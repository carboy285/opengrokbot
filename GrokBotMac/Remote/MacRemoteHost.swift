import AppKit
import Darwin
import Combine
import Foundation
import Security

@MainActor
final class MacRemoteHost: ObservableObject {
    enum Mode: String, CaseIterable, Identifiable {
        case tailscale = "Tailscale · private", funnel = "Tailscale Funnel · public HTTPS", wifi = "Wi-Fi / private IP", proxy = "My HTTPS proxy"
        var id: String { rawValue }
    }
    @Published var mode: Mode
    @Published var address: String
    @Published private(set) var enabled = false
    @Published private(set) var changing = false
    @Published private(set) var feedback: String?
    let port: UInt16
    private let preferences: UserDefaults
    private var token = ""
    private var revision = UUID().uuidString
    private let server = LocalHTTPServer()
    private let secrets: KeychainSecretStore
    private weak var app: AppModel?
    private weak var desktop: MacAppModel?
    private var subscriptions: Set<AnyCancellable> = []
    private var receipts: Set<UUID> = []
    private var ownedRoute: (String,Bool)?

    init(port: UInt16 = 48291, preferences: UserDefaults = .standard, secrets: KeychainSecretStore = KeychainSecretStore(service: "org.opengrokbot.remote-host")) {
        self.port = port; self.preferences = preferences; self.secrets = secrets
        mode = Mode(rawValue: preferences.string(forKey: "remoteMode") ?? "") ?? .tailscale
        address = preferences.string(forKey: "remoteAddress") ?? ""
        if let route = preferences.string(forKey: "remoteOwnedRoute") { ownedRoute = (route, preferences.bool(forKey: "remoteOwnedFunnel")) }
    }

    var needsCleanup: Bool { !enabled && ownedRoute != nil }
    var pairing: RemotePairing? { enabled ? try? RemotePairing(address: address, token: token) : nil }
    var serveCommand: String { "tailscale \(mode == .funnel ? "funnel" : "serve") --bg --https=8443 http://127.0.0.1:\(port)" }

