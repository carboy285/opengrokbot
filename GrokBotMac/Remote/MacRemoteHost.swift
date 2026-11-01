import AppKit
import Combine
import Foundation

@MainActor
final class MacRemoteHost: ObservableObject {
    let account: CloudAccount
    @Published private(set) var enabled = false
    @Published private(set) var feedback: String?
    private let preferences: UserDefaults
    private var revision = UUID().uuidString
    private weak var app: AppModel?
    private weak var desktop: MacAppModel?
    private var subscriptions: Set<AnyCancellable> = []
    private var receipts: Set<UUID> = []
    private var polling: Task<Void,Never>?
    private var baselines: [UUID:RemoteSnapshot] = [:]
    private var replies: [String:CloudResponse] = [:]
    private var owner: UUID?
    init(preferences: UserDefaults = .standard, account: CloudAccount = CloudAccount(kind: "host")) {
        self.preferences = preferences; self.account = account
        account.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &subscriptions)
    }
    func attach(app: AppModel, desktop: MacAppModel) {
        guard self.app == nil else { return }; self.app = app; self.desktop = desktop
        app.$workspace.sink { [weak self] _ in self?.revision = UUID().uuidString }.store(in: &subscriptions)
        desktop.$runningBots.sink { [weak self] _ in self?.revision = UUID().uuidString }.store(in: &subscriptions)
        desktop.$installedCLIs.sink { [weak self] _ in self?.revision = UUID().uuidString }.store(in: &subscriptions)
        desktop.$selectedCLIID.sink { [weak self] _ in self?.revision = UUID().uuidString }.store(in: &subscriptions)
        account.$session.map { $0?.user.id }.removeDuplicates().sink { [weak self] id in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if self.owner != id { let restore = self.preferences.bool(forKey:"cloudHostEnabled"); self.stop(); self.preferences.set(restore,forKey:"cloudHostEnabled"); self.owner = id; self.replies = [:]; self.baselines = [:] }
                if id != nil, self.preferences.bool(forKey: "cloudHostEnabled") { self.start() }
            }
        }.store(in: &subscriptions)
    }
    func start() {
        guard account.signedIn, app != nil, !enabled else { return }
        enabled = true; preferences.set(true,forKey:"cloudHostEnabled"); feedback = "Connecting to your account…"
        polling = Task { [weak self] in
            var ticks = 0
            while !Task.isCancelled {
                guard let self, self.enabled else { return }
                do {
                    if ticks % 15 == 0 { try await self.account.sync(available:true) }
                    let packets = try await self.account.poll()
                    for packet in packets {
                        try Task.checkCancellation()
                        guard let peer = self.account.controllers.first(where: { $0.id == packet.sender }), self.account.approved(peer) else { try? await self.account.acknowledge(packet); continue }
                        do {
                            let data = try self.account.decrypt(packet,peer:peer)
                            guard packet.kind == "request" else { throw CloudError.invalidPacket }
                            let cacheKey = peer.id.uuidString + packet.id.uuidString
                            let response: CloudResponse
                            if let cached = self.replies[cacheKey] { response = cached }
                            else {
                                let request = try CloudCoding.decoder().decode(CloudRequest.self,from:data)
                                guard packet.kind == "request", request.target.count <= 2048, request.body.count <= 131072 else { throw CloudError.invalidPacket }
                                response = await self.respond(request,peer:peer)
                                if self.replies.count >= 128 { self.replies.removeAll() }; self.replies[cacheKey] = response
                            }
                            // An approval revoked while a CLI model lookup awaited must also block its result.
                            guard self.enabled, self.account.approved(peer) else { continue }
                            try await self.account.send(CloudCoding.encoder().encode(response),to:peer,id:packet.id,kind:"response")
                            try await self.account.acknowledge(packet)
                        } catch { try? await self.account.acknowledge(packet) }
                    }
                    self.feedback = "Phone access is on. Approve a phone below to allow control."
                    ticks += 1
                } catch { self.feedback = error.localizedDescription; ticks = 0 }
                try? await Task.sleep(for:.seconds(1))
            }
        }
    }
    func stop() {
        enabled = false; polling?.cancel(); polling = nil; baselines = [:]; replies = [:]
        preferences.set(false,forKey:"cloudHostEnabled"); feedback = "Phone access is off."
        // The registered host expires as offline even if this update cannot reach the network.
        Task { if account.signedIn { try? await account.sync(available:false) } }
    }
    func approve(_ device: CloudDevice, allowed: Bool) {
        do { try account.approve(device,allowed:allowed); baselines[device.id] = nil; replies = [:] }
        catch { feedback = error.localizedDescription }
    }
    private func respond(_ request: CloudRequest, peer: CloudDevice) async -> CloudResponse {
        if request.method == "GET", let parts = URLComponents(string:request.target), parts.path == "/v1/state", let next = snapshot() {
            let since = parts.queryItems?.first(where:{$0.name == "since"})?.value
            if since == next.revision { return CloudResponse(status:204,body:Data()) }
            let baseline = baselines[peer.id].flatMap { $0.revision == since ? $0:nil }
            do {
                let patch = try CloudStatePatch.make(next,previous:baseline)
                let data = try CloudCoding.encoder().encode(patch); baselines[peer.id] = next
                return CloudResponse(status:200,body:data)
            } catch { return CloudResponse(status:500,body:Data()) }
        }
        let response = await dispatch(HostHTTPRequest(method:request.method,target:request.target,headers:[:],body:request.body))
        return CloudResponse(status:response.status,body:response.body)
    }
    private func snapshot() -> RemoteSnapshot? {
        guard let app, let desktop else { return nil }
        var workspace = app.workspace; workspace.sessions = nil
        return RemoteSnapshot(hostName: Host.current().localizedName ?? "Mac", revision: revision, workspace: workspace, running: Array(desktop.runningBots), providers: desktop.installedCLIs.map { RemoteProvider(provider: $0.provider, version: $0.version) }, defaultProvider: desktop.selectedCLI?.provider)
    }
    func dispatch(_ request: HostHTTPRequest) async -> HostHTTPResponse {
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
}
