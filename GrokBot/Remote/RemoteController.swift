import Foundation
import SwiftUI
import Combine

@MainActor
final class RemoteController: ObservableObject {
    let account: CloudAccount
    @Published private(set) var online = false
    @Published private(set) var hasSnapshot = false
    @Published private(set) var hostName = "Desktop"
    @Published private(set) var status = "Sign in to connect your desktop"
    @Published private(set) var running: Set<UUID> = []
    @Published private(set) var providers: [RemoteProvider] = []
    @Published private(set) var defaultProvider: CLIProvider?
    @Published var showPairing = false
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

    init(account: CloudAccount = CloudAccount(kind:"controller"), secrets: KeychainSecretStore = KeychainSecretStore(service:"org.opengrokbot.ios.cloud-selection")) {
        self.account = account; self.client = CloudRelayClient(account:account); self.secrets = secrets
        account.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }.store(in:&subscriptions)
    }
    func attach(_ model: AppModel) {
        guard self.model == nil else { return }; self.model = model
        account.$session.map { $0?.user.id }.removeDuplicates().sink { [weak self] _ in
            Task { @MainActor [weak self] in self?.clearState(); self?.startPolling() }
        }.store(in:&subscriptions)
        startPolling()
    }
    func receive(_ url: URL) { if url.host == "auth" { showPairing = true } }
    func select(_ device: CloudDevice) {
        do {
            try account.pin(device)
            guard let owner = account.session?.user.id else { throw CloudError.signedOut }
            try secrets.save(Data(device.id.uuidString.utf8),account:owner.uuidString)
            clearState(); connection = device; hostName = device.name; showPairing = false; startPolling()
        } catch { self.error = error.localizedDescription }
    }
    func disconnect() {
        if let owner = account.session?.user.id { try? secrets.delete(account:owner.uuidString) }
        clearState(); status = "Choose your desktop"; startPolling(autoSelect:false)
    }
    private func clearState() {
        epoch = UUID(); polling?.cancel(); polling = nil; connection = nil; state = nil
        online = false; hasSnapshot = false; running = []; providers = []; defaultProvider = nil
        drafts = [:]; pendingSends = [:]
        model?.applyRemoteSnapshot(Workspace()); model?.leavePreview()
    }
    func setActive(_ active: Bool) {
        self.active = active
        if active { startPolling() } else { polling?.cancel(); polling = nil; online = false }
    }
    private func startPolling(autoSelect: Bool = true) {
        polling?.cancel()
        guard active, account.signedIn else { status = "Sign in to connect your desktop"; return }
        let current = epoch
        polling = Task {
            var ticks = 0
            while !Task.isCancelled, current == epoch {
                do {
                    if ticks % 10 == 0 {
                        try await account.sync()
                        if connection == nil, autoSelect, let owner = account.session?.user.id {
                            let saved = try secrets.read(account:owner.uuidString).flatMap { String(data:$0,encoding:.utf8) }.flatMap(UUID.init(uuidString:))
                            if let device = account.hosts.first(where:{$0.id == saved}) ?? (saved == nil && account.hosts.count == 1 ? account.hosts.first:nil) {
                                try account.pin(device); connection = device; hostName = device.name
                            }
                        }
                    }
                    if connection != nil { try await refresh() } else { status = "Choose your desktop" }
                    ticks += 1
                } catch {
                    if Task.isCancelled || current != epoch { return }
                    online = false; status = error.localizedDescription; ticks = 0
                }
                try? await Task.sleep(for:.seconds(2))
            }
        }
    }
    private func refresh() async throws {
        guard let peer = connection else { return }; let current = epoch
        var parts = URLComponents(); parts.path = "/v1/state"
        if let revision = state?.revision { parts.queryItems = [URLQueryItem(name:"since",value:revision)] }
        let response = try await client.fetch(peer,target:parts.string!)
        try Task.checkCancellation(); guard current == epoch else { return }
        if response.status != 204 {
            do {
                let patch = try CloudCoding.decoder().decode(CloudStatePatch.self,from:response.body)
                let snapshot = try patch.applying(to:state)
                guard snapshot.protocolVersion == 1 else { throw RemoteError.incompatible }
                state = snapshot; hostName = snapshot.hostName; running = Set(snapshot.running)
                providers = snapshot.providers; defaultProvider = snapshot.defaultProvider
                model?.applyRemoteSnapshot(snapshot.workspace); hasSnapshot = true
            } catch { state = nil; throw error }
        }
        online = true; status = "Connected to \(hostName)"
    }
    @discardableResult
    func command(_ command: RemoteCommand) async -> Bool {
        guard online, let peer = connection else { error = "Reconnect to your desktop before changing the workspace."; return false }
        let current = epoch
        do {
            _ = try await client.fetch(peer,target:"/v1/command",command:command)
            guard current == epoch else { return false }
            try? await refresh(); return true
        } catch { self.error = error.localizedDescription; return false }
    }
    func send(_ text: String, bot: Bot) async -> Bool {
        let id = pendingSends[bot.id].flatMap { $0.0 == text ? $0.1:nil } ?? UUID()
        pendingSends[bot.id] = (text,id)
        let accepted = await command(RemoteCommand(requestID:id,action:"send",botID:bot.id,text:text))
        if accepted { pendingSends[bot.id] = nil }; return accepted
    }
    func models(_ provider: CLIProvider) async -> [AvailableCLIModel] {
        guard let peer = connection, let response = try? await client.fetch(peer,target:"/v1/models?provider=" + provider.rawValue) else { return [] }
        return (try? CloudCoding.decoder().decode([AvailableCLIModel].self,from:response.body)) ?? []
    }
    func files(_ bot: Bot) async -> [RemoteFile] {
        guard let peer = connection, let response = try? await client.fetch(peer,target:"/v1/files?bot=" + bot.id.uuidString) else { return [] }
        return (try? CloudCoding.decoder().decode([RemoteFile].self,from:response.body)) ?? []
    }
}