    func attach(app: AppModel, desktop: MacAppModel) {
        guard self.app == nil else { return }; self.app = app; self.desktop = desktop
        app.$workspace.sink { [weak self] _ in self?.revision = UUID().uuidString }.store(in: &subscriptions)
        desktop.$runningBots.sink { [weak self] _ in self?.revision = UUID().uuidString }.store(in: &subscriptions)
        desktop.$installedCLIs.sink { [weak self] _ in self?.revision = UUID().uuidString }.store(in: &subscriptions)
        desktop.$selectedCLIID.sink { [weak self] _ in self?.revision = UUID().uuidString }.store(in: &subscriptions)
        if preferences.bool(forKey: "remoteEnabled") { ownedRoute = nil; start() }
    }
    func start() {
        guard !enabled, !changing, app != nil else { return }
        if ownedRoute != nil { feedback = "Remove the previous Tailscale route before enabling a different connection."; return }
        do {
            if let data = try secrets.read(account: "pairing"), let saved = String(data: data, encoding: .utf8), saved.range(of:"^[A-Za-z0-9_-]{43,128}$",options:.regularExpression) != nil { token = saved }
            else { try replaceToken() }
            if mode == .wifi, address.isEmpty { address = "http://\(Self.localIPv4() ?? "your-mac.local"):\(port)" }
            if mode == .proxy || mode == .wifi { _ = try RemotePairing(address: address, token: token); if mode == .proxy && URL(string: address)?.scheme != "https" { throw RemoteError.invalidPairing } }
        } catch { feedback = "Unlock Keychain and enter a valid host address, then try again."; return }
        changing = true; feedback = nil
        let lan = mode == .wifi
        server.start(port: port, lan: lan, handler: { [weak self] request in
            await self?.handle(request) ?? .error(503, "Host is unavailable")
        }, ready: { [weak self] success in
            Task { @MainActor in
                guard let self else { return }
                self.changing = false; self.enabled = success
                if success {
                    self.preferences.set(true, forKey: "remoteEnabled")
                    if self.mode == .tailscale || self.mode == .funnel { self.configureTailscale() }
                    else { self.savePreferences(); self.feedback = "Remote access is on. Pair your iPhone using this desktop’s link." }
                } else { self.feedback = "Port \(self.port) is unavailable. Stop the other service or restart this app." }
            }
        })
    }
    func stop() {
        server.stop(); enabled = false; preferences.set(false, forKey: "remoteEnabled")
        guard let route = ownedRoute else { feedback = "Remote access is off."; return }
        changing = true
        Task {
            let port = port
            let removed = await Task.detached { TailscaleHosting.remove(localPort: port, address: route.0, funnel: route.1) }.value
            changing = false
            if removed { ownedRoute = nil; preferences.removeObject(forKey: "remoteOwnedRoute"); preferences.removeObject(forKey: "remoteOwnedFunnel"); feedback = "Remote access is off." }
            else { feedback = "The app server is off. Remove its port 8443 route in Tailscale before changing connection modes." }
        }
    }
    func rotateKey() {
        do { try replaceToken(); receipts.removeAll(); feedback = "Pairing key changed. Existing phones must pair again." }
        catch { feedback = "The pairing key could not be changed. Unlock Keychain and try again." }
    }
    func copyLink() {
        guard let link = pairing?.link.absoluteString else { return }
        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(link, forType: .string)
        feedback = "Pairing link copied. Treat it like a password; it controls this workspace."
    }
    func configureTailscale() {
        guard enabled, !changing else { return }; changing = true
        let port = port, funnel = mode == .funnel
        Task {
            let link = await Task.detached { TailscaleHosting.configure(localPort: port, funnel: funnel) }.value
            changing = false
            if let link { address = link; ownedRoute = (link,funnel); preferences.set(link,forKey:"remoteOwnedRoute"); preferences.set(funnel,forKey:"remoteOwnedFunnel"); savePreferences(); feedback = funnel ? "Funnel HTTPS is ready. Your pairing key is still required." : "Private Tailscale HTTPS is ready. Connect your iPhone to the same tailnet." }
            else { feedback = "Tailscale needs setup or port 8443 is already in use. Use the command below in Terminal, authorize Tailscale if asked, then enter its HTTPS address. Existing routes are not overwritten." }
        }
    }
    func saveAddress() {
        guard (mode == .wifi || URL(string: address)?.scheme == "https"), (try? RemotePairing(address: address, token: token)) != nil else { feedback = "Enter an HTTPS address, or a private Wi-Fi address in Wi-Fi mode."; return }
        if mode == .tailscale || mode == .funnel { ownedRoute = (address,mode == .funnel); preferences.set(address,forKey:"remoteOwnedRoute"); preferences.set(mode == .funnel,forKey:"remoteOwnedFunnel") }
        savePreferences(); feedback = "Pairing address saved."
    }
    private func savePreferences() {
        preferences.set(mode.rawValue, forKey: "remoteMode"); preferences.set(address, forKey: "remoteAddress")
    }
    private func replaceToken() throws {
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else { throw RemoteError.unavailable }
        let value = bytes.map { String(format: "%02x", $0) }.joined()
        try secrets.save(Data(value.utf8), account: "pairing"); token = value
    }
    private func snapshot() -> RemoteSnapshot? {
        guard let app, let desktop else { return nil }
        var workspace = app.workspace; workspace.sessions = nil
        return RemoteSnapshot(hostName: Host.current().localizedName ?? "Mac", revision: revision, workspace: workspace, running: Array(desktop.runningBots), providers: desktop.installedCLIs.map { RemoteProvider(provider: $0.provider, version: $0.version) }, defaultProvider: desktop.selectedCLI?.provider)
    }
    private func handle(_ request: HostHTTPRequest) async -> HostHTTPResponse {
        guard enabled else { return .error(503, "Remote access is off") }
        guard request.authorized(token: token) else { return .error(401, "Pairing key required") }
        guard let parts = URLComponents(string: request.target), let app, let desktop else { return .error(400, "Invalid request") }
        func query(_ name: String) -> String? { parts.queryItems?.first { $0.name == name }?.value }
        do {
            if request.method == "GET", parts.path == "/v1/state", let snapshot = snapshot() {
                return query("since") == revision ? HostHTTPResponse(status: 204) : try .json(snapshot)
            }
            if request.method == "GET", parts.path == "/v1/models", let provider = query("provider").flatMap(CLIProvider.init(rawValue:)), let cli = desktop.installedCLIs.first(where: { $0.provider == provider }) {
                let models = await Task.detached { CLIModelCatalog.models(for: cli) }.value
                return try .json(models)
            }
            if request.method == "GET", parts.path == "/v1/files", let bot = app.workspace.bots.first(where: { $0.id.uuidString.lowercased() == query("bot")?.lowercased() }) {
                let folder = desktop.workingDirectory(for: bot)
                let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isRegularFileKey,.isSymbolicLinkKey], options: [.skipsHiddenFiles])) ?? []
                return try .json(files.filter { url in let flags = try? url.resourceValues(forKeys: [.isRegularFileKey,.isSymbolicLinkKey]); return flags?.isRegularFile == true && flags?.isSymbolicLink != true }.prefix(500).map { RemoteFile(name: $0.lastPathComponent) })
            }
            guard request.method == "POST", parts.path == "/v1/command" else { return .error(404, "Unknown endpoint") }
            let command = try JSONDecoder().decode(RemoteCommand.self, from: request.body)
            if receipts.contains(command.requestID) || app.workspace.entries.contains(where: { $0.id == command.requestID }) { return try .json(["accepted":true]) }
            let bot = app.workspace.bots.first { $0.id == command.botID }
            switch command.action {
            case "send":
                guard let bot, let text = command.text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, text.count <= 100000, desktop.send(text, to: bot, app: app, requestID: command.requestID) else { return .error(409, "The Bot is busy or needs provider setup. Check the desktop workspace.") }
            case "stop": guard let bot else { return .error(404,"Bot not found") }; desktop.stop(botID: bot.id)
            case "retry": guard let bot, !desktop.runningBots.contains(bot.id) else { return .error(409,"Bot is busy") }; desktop.retry(bot: bot, app: app)
            case "create_bot":
                guard let name = command.name, name.count <= 200, let purpose = command.purpose, purpose.count <= 2000, ["white","purple","pink","ochre"].contains(command.color ?? ""), app.workspace.bots.count < 100, app.addBot(name: name, purpose: purpose, color: command.color!) else { return .error(409,"Use a unique Bot name and a short description") }
            case "delete_bot": guard let bot, bot.isMain != true else { return .error(409,"The main Grok Bot must be kept") }; desktop.stop(botID: bot.id); app.removeBot(bot)
            case "configure_bot":
                guard let bot, let config = command.configuration, !desktop.runningBots.contains(bot.id), app.setAIConfiguration(config, for: bot) else { return .error(409,"Stop the Bot before changing its provider or model") }
            default: return .error(400,"Unsupported command")
            }
            if receipts.count >= 256 { receipts.removeAll() }; receipts.insert(command.requestID)
            revision = UUID().uuidString
            return try .json(["accepted":true])
        } catch { return .error(400,"The request could not be completed") }
    }
    private static func localIPv4() -> String? {
        var pointer: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&pointer) == 0 else { return nil }; defer { freeifaddrs(pointer) }
        var item = pointer
        while let current = item {
            defer { item = current.pointee.ifa_next }
            guard let addr = current.pointee.ifa_addr, addr.pointee.sa_family == UInt8(AF_INET), String(cString: current.pointee.ifa_name) != "lo0" else { continue }
            var name = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            if getnameinfo(addr, socklen_t(addr.pointee.sa_len), &name, socklen_t(name.count), nil, 0, NI_NUMERICHOST) == 0 {
                let ip = String(cString: name); if RemotePairing.isLocalHost(ip) { return ip }
            }
        }
        return nil
    }
}
