import Foundation
import SwiftUI
import Combine

@MainActor
final class RemoteController: ObservableObject {
    let account: CloudAccount
    @Published private(set) var online = false
    @Published private(set) var hasSnapshot = false
    @Published private(set) var needsApproval = false
    @Published private(set) var hostName = "Desktop"
    @Published private(set) var status = "Sign in to connect your desktop"
    @Published private(set) var running: Set<UUID> = []
    @Published private(set) var providers: [RemoteProvider] = []
    @Published private(set) var defaultProvider: CLIProvider?
    @Published private(set) var pinnedBotIDs: [UUID]?
    @Published private(set) var pinSyncNotice: String?
    private var serverPins: [UUID:Bool] = [:]
    private var pendingPins: [UUID:Bool] = [:]
    private var legacyPins = Set<UUID>()
    private var syncingPins = false
    @Published var showConnection = false
    @Published var busy = false
    @Published var drafts: [UUID:String] = [:]
    @Published var error: String?
    private let client: CloudRelayClient
    private let secrets: KeychainSecretStore
    private var connection: CloudDevice?
    private var polling: Task<Void,Never>?
    private var state: RemoteSnapshot?
    private weak var model: AppModel?
    private var pendingSends: [UUID:(String,UUID)] = [:]
    private var subscriptions: Set<AnyCancellable> = []
    private var active = true
    private var epoch = UUID()
    private var initialLoadFailed = false

