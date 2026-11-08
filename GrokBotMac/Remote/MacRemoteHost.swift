import AppKit
import Combine
import Foundation

@MainActor
final class MacRemoteHost: ObservableObject {
    let account: CloudAccount
    @Published private(set) var enabled = false
    @Published private(set) var feedback: String?
    @Published private(set) var connectionState = "Signed out"
    @Published private(set) var lastHeartbeat: Date?
    @Published private(set) var lastPhoneRequest: Date?
    @Published var pendingPhoneApproval: CloudDevice?
    private let preferences: UserDefaults
    private var revision = UUID().uuidString
    private weak var app: AppModel?
    private weak var desktop: MacAppModel?
    private var subscriptions: Set<AnyCancellable> = []
    private var receipts: Set<UUID> = []
    private var polling: Task<Void,Never>?
    private var pinPolling: Task<Void,Never>?
    @Published private(set) var pinSyncNotice: String?
    private var baselines: [UUID:RemoteSnapshot] = [:]
    private var replies: [String:CloudResponse] = [:]
    private var owner: UUID?
    private var promptedPhones: Set<UUID> = []
    init(preferences: UserDefaults = .standard, account: CloudAccount = CloudAccount(kind: "host")) {
        self.preferences = preferences; self.account = account
        receipts = Set((preferences.stringArray(forKey:"cloudCommandReceipts") ?? []).compactMap(UUID.init(uuidString:)))
        account.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &subscriptions)
    }
    func attach(app: AppModel, desktop: MacAppModel) {
        guard self.app == nil else { return }; self.app = app; self.desktop = desktop
        MacApproval.shared.onChange = { [weak self] in self?.revision = UUID().uuidString }
        app.$workspace.sink { [weak self] _ in self?.revision = UUID().uuidString }.store(in: &subscriptions)
        desktop.$runningBots.sink { [weak self] _ in self?.revision = UUID().uuidString }.store(in: &subscriptions)
        desktop.$installedCLIs.sink { [weak self] _ in self?.revision = UUID().uuidString }.store(in: &subscriptions)
        desktop.$selectedCLIID.sink { [weak self] _ in self?.revision = UUID().uuidString }.store(in: &subscriptions)
        account.$session.map { $0?.user.id }.removeDuplicates().sink { [weak self] id in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if self.owner != id {
                    // Signing out must stop the relay without turning an unset preference
                    // into an explicit opt-out for the next sign-in.
                    self.stop(persistPreference: false)
                    self.owner = id; self.replies = [:]; self.baselines = [:]; self.promptedPhones = []
                }
                self.startPinSync()
                if id != nil, (self.preferences.object(forKey: "cloudHostEnabled") as? Bool ?? true) { self.start() }
            }
        }.store(in: &subscriptions)
    }
    private var pendingPinKey: String? {
        guard let owner = account.session?.user.id, let host = account.identity?.id else { return nil }
        return "server-pin-intents-" + owner.uuidString + "-" + host.uuidString
    }
    func setPinned(_ bot: Bot, pinned: Bool) {
        guard let app else { return }
        if app.organize(bot, pinned: pinned), let key = pendingPinKey {
            var pending = preferences.dictionary(forKey: key) as? [String:Bool] ?? [:]
            pending[bot.id.uuidString] = pinned; preferences.set(pending, forKey: key)
        }
    }
    private func startPinSync() {
        pinPolling?.cancel(); pinPolling = nil
        guard let owner = account.session?.user.id, let host = account.identity?.id, let key = pendingPinKey else { return }
        pinPolling = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, let app = self.app, self.account.session?.user.id == owner else { return }
                do {
                    if self.account.localDevice == nil { try await self.account.sync(available: self.enabled) }
                    try Task.checkCancellation()
                    let pending = self.preferences.dictionary(forKey: key) as? [String:Bool] ?? [:]
                    for (id, value) in pending {
                        guard let bot = UUID(uuidString: id) else { continue }
                        _ = try await self.account.setBotPin(host: host, bot: bot, pinned: value)
                        guard self.account.session?.user.id == owner else { return }; try Task.checkCancellation()
                        var latest = self.preferences.dictionary(forKey: key) as? [String:Bool] ?? [:]
                        if latest[id] == value { latest[id] = nil; self.preferences.set(latest, forKey: key) }
                    }
                    var rows = try await self.account.botPins(host: host)
                    let existing = Set(rows.map(\.bot_id))
                    for bot in app.workspace.bots where !existing.contains(bot.id) && (bot.isPinned != nil || bot.isMain == true) {
                        rows.append(try await self.account.setBotPin(host: host, bot: bot.id, pinned: bot.isPinned ?? (bot.isMain == true), onlyIfMissing: true))
                    }
                    guard self.account.session?.user.id == owner else { return }; try Task.checkCancellation()
                    let dirty = self.preferences.dictionary(forKey: key) as? [String:Bool] ?? [:]
                    for row in rows where dirty[row.bot_id.uuidString] == nil {
                        if let bot = app.workspace.bots.first(where: { $0.id == row.bot_id }), (bot.isPinned ?? (bot.isMain == true)) != row.is_pinned {
                            _ = app.organize(bot, pinned: row.is_pinned)
                        }
                    }
                    self.pinSyncNotice = nil
                } catch {
                    if Task.isCancelled || self.account.session?.user.id != owner { return }
                    self.pinSyncNotice = "Pins are saved locally and will sync when the account service reconnects."
                }
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }
    func start() {
        guard account.signedIn, app != nil, !enabled else { return }
        enabled = true; preferences.set(true,forKey:"cloudHostEnabled"); feedback = "Connecting to your account…"; connectionState = "Connecting"
        polling = Task { [weak self] in
            var nextHeartbeat = Date.distantPast
            var lastRequest = Date.distantPast
            var retryDelay = 1000
            while !Task.isCancelled {
                guard let self, self.enabled else { return }
                var retrying = false
                do {
                    if Date() >= nextHeartbeat {
                        try await self.account.sync(available:true)
                        nextHeartbeat = Date().addingTimeInterval(20); self.lastHeartbeat = Date()
                    }
                    let packets = try await self.account.poll()
                    if !packets.isEmpty { lastRequest = Date() }
                    for packet in packets {
                        try Task.checkCancellation()
                        // A phone can register between heartbeats. Discover it before
                        // discarding its first request, including its approval request.
                        if !self.account.controllers.contains(where: { $0.id == packet.sender }) {
                            try await self.account.sync(available: true)
                        }
                        try Task.checkCancellation()
                        guard let peer = self.account.controllers.first(where: { $0.id == packet.sender }) else { try? await self.account.acknowledge(packet); continue }
                        if !self.account.approved(peer) {
                            guard packet.kind == "request", (try? self.account.decrypt(packet, peer: peer)) != nil else {
                                try? await self.account.acknowledge(packet); continue
                            }
                            if self.pendingPhoneApproval == nil, self.promptedPhones.insert(peer.id).inserted {
                                self.pendingPhoneApproval = peer
                            }
                            self.connectionState = "Waiting for device approval"
                            let denied = RemoteHostResponse.error(403,"Approve this device in Mac Settings → Computer. Compare its fingerprint before approving.")
                            try? await self.account.send(CloudCoding.encoder().encode(CloudResponse(status:denied.status,body:denied.body)),to:peer,id:packet.id,kind:"response")
                            try? await self.account.acknowledge(packet); continue
                        }
                        do {
                            let data = try self.account.decrypt(packet,peer:peer)
                            self.lastPhoneRequest = Date(); self.connectionState = "Connected"
                            guard packet.kind == "request" else { throw CloudError.invalidPacket }
                            let cacheKey = peer.id.uuidString + packet.id.uuidString
                            let response: CloudResponse
                            if let cached = self.replies[cacheKey] { response = cached }
                            else {
                                if let request = try? CloudCoding.decoder().decode(CloudRequest.self,from:data), request.target.count <= 2048, request.body.count <= 3_500_000 {
                                    response = await self.respond(request,peer:peer)
                                } else {
                                    let error = RemoteHostResponse.error(400, "The remote request format is unsupported. Update both devices to 0.7.2.")
                                    response = CloudResponse(status: error.status, body: error.body)
                                }
                                if response.body.count <= 128_000 { if self.replies.count >= 128 { self.replies.removeAll() }; self.replies[cacheKey] = response }
                            }
                            // An approval revoked while a CLI model lookup awaited must also block its result.
                            guard self.enabled, self.account.approved(peer) else { continue }
                            let encoded = try CloudCoding.encoder().encode(response)
                            if encoded.count <= 5_900_000 {
                                try await self.account.send(encoded,to:peer,id:packet.id,kind:"response")
                            } else {
                                let error = RemoteHostResponse.error(413, "This computer's workspace is too large for the encrypted relay. Export older conversations on the host and try again.")
                                try await self.account.send(CloudCoding.encoder().encode(CloudResponse(status: error.status, body: error.body)),to:peer,id:packet.id,kind:"response")
                            }
                            try await self.account.acknowledge(packet)
                        } catch { try? await self.account.acknowledge(packet) }
                    }
                    if self.connectionState != "Waiting for device approval" { self.connectionState = self.lastPhoneRequest.map { Date().timeIntervalSince($0) < 10 ? "Connected" : "Ready for approved phones" } ?? "Ready for approved phones" }
                    let message = self.connectionState == "Waiting for device approval" ? "Compare the device’s fingerprint below, then choose Approve device." : "Phone access is ready. Keep this Mac awake."
                    retryDelay = 1000
                    if self.feedback != message { self.feedback = message }
                } catch { if Task.isCancelled || !self.enabled { return }; self.connectionState = "Offline · retrying"; self.feedback = error.localizedDescription; nextHeartbeat = .distantPast; retrying = true; retryDelay = min(15000, retryDelay * 2) }
                let interval: Duration = retrying ? .milliseconds(retryDelay) : Date().timeIntervalSince(lastRequest) < 10 ? .milliseconds(250) : .milliseconds(700)
                try? await Task.sleep(for: interval)
            }
        }
    }
    func stop(persistPreference: Bool = true) {
        enabled = false; polling?.cancel(); polling = nil; baselines = [:]; replies = [:]
        pendingPhoneApproval = nil
        if persistPreference { preferences.set(false,forKey:"cloudHostEnabled") }
        feedback = "Phone access is off."; connectionState = account.signedIn ? "Phone access off" : "Signed out"
        // The registered host expires as offline even if this update cannot reach the network.
        Task { if !enabled, account.signedIn { try? await account.sync(available:false) } }
    }
    func reconnect() { guard account.signedIn else { return }; stop(persistPreference: false); start() }
    var diagnostics: String {
        let formatter = ISO8601DateFormatter()
        let values: [String: String] = ["state": connectionState, "phoneAccess": String(enabled), "lastHeartbeat": lastHeartbeat.map(formatter.string(from:)) ?? "none", "lastPhoneRequest": lastPhoneRequest.map(formatter.string(from:)) ?? "none", "approvedPhones": String(account.controllers.filter { account.approved($0) }.count)]
        return (try? String(data: JSONEncoder().encode(values), encoding: .utf8)) ?? "Connection diagnostics unavailable."
    }
    func approve(_ device: CloudDevice, allowed: Bool) {
        do {
            try account.approve(device,allowed:allowed); baselines[device.id] = nil; replies = [:]
            connectionState = enabled ? "Ready for approved phones" : "Phone access off"
            if pendingPhoneApproval?.id == device.id { pendingPhoneApproval = nil }
        }
        catch { feedback = error.localizedDescription }
    }
    private func respond(_ request: CloudRequest, peer: CloudDevice) async -> CloudResponse {
        if request.method == "GET", let parts = URLComponents(string:request.target), parts.path == "/v1/state", let next = snapshot() {
            if parts.queryItems?.contains(where: { $0.name == "overview" && $0.value == "true" }) == true {
                do { return CloudResponse(status: 200, body: try CloudCoding.encoder().encode(CloudStatePatch(snapshot: next.botOverview(), baseRevision: nil, removedEntries: []))) }
                catch { return CloudResponse(status: 500, body: Data()) }
            }
            let since = parts.queryItems?.first(where:{$0.name == "since"})?.value
            if since == next.revision { return CloudResponse(status:204,body:Data()) }
            let baseline = baselines[peer.id].flatMap { $0.revision == since ? $0:nil }
            do {
                let patch = try CloudStatePatch.make(next,previous:baseline)
                let data = try CloudCoding.encoder().encode(patch); baselines[peer.id] = next
                return CloudResponse(status:200,body:data)
            } catch {
                let error = RemoteHostResponse.error(500, "The hosting computer could not prepare its workspace. Open it on the host and resolve any saved-workspace error before reconnecting.")
                return CloudResponse(status: error.status, body: error.body)
            }
        }
        let response = await dispatch(RemoteHostRequest(method:request.method,target:request.target,body:request.body))
        return CloudResponse(status:response.status,body:response.body)
    }
    private func snapshot() -> RemoteSnapshot? {
        guard let app, let desktop else { return nil }
        var workspace = app.workspace; workspace.sessions = nil
        workspace.entries = workspace.entries.map { var entry = $0; entry.detail = nil; return entry } // The phone shows summaries only.
        return RemoteSnapshot(hostName: Host.current().localizedName ?? "Mac", revision: revision, workspace: workspace, running: Array(desktop.runningBots), providers: desktop.installedCLIs.map { RemoteProvider(provider: $0.provider, version: $0.version) }, defaultProvider: desktop.selectedCLI?.provider, approval: MacApproval.shared.remoteRequest)
    }
    func dispatch(_ request: RemoteHostRequest) async -> RemoteHostResponse {
        guard let parts = URLComponents(string: request.target), let app, let desktop else { return .error(400, "Invalid request") }
        func query(_ name: String) -> String? { parts.queryItems?.first { $0.name == name }?.value }
        do {
            if request.method == "GET", parts.path == "/v1/state", let snapshot = snapshot() {
                return query("since") == revision ? RemoteHostResponse(status: 204) : try .json(snapshot)
            }
            if request.method == "GET", parts.path == "/v1/vm", let bot = app.workspace.bots.first(where: { $0.id.uuidString.lowercased() == query("bot")?.lowercased() }) {
                return try .json(try await MacBotVMs.shared.preview(bot))
            }
            if request.method == "GET", parts.path == "/v1/browser", let bot = app.workspace.bots.first(where: { $0.id.uuidString.lowercased() == query("bot")?.lowercased() }) {
                return try .json(try await LocalBotBrowsers.shared.preview(bot))
            }
            if request.method == "GET", parts.path == "/v1/bot-package", let bot = app.workspace.bots.first(where: { $0.id.uuidString.lowercased() == query("bot")?.lowercased() }), bot.memberIDs == nil {
                guard let data = desktop.packageForCopy(bot, app: app) else { return .error(500, "The Bot could not be packaged.") }
                return RemoteHostResponse(status: 200, body: data)
            }
            if request.method == "GET", parts.path == "/v1/host-settings" {
                var keys: [String: Bool] = [:]
                for provider in CLIProvider.allCases where ProviderAPIKeys.info(for: provider) != nil { keys[provider.rawValue] = ProviderAPIKeys.get(provider) != nil }
                var voice: [String: Bool] = [:]
                for provider in VoiceProvider.allCases where provider != .apple { voice[provider.rawValue] = !VoiceKeys.get(provider).isEmpty }
                let settings = RemoteHostSettings(
                    hostName: Host.current().localizedName ?? "Mac", platform: "mac", appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown",
                    providers: desktop.installedCLIs.map { RemoteProvider(provider: $0.provider, version: $0.version) }, defaultProvider: desktop.selectedCLI?.provider,
                    apiKeys: keys, voiceKeys: voice,
                    connectors: RemoteHostSettings.Connectors(configured: desktop.composio.configured, toolkits: desktop.composio.exportConfiguration()?.toolkits ?? []),
                    sharing: SettingsBundle.sharingAllowed)
                return try .json(settings)
            }
            if request.method == "GET", parts.path == "/v1/bundle" {
                guard SettingsBundle.sharingAllowed else { return .error(409, "“Share keys and connectors” is off on this computer. Turn it on in the Computers screen, then try again.") }
                guard let data = try? desktop.makeSettingsBundle().encoded() else { return .error(500, "The settings could not be packaged.") }
                return RemoteHostResponse(status: 200, body: data)
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
            case "touch_bot":
                guard let bot, app.touchBot(bot.id) else { return .error(404, "Bot not found") }
            case "open_vm":
                guard let bot, MacBotVMs.shared.assigned(bot.id) != nil else { return .error(409, "Set up this Bot’s Linux VM on the host desktop first.") }
                await MacBotVMs.shared.open(bot)
            case "open_browser":
                guard let bot else { return .error(404, "Bot not found") }
                _ = try LocalBotBrowsers.shared.open(bot, address: command.text)  // the phone shows a preview; no window opens on the Mac
            case "cancel_task":
                guard let id = command.botID, let taskID = command.taskID, app.removeSchedule(taskID, botID: id) else { return .error(400, "Task could not be cancelled.") }
            case "update_avatar":
                guard let bot, app.setAppearance(command.appearance, for: bot) else { return .error(400, "Choose a valid Bot avatar with an image under 24 KB.") }
            case "send":
                guard let bot, let text = command.text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, text.count <= 100000 else { return .error(409, "The Bot is busy or needs provider setup. Check the desktop workspace.") }
                var message = text
                if let images = command.attachments, !images.isEmpty {
                    guard let names = desktop.saveRemoteAttachments(images, for: bot) else { return .error(400, "The images couldn’t be accepted. Send up to 3 JPEG or PNG images under 2.4 MB in total.") }
                    message = MacAppModel.attachmentMessage(base: text, names: names)
                }
                guard desktop.send(message, to: bot, app: app, requestID: command.requestID) else { return .error(409, "The Bot is busy or needs provider setup. Check the desktop workspace.") }
            case "approval_response":
                guard let text = command.text, let id = UUID(uuidString: text), MacApproval.shared.respondFromPhone(id: id, approved: command.name == "approve") else { return .error(409, "That request is no longer waiting.") }
            case "set_api_key":
                guard SettingsBundle.sharingAllowed else { return .error(409, "Turn on “Share keys and connectors” on this computer first (Computers screen).") }
                guard let name = command.name, let provider = CLIProvider(rawValue: name), ProviderAPIKeys.info(for: provider) != nil else { return .error(400, "Choose a provider that uses an API key.") }
                let key = (command.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                if key.isEmpty { try? ProviderAPIKeys.remove(provider) }
                else if (try? ProviderAPIKeys.save(key, for: provider)) != true { return .error(400, "That key does not look right (no spaces, 8 to 512 characters).") }
            case "import_settings":
                guard SettingsBundle.sharingAllowed else { return .error(409, "“Share keys and connectors” is off on this computer. Turn it on in the Computers screen, then try again.") }
                guard let data = command.package, let bundle = try? SettingsBundle.decode(data) else { return .error(400, "That settings bundle could not be read.") }
                let result = await desktop.applySettingsBundle(bundle)
                if result.contains("could not") { return .error(409, result) }
            case "import_bot":
                guard let data = command.package else { return .error(400, "No Bot was sent.") }
                do { _ = try desktop.importBotPackage(data, into: app) } catch { return .error(409, (error as? LocalizedError)?.errorDescription ?? "The Bot could not be copied.") }
            case "stop": guard let bot else { return .error(404,"Bot not found") }; desktop.stop(botID: bot.id)
            case "retry": guard let bot, !desktop.runningBots.contains(bot.id) else { return .error(409,"Bot is busy") }; desktop.retry(bot: bot, app: app)
            case "create_bot":
                let colors = ["purple", "pink", "red", "orange", "amber", "green", "teal", "blue", "gray", "black"]
                let legacy = ["white", "purple", "pink", "ochre"]
                // Older phones send one of four colours; newer ones also send a shape and one of ten colours.
                guard let name = command.name, name.count <= 200, let purpose = command.purpose, purpose.count <= 2000,
                      legacy.contains(command.color ?? "") || command.appearance.map({ colors.contains($0.color) }) == true,
                      app.workspace.bots.count < 100,
                      app.addBot(name: name, purpose: purpose, color: legacy.contains(command.color ?? "") ? command.color! : "purple") else { return .error(409,"Use a unique Bot name and a short description") }
                if let appearance = command.appearance, colors.contains(appearance.color), let created = app.workspace.bots.last(where: { $0.name == name }) { app.setAppearance(BotAppearance(shape: appearance.shape, color: appearance.color), for: created) }
            case "react":
                guard let id = command.taskID, (command.text ?? "").count <= 8, app.setReaction((command.text ?? "").isEmpty ? nil : command.text, for: id) else { return .error(409,"That message could not be updated") }
            case "delete_entry":
                guard let id = command.taskID, app.deleteEntry(id) else { return .error(409,"That message could not be deleted") }
            case "delete_bot": guard let bot, bot.isMain != true else { return .error(409,"The main Grok Bot must be kept") }; desktop.stop(botID: bot.id); app.removeBot(bot)
            case "configure_bot":
                guard let bot, let config = command.configuration, !desktop.runningBots.contains(bot.id), app.setAIConfiguration(config, for: bot) else { return .error(409,"Stop the Bot before changing its provider or model") }
            default: return .error(400,"Unsupported command")
            }
            if receipts.count >= 256 { receipts.removeAll() }; receipts.insert(command.requestID)
            preferences.set(receipts.map(\.uuidString),forKey:"cloudCommandReceipts")
            revision = UUID().uuidString
            return try .json(["accepted":true])
        } catch { if let cloud = error as? CloudError { return .error(409, cloud.localizedDescription) }; return .error(400,"The request could not be completed") }
    }
}
