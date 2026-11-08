import Combine
import Foundation

/// Another computer on this account, shown in the main window exactly like this Mac's own Bots.
/// Messages, stops, retries, provider changes, pins and new Bots are all sent to that computer; nothing here edits this Mac's workspace.
@MainActor
final class MacGateway: ObservableObject {
    /// An in-memory copy of the other computer's workspace. Its own cache file is separate from this Mac's real workspace file,
    /// so even a stray save can never overwrite the Bots on this Mac.
    let model: AppModel
    let remote: RemoteController
    private var subscriptions: Set<AnyCancellable> = []

    init(source: CloudAccount) {
        let cache = FileManager.default.temporaryDirectory.appendingPathComponent("OpenGrokBot-gateway-cache-" + UUID().uuidString + ".json")
        model = AppModel(store: WorkspaceStore(url: cache), deferSaves: true)
        remote = RemoteController(
            account: CloudAccount(kind: "controller", secrets: KeychainSecretStore(service: "org.opengrokbot.mac.mirror-identity")),
            secrets: KeychainSecretStore(service: "org.opengrokbot.mac.mirror-selection"))
        remote.account.useAccount(from: source)
        remote.attach(model)
        remote.setActive(true)
        remote.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &subscriptions)
    }

    func close() { remote.setActive(false) }

    var hosts: [CloudDevice] { remote.account.hosts }
    var online: Bool { remote.online }
    var hostName: String { remote.hostName }
    var running: Set<UUID> { remote.running }
    func select(_ host: CloudDevice) { remote.select(host) }

    private func run(_ command: RemoteCommand) { Task { _ = await remote.command(command) } }

    /// Sends a message to a Bot on the other computer. False if that computer is not reachable right now.
    func send(_ text: String, to bot: Bot) -> Bool {
        guard remote.online, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, text.count <= 100_000 else { return false }
        Task { _ = await remote.send(text, bot: bot) }
        return true
    }
    func stop(_ id: UUID) { run(RemoteCommand(action: "stop", botID: id)) }
    func retry(_ id: UUID) { run(RemoteCommand(action: "retry", botID: id)) }
    func touch(_ id: UUID) { run(RemoteCommand(action: "touch_bot", botID: id)) }
    /// Deletes a Bot on the other computer and drops it from the list on screen right away.
    func delete(_ id: UUID) {
        Task {
            if await remote.command(RemoteCommand(action: "delete_bot", botID: id)), let bot = model.workspace.bots.first(where: { $0.id == id }) { model.removeBot(bot) }
        }
    }
    func setPinned(_ bot: Bot, _ pinned: Bool) { remote.setPinned(pinned, bot: bot) }
    func isPinned(_ bot: Bot) -> Bool { remote.isPinned(bot) }
    func create(name: String, purpose: String, color: String) async -> Bool { await remote.command(RemoteCommand(action: "create_bot", name: name, purpose: purpose, color: color)) }
    func useProvider(_ provider: CLIProvider, for bot: Bot) {
        let configuration = BotAIConfiguration(providers: [BotAIProvider(provider: provider, model: "")], activeProvider: provider, replyMode: .one)
        run(RemoteCommand(action: "configure_bot", botID: bot.id, configuration: configuration))
    }
    func configure(_ configuration: BotAIConfiguration, for bot: Bot) { run(RemoteCommand(action: "configure_bot", botID: bot.id, configuration: configuration)) }
    var providers: [RemoteProvider] { remote.providers }
    var defaultProvider: CLIProvider? { remote.defaultProvider }
    var hasSnapshot: Bool { remote.hasSnapshot }
    func models(_ provider: CLIProvider) async -> [AvailableCLIModel] { await remote.models(provider) }
    func useProvider(_ provider: CLIProvider, model: String, for bot: Bot) {
        let configuration = BotAIConfiguration(providers: [BotAIProvider(provider: provider, model: model)], activeProvider: provider, replyMode: .one)
        run(RemoteCommand(action: "configure_bot", botID: bot.id, configuration: configuration))
    }
    func hostSettings() async throws -> RemoteHostSettings { try await remote.hostSettings() }
    func setAPIKey(_ key: String, for provider: CLIProvider) async throws { try await remote.setAPIKey(key, for: provider) }

    func vmPreview(_ vm: UUID, on host: CloudDevice) async throws -> RemoteBrowserPreview { try await remote.vmPreview(vm: vm, on: host) }
    func openVM(_ vm: UUID, on host: CloudDevice) async throws { try await remote.openVM(vm: vm, on: host) }
    func vms(on host: CloudDevice) async throws -> [RemoteVM] { try await remote.vmList(on: host) }
    func runVM(_ argv: [String], vm: UUID, on host: CloudDevice) async throws -> String { try await remote.runVMCommand(argv, vm: vm, on: host) }

    /// The Bot as a package, from the computer being viewed.
    func package(_ bot: Bot) async throws -> Data { try await remote.botPackage(bot) }
    func settingsBundle() async throws -> Data { try await remote.settingsBundle() }
    func deliverSettings(_ data: Data, to host: CloudDevice) async throws { try await remote.importSettings(data, to: host) }
    /// Sends a package to a computer on this account.
    func deliver(_ data: Data, to host: CloudDevice) async throws { try await remote.importPackage(data, to: host) }
}
