import Foundation
import SwiftUI
import Combine
#if os(iOS)
import UIKit
import UserNotifications
#endif

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
    /// A Bot request the Mac is waiting on; answer it with answerApproval.
    @Published private(set) var approval: RemoteApproval?
    private var serverPins: [UUID:Bool] = [:]
    private var pendingPins: [UUID:Bool] = [:]
    private var legacyPins = Set<UUID>()
    private var syncingPins = false
    @Published var showConnection = false
    @Published var busy = false
    @Published var drafts: [UUID:String] = [:]
    @Published var draftImages: [UUID:[RemoteAttachment]] = [:]
    /// The chat on screen, so a finished reply there doesn't also raise a notification.
    var viewingBotID: UUID?
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
        online = false; hasSnapshot = false; needsApproval = false; approval = nil; running = []; providers = []; defaultProvider = nil; pinnedBotIDs = nil
        drafts = [:]; draftImages = [:]; pendingSends = [:]; serverPins = [:]; pendingPins = [:]; legacyPins = []; pinSyncNotice = nil
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
                let wasLoaded = hasSnapshot, finished = running.subtracting(Set(snapshot.running))
                state = snapshot; hostName = snapshot.hostName; running = Set(snapshot.running); approval = snapshot.approval
                providers = snapshot.providers; defaultProvider = snapshot.defaultProvider
                model?.applyRemoteSnapshot(snapshot.workspace)
                if wasLoaded, !finished.isEmpty { ReplyNotifier.notify(finished: finished, workspace: snapshot.workspace, viewing: viewingBotID) }
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
    func answerApproval(_ approve: Bool) async {
        guard let request = approval else { return }
        approval = nil
        _ = await command(RemoteCommand(action: "approval_response", text: request.id.uuidString, name: approve ? "approve" : "deny"))
    }
    func send(_ text: String, bot: Bot, images: [RemoteAttachment] = []) async -> Bool {
        let id = pendingSends[bot.id].flatMap { $0.0 == text ? $0.1:nil } ?? UUID()
        pendingSends[bot.id] = (text,id)
        let accepted = await command(RemoteCommand(requestID:id,action:"send",botID:bot.id,text:text,attachments:images.isEmpty ? nil : images))
        if accepted, pendingSends[bot.id]?.1 == id { pendingSends[bot.id] = nil }; return accepted
    }
    func models(_ provider: CLIProvider) async -> [AvailableCLIModel] {
        guard let peer = connection, let response = try? await client.fetch(peer,target:"/v1/models?provider=" + provider.rawValue) else { return [] }
        var seen = Set<String>()
        return ((try? CloudCoding.decoder().decode([AvailableCLIModel].self,from:response.body)) ?? []).filter { seen.insert($0.id).inserted }
    }
    func browserPreview(_ botID: UUID, vm: Bool = false) async throws -> RemoteBrowserPreview {
        guard let peer = connection else { throw CloudError.message("Choose a hosting computer first.") }
        let response = try await client.fetch(peer, target: "/v1/" + (vm ? "vm" : "browser") + "?bot=" + botID.uuidString)
        return try CloudCoding.decoder().decode(RemoteBrowserPreview.self, from: response.body)
    }
    /// An encoded Bot package from the connected computer.
    func botPackage(_ bot: Bot) async throws -> Data {
        guard let peer = connection else { throw CloudError.message("Choose a hosting computer first.") }
        return try await client.fetch(peer, target: "/v1/bot-package?bot=" + bot.id.uuidString).body
    }
    /// Sends a Bot package to a computer on this account (the connected one unless another is named).
    func importPackage(_ data: Data, to host: CloudDevice? = nil) async throws {
        guard let peer = host ?? connection else { throw CloudError.message("Choose a hosting computer first.") }
        _ = try await client.fetch(peer, target: "/v1/command", command: RemoteCommand(action: "import_bot", package: data))
    }
    /// The connected computer's own settings (providers, which keys are set, connectors, versions).
    func hostSettings() async throws -> RemoteHostSettings {
        guard let peer = connection else { throw CloudError.message("Choose a hosting computer first.") }
        let response = try await client.fetch(peer, target: "/v1/host-settings")
        return try CloudCoding.decoder().decode(RemoteHostSettings.self, from: response.body)
    }
    /// Saves (or, with an empty key, removes) an AI provider API key on the connected computer.
    func setAPIKey(_ key: String, for provider: CLIProvider) async throws {
        guard let peer = connection else { throw CloudError.message("Choose a hosting computer first.") }
        _ = try await client.fetch(peer, target: "/v1/command", command: RemoteCommand(action: "set_api_key", text: key, name: provider.rawValue))
    }
    /// Keys and connector settings from the connected computer (it must have sharing switched on).
    func settingsBundle() async throws -> Data {
        guard let peer = connection else { throw CloudError.message("Choose a hosting computer first.") }
        return try await client.fetch(peer, target: "/v1/bundle").body
    }
    /// Sends keys and connector settings to a computer on this account (it must have sharing switched on).
    func importSettings(_ data: Data, to host: CloudDevice? = nil) async throws {
        guard let peer = host ?? connection else { throw CloudError.message("Choose a hosting computer first.") }
        _ = try await client.fetch(peer, target: "/v1/command", command: RemoteCommand(action: "import_settings", package: data))
    }
    func files(_ bot: Bot) async -> [RemoteFile] {
        guard let peer = connection, let response = try? await client.fetch(peer,target:"/v1/files?bot=" + bot.id.uuidString) else { return [] }
        return (try? CloudCoding.decoder().decode([RemoteFile].self,from:response.body)) ?? []
    }
}

/// Notifies you when a Bot finishes while you're in another chat or the app is in the background.
/// The phone only learns about replies while it is connected, so this is not a push service.
enum ReplyNotifier {
    @MainActor static func notify(finished: Set<UUID>, workspace: Workspace, viewing: UUID?) {
        #if os(iOS)
        let foreground = UIApplication.shared.applicationState == .active
        for id in finished where !(foreground && id == viewing) {
            guard let bot = workspace.bots.first(where: { $0.id == id }),
                  let reply = workspace.entries.last(where: { $0.botID == id && $0.kind == .bot }),
                  reply.state != .stopped else { continue }
            let content = UNMutableNotificationContent()
            content.title = reply.state == .failed ? "\(bot.name) couldn’t finish" : "\(bot.name) replied"
            content.body = String(reply.text.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression).prefix(160))
            content.sound = .default
            content.userInfo = ["botID": id.uuidString]
            let request = UNNotificationRequest(identifier: reply.id.uuidString, content: content, trigger: nil)
            Task {
                let center = UNUserNotificationCenter.current()
                guard (try? await center.requestAuthorization(options: [.alert, .sound])) == true else { return }
                try? await center.add(request)
            }
        }
        #endif
    }
}

#if os(iOS)
/// Shows reply banners even while OpenGrokBot is open.
final class NotificationPresenter: NSObject, UNUserNotificationCenterDelegate, Sendable {
    static let shared = NotificationPresenter()
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}
#endif