    init(account: CloudAccount = CloudAccount(kind:"controller"), secrets: KeychainSecretStore = KeychainSecretStore(service:"org.opengrokbot.ios.cloud-selection")) {
        self.account = account; self.client = CloudRelayClient(account:account); self.secrets = secrets
        account.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }.store(in:&subscriptions)
    }
    func attach(_ model: AppModel) {
        guard self.model == nil else { return }; self.model = model
        account.$session.map { $0?.user.id }.removeDuplicates().sink { [weak self] _ in
            Task { @MainActor [weak self] in self?.clearState(); self?.startPolling() }
        }.store(in:&subscriptions)
    }
    func receive(_ url: URL) { if url.host == "auth" { showConnection = true } }
    func select(_ device: CloudDevice) {
        do {
            try account.pin(device)
            guard let owner = account.session?.user.id else { throw CloudError.signedOut }
            try secrets.save(Data(device.id.uuidString.utf8),account:owner.uuidString)
            try secrets.save(JSONEncoder().encode(device), account: "last-host-" + owner.uuidString)
            clearState(); connection = device; hostName = device.name; startPolling()
        } catch { self.error = error.localizedDescription }
    }
    func disconnect() {
        if let owner = account.session?.user.id { try? secrets.save(Data("disconnected".utf8),account:owner.uuidString) }
        clearState(); status = "Choose your desktop"; startPolling(autoSelect:false)
    }
    private func clearState() {
        epoch = UUID(); initialLoadFailed = false; polling?.cancel(); polling = nil; connection = nil; state = nil
        online = false; hasSnapshot = false; needsApproval = false; running = []; providers = []; defaultProvider = nil; pinnedBotIDs = nil
        drafts = [:]; pendingSends = [:]; serverPins = [:]; pendingPins = [:]; legacyPins = []; pinSyncNotice = nil
        model?.applyRemoteSnapshot(Workspace()); model?.leavePreview()
    }
    func setActive(_ active: Bool) {
        if self.active == active, (!active || polling != nil) { return }
        self.active = active
        if active { startPolling() } else { polling?.cancel(); polling = nil; online = false }
    }
    private func startPolling(autoSelect: Bool = true) {
        polling?.cancel()
        guard active, account.signedIn else { status = "Sign in to connect your desktop"; return }
        restoreHost()
        if connection == nil { status = "Finding your computer…" }
        let current = epoch
        polling = Task {
            var nextPinSync = Date.distantPast
            var nextDiscovery = connection == nil ? Date.distantPast : Date().addingTimeInterval(15)
            while !Task.isCancelled, current == epoch {
                do {
                    if Date() >= nextDiscovery {
                        try await account.sync()
                        try Task.checkCancellation()
                        guard current == epoch else { return }
                        nextDiscovery = Date().addingTimeInterval(connection == nil ? 2 : 20)
                        if connection == nil, autoSelect, let owner = account.session?.user.id {
                            let selection = try secrets.read(account:owner.uuidString).flatMap { String(data:$0,encoding:.utf8) }
                            let saved = selection.flatMap(UUID.init(uuidString:))
                            let hosts = account.hosts
                            let onlineHosts = hosts.filter(\.online)
                            // Old installations remain registered. They must not block
                            // discovery of the only Mac that is currently available.
                            let remembered = hosts.first(where: { $0.id == saved })
                            let candidate = remembered?.online == true ? remembered
                                : (onlineHosts.count == 1 ? onlineHosts.first : remembered ?? (hosts.count == 1 ? hosts.first : nil))
                            if selection != "disconnected", let device = candidate {
                                try account.pin(device)
                                try secrets.save(Data(device.id.uuidString.utf8),account:owner.uuidString)
                                connection = device; hostName = device.name
                            }
                        }
                    }
                    if connection != nil {
                        if !hasSnapshot, !needsApproval, !initialLoadFailed { status = "Loading Bots from \(hostName)…" }
                        try await refresh()
                        if hasSnapshot, Date() >= nextPinSync {
                            do { try await syncPins(); nextPinSync = Date().addingTimeInterval(2) }
                            catch { if current == epoch { pinSyncNotice = "Pins will sync when the account service reconnects." }; nextPinSync = Date().addingTimeInterval(5) }
                        }
                    } else {
                        status = account.hosts.isEmpty
                            ? "Open OpenGrokBot on your computer and sign in with this account. In Settings → Computer, make sure Allow phone access is on."
                            : "Choose your computer in Connect Desktop to load its Bots."
                    }
                } catch {
                    if Task.isCancelled || current != epoch { return }
                    online = false; initialLoadFailed = true; status = error.localizedDescription + " Retrying…"
                    nextDiscovery = Date.distantPast
                    if let cloudError = error as? CloudError {
                        if case .approvalRequired = cloudError { needsApproval = true }
                        if case .timeout = cloudError, !hasSnapshot { state = nil }
                    }
                }
                let interval: Duration = !online ? .seconds(2) : running.isEmpty ? .milliseconds(700) : .milliseconds(250)
                try? await Task.sleep(for: interval)
            }
        }
    }
    private func refresh() async throws {
        guard let peer = connection else { return }; let current = epoch
        var parts = URLComponents(); parts.path = "/v1/state"
        if !hasSnapshot { parts.queryItems = [URLQueryItem(name: "overview", value: "true")] }
        else if let revision = state?.revision { parts.queryItems = [URLQueryItem(name:"since",value:revision)] }
        guard let target = parts.string else { throw CloudError.invalidPacket }
        let response = try await client.fetch(peer,target:target)
        try Task.checkCancellation(); guard current == epoch else { return }
        if response.status == 204, state == nil || !hasSnapshot { throw CloudError.resync }
        if response.status != 204 {
            do {
                let patch = try CloudStatePatch.decode(response.body)
                let snapshot = try patch.applying(to:state)
                guard snapshot.protocolVersion == 1 else { throw RemoteError.incompatible }
                state = snapshot; hostName = snapshot.hostName; running = Set(snapshot.running)
                providers = snapshot.providers; defaultProvider = snapshot.defaultProvider
                model?.applyRemoteSnapshot(snapshot.workspace)
                if !hasSnapshot {
                    loadPins(); showConnection = false
                    if let owner = account.session?.user.id {
                        try? secrets.save(JSONEncoder().encode(peer), account: "last-host-" + owner.uuidString)
                    }
                }
                hasSnapshot = true
            } catch { state = nil; throw error }
        }
        needsApproval = false; initialLoadFailed = false; online = true; status = "Connected to \(hostName)" + (state?.overview == true ? " · loading chat history…" : "")
    }
    private func restoreHost() {
        guard connection == nil, let owner = account.session?.user.id else { return }
        do {
            guard let selection = try secrets.read(account: owner.uuidString),
                  let id = String(data: selection, encoding: .utf8).flatMap(UUID.init(uuidString:)),
                  let data = try secrets.read(account: "last-host-" + owner.uuidString) else { return }
            let host = try JSONDecoder().decode(CloudDevice.self, from: data)
            guard host.id == id else { return }
            try account.pin(host)
            connection = host; hostName = host.name
        } catch { self.error = error.localizedDescription }
    }
    private var pinsKey: String? {
        guard let owner = account.session?.user.id, let host = connection?.id else { return nil }
        return "pinned-bots-" + owner.uuidString + "-" + host.uuidString
    }
    private func loadPins() {
        guard let key = pinsKey else { return }
        do {
            if let data = try secrets.read(account: key) {
                pinnedBotIDs = try JSONDecoder().decode([UUID].self, from: data)
                legacyPins = Set(pinnedBotIDs ?? [])
            }
            if let data = try secrets.read(account: key + "-pending") { pendingPins = try JSONDecoder().decode([UUID:Bool].self, from: data) }
        } catch { self.error = "Your pinned Bots could not be loaded. Unlock this iPhone and try again." }
    }
    func isPinned(_ bot: Bot) -> Bool { serverPins[bot.id] ?? pinnedBotIDs?.contains(bot.id) ?? bot.isPinned ?? (bot.isMain == true) }
    func setPinned(_ pinned: Bool, bot: Bot) {
        guard let key = pinsKey else { return }
        var ids = pinnedBotIDs ?? model?.workspace.bots.filter { isPinned($0) }.map(\.id) ?? []
        ids.removeAll { $0 == bot.id }; if pinned { ids.append(bot.id) }
        do {
            var pending = pendingPins; pending[bot.id] = pinned
            try secrets.save(JSONEncoder().encode(pending), account: key + "-pending")
            pendingPins = pending; serverPins[bot.id] = pinned; pinnedBotIDs = ids
            let current = epoch
            Task { @MainActor in
                do { try await syncPins() }
                catch { if current == epoch { pinSyncNotice = "Saved on this phone. The pin will sync when the account service reconnects." } }
            }
        } catch { self.error = "Your pinned Bots could not be saved. Unlock this iPhone and try again." }
    }
    private func syncPins() async throws {
        guard !syncingPins, let host = connection?.id, let key = pinsKey else { return }
        syncingPins = true; defer { syncingPins = false }
        let current = epoch
        var rows = try await account.botPins(host: host)
        guard current == epoch, !Task.isCancelled else { return }
        var existing = Set(rows.map(\.bot_id))
        // Import previously phone-only pins once, without overwriting newer server choices.
        for id in legacyPins where !existing.contains(id) {
            let row = try await account.setBotPin(host: host, bot: id, pinned: true, onlyIfMissing: true)
            guard current == epoch else { return }; rows.append(row); existing.insert(id)
        }
        for (id, value) in pendingPins {
            _ = try await account.setBotPin(host: host, bot: id, pinned: value)
            guard current == epoch else { return }
            if pendingPins[id] == value { pendingPins[id] = nil }
        }
        try secrets.save(JSONEncoder().encode(pendingPins), account: key + "-pending")
        rows = try await account.botPins(host: host)
        guard current == epoch, !Task.isCancelled else { return }
        var pins: [UUID:Bool] = [:]; for row in rows { pins[row.bot_id] = row.is_pinned }
        for (id, value) in pendingPins { pins[id] = value }
        serverPins = pins
        pinnedBotIDs = model?.workspace.bots.filter { pins[$0.id] ?? $0.isPinned ?? ($0.isMain == true) }.map(\.id)
        pinSyncNotice = nil
    }
    @discardableResult
    func command(_ command: RemoteCommand) async -> Bool {
        guard online, let peer = connection else { error = "Reconnect to your desktop before changing the workspace."; return false }
        let current = epoch
        do {
            _ = try await client.fetch(peer,target:"/v1/command",command:command)
            guard current == epoch else { return false }
            // The regular state poll publishes the result. Acknowledged commands
            // must not keep the composer busy waiting for another relay exchange.
            return true
        } catch { if current == epoch, !Task.isCancelled { self.error = error.localizedDescription }; return false }
    }
    func send(_ text: String, bot: Bot) async -> Bool {
        let id = pendingSends[bot.id].flatMap { $0.0 == text ? $0.1:nil } ?? UUID()
        pendingSends[bot.id] = (text,id)
        let accepted = await command(RemoteCommand(requestID:id,action:"send",botID:bot.id,text:text))
        if accepted, pendingSends[bot.id]?.1 == id { pendingSends[bot.id] = nil }; return accepted
    }
    func models(_ provider: CLIProvider) async -> [AvailableCLIModel] {
        guard let peer = connection, let response = try? await client.fetch(peer,target:"/v1/models?provider=" + provider.rawValue) else { return [] }
        var seen = Set<String>()
        return ((try? CloudCoding.decoder().decode([AvailableCLIModel].self,from:response.body)) ?? []).filter { seen.insert($0.id).inserted }
    }
    func browserPreview(_ botID: UUID) async throws -> RemoteBrowserPreview {
        guard let peer = connection else { throw CloudError.message("Choose a hosting computer first.") }
        let response = try await client.fetch(peer, target: "/v1/browser?bot=" + botID.uuidString)
        return try CloudCoding.decoder().decode(RemoteBrowserPreview.self, from: response.body)
    }
    func files(_ bot: Bot) async -> [RemoteFile] {
        guard let peer = connection, let response = try? await client.fetch(peer,target:"/v1/files?bot=" + bot.id.uuidString) else { return [] }
        return (try? CloudCoding.decoder().decode([RemoteFile].self,from:response.body)) ?? []
    }
}
