import AppKit
import UniformTypeIdentifiers
import SwiftUI

enum MacPanel: String, Identifiable {
    case settings, apps, newBot, integration, setup
    var id: String { rawValue }
}

enum SettingsTab: String, CaseIterable, Identifiable {
    case general = "General", computer = "Computer", permissions = "Permissions", vault = "Vault", usage = "Usage & Billing", updates = "Updates"
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .general: "gearshape"
        case .computer: "desktopcomputer"
        case .permissions: "shield"
        case .vault: "lock.square"
        case .usage: "chart.bar"
        case .updates: "arrow.down.circle"
        }
    }
}

@MainActor
final class MacAppModel: ObservableObject {
    let composio = ComposioModel()
    @Published var selectedID: UUID?
    @Published var panel: MacPanel?
    @Published var settingsTab = SettingsTab.general
    @Published var showSearch = false
    @Published var showBotInspector = false
    @Published var drafts: [UUID: String] = [:]
    @Published var importFeedback: String?
    @Published var installedCLIs: [InstalledCLI] = []
    @Published var selectedCLIID = UserDefaults.standard.string(forKey: "selectedLocalCLI") ?? ""
    @Published var scanningCLIs = false
    @Published var checkingLogin = false
    @Published var loginVerified = false
    @Published var setupFeedback: String?
    @Published var runningBots: Set<UUID> = []
    @Published var modelCatalogs: [CLIProvider:[AvailableCLIModel]] = [:]
    @Published var loadingModels: Set<CLIProvider> = []
    @Published var modelCatalogFeedback: [CLIProvider:String] = [:]
    @Published var setupProvider: CLIProvider?
    @Published var runErrors: [UUID:String] = [:]
    var cliOverrides = UserDefaults.standard.dictionary(forKey: "localCLIPaths") as? [String:String] ?? [:]
    var tasks: [UUID:Task<Void,Never>] = [:]
    var runs: [UUID:LocalCLIRun] = [:]
    var runOwners: [UUID:UUID] = [:]

    func selectFirst(in app: AppModel) {
        if selectedID == nil { selectedID = app.workspace.bots.first?.id }
    }
    func selected(in app: AppModel) -> Bot? {
        app.workspace.bots.first { $0.id == selectedID } ?? app.workspace.bots.first
    }
    func openSettings(_ tab: SettingsTab = .general) { settingsTab = tab; panel = .settings }

    func exportConversation(_ bot: Bot, app: AppModel) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = "\(bot.name)-conversation.txt"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try conversationText(for: bot, app: app).write(to: url, atomically: true, encoding: .utf8) }
        catch { app.errorMessage = "The conversation could not be exported. Choose a writable folder and try again." }
    }
    func conversationText(for bot: Bot, app: AppModel) -> String {
        "OpenGrokBot — \(bot.name)\n\n" + app.entries(for: bot).map { entry in
            let label = entry.kind == .user ? "You" : entry.kind == .activity ? "Activity" : bot.name
            return "\(label): \(entry.text)"
        }.joined(separator: "\n\n")
    }

    func workingDirectory(for bot: Bot) -> URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/OpenGrokBot/Conversations/\(bot.id.uuidString)")
    }

    func openWorkingDirectory(for bot: Bot) {
        do {
            let directory = workingDirectory(for: bot)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions:0o700])
            NSWorkspace.shared.open(directory)
        } catch { importFeedback = "The working folder could not be opened. Check this Mac’s available storage and folder permissions."; panel = .integration }
    }

}

extension MacAppModel {
    var selectedCLI: InstalledCLI? { installedCLIs.first { $0.id == selectedCLIID } }
    var canChat: Bool { selectedCLI != nil }
    var statusText: String { selectedCLI.map { "\($0.provider.name) · On this Mac" } ?? "Set up an AI CLI" }

    func aiConfiguration(for bot: Bot) -> BotAIConfiguration {
        bot.aiConfiguration ?? BotAIConfiguration(providers: selectedCLI.map { [BotAIProvider(provider: $0.provider)] } ?? [], activeProvider: selectedCLI?.provider)
    }

    func providersToRun(for bot: Bot) -> [(cli: InstalledCLI, choice: BotAIProvider)] {
        let configuration = aiConfiguration(for: bot)
        let choices: [BotAIProvider]
        if configuration.replyMode == .all { choices = configuration.providers }
        else { choices = (configuration.providers.first { $0.provider == configuration.activeProvider } ?? configuration.providers.first).map { [$0] } ?? [] }
        return choices.compactMap { choice in installedCLIs.first { $0.provider == choice.provider }.map { ($0, choice) } }
    }

    func loadModels(for provider: CLIProvider) {
        guard !loadingModels.contains(provider), let cli = installedCLIs.first(where: { $0.provider == provider }) else { return }
        loadingModels.insert(provider); modelCatalogFeedback[provider] = nil
        Task {
            let models = await Task.detached { CLIModelCatalog.models(for: cli) }.value
            modelCatalogs[provider] = models
            if models.isEmpty { modelCatalogFeedback[provider] = "No model list was returned. You can enter a model ID below." }
            loadingModels.remove(provider)
        }
    }

    func refreshCLIs() {
        guard !scanningCLIs else { return }
        scanningCLIs = true
        var overrides = cliOverrides
        #if DEBUG
        if let path = ProcessInfo.processInfo.environment["OPENGROKBOT_TEST_CODEX_PATH"] ?? WorkspaceStore.testArgument("--opengrokbot-test-cli") { overrides["codex"] = path }
        #endif
        Task {
            let found = await Task.detached { [overrides] in CLIInstallationScanner.scan(overrides: overrides) }.value
            installedCLIs = found
            if !found.contains(where: { $0.id == selectedCLIID }) { selectedCLIID = found.first?.id ?? "" }
            scanningCLIs = false
        }
    }

    func chooseCLI(_ id: String) {
        selectedCLIID = id
        UserDefaults.standard.set(id, forKey: "selectedLocalCLI")
    }

    func setCLIPath(_ path: String, provider: CLIProvider) {
        cliOverrides[provider.rawValue] = path
        UserDefaults.standard.set(cliOverrides, forKey: "localCLIPaths")
        refreshCLIs()
    }

    func checkLogin() {
        guard let cli = selectedCLI else { return }
        checkingLogin = true; loginVerified = false
        Task {
            if cli.provider == .codex {
                let status = await Task.detached { CLIInstallationScanner.capture(path: cli.path, arguments: ["login", "status"], timeout: 12).exit }.value
                loginVerified = status == 0
                setupFeedback = loginVerified ? "Codex is signed in and ready." : "Sign in using codex login in Terminal, then check again."
            } else {
                loginVerified = true
                setupFeedback = "This CLI uses its own saved provider configuration. Authentication will be verified when you send your first message."
            }
            checkingLogin = false
        }
    }

    func completeSetup() {
        guard selectedCLI != nil else { return }
        UserDefaults.standard.set(true, forKey: "localCLISetupComplete")
        panel = nil
    }

    @discardableResult
    func send(_ text: String, to bot: Bot, app: AppModel) -> Bool {
        let providers = providersToRun(for: bot)
        guard !providers.isEmpty else { showBotInspector = true; return false }
        guard !runningBots.contains(bot.id), !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        guard app.addNote(text, to: bot) else { return false }
        for provider in providers { startReply(to: bot, cli: provider.cli, model: provider.choice.model, app: app) }
        return true
    }

    func retry(bot: Bot, app: AppModel) {
        guard !runningBots.contains(bot.id), app.entries(for: bot).contains(where: { $0.kind == .user }) else { return }
        for provider in providersToRun(for: bot) { startReply(to: bot, cli: provider.cli, model: provider.choice.model, app: app) }
    }

    func stop(botID: UUID) { for (runID, owner) in runOwners where owner == botID { runs[runID]?.cancel() } }
    func stopAll(immediately: Bool = false) { for run in runs.values { run.cancel(immediately: immediately) } }

    private func startReply(to bot: Bot, cli: InstalledCLI, model: String, app: AppModel) {
        let key = bot.id.uuidString + "|" + cli.id + (model.isEmpty ? "" : "|" + model)
        let session = app.session(for: key)
        let history = app.entries(for: bot).filter { $0.state != .failed && $0.state != .stopped && !$0.text.isEmpty }
        let prompt: String
        if session != nil { prompt = history.last(where: { $0.kind == .user })?.text ?? "" }
        else {
            let transcript = history.suffix(30).map { "\($0.kind == .user ? "User" : bot.name): \($0.text)" }.joined(separator: "\n\n")
            prompt = "You are \(bot.name). \(bot.purpose)\nRespond to the user's latest message.\n\n" + String(transcript.suffix(100_000))
        }
        let replyID = app.beginReply(for: bot, provider: cli.provider.name + (model.isEmpty ? "" : " · " + model))
        runningBots.insert(bot.id); runErrors[bot.id] = nil
        let directory = workingDirectory(for: bot)
        let run = LocalCLIRun(); runs[replyID] = run; runOwners[replyID] = bot.id
        tasks[replyID] = Task {
            do {
                let mcpURL = try composio.mcpURL()
                for try await event in run.events(cli: cli, prompt: prompt, session: session, directory: directory, mcpURL: mcpURL, model: model) {
                    try Task.checkCancellation()
                    switch event {
                    case .session(let id): app.setSession(id, for: key)
                    case .text(let value): app.updateReply(replyID, text: value)
                    case .activity: break
                    case .failed: throw CLIError.failed(1)
                    }
                }
                try Task.checkCancellation()
                app.finishReply(replyID, state: .complete)
            } catch {
                let stopped = Task.isCancelled || (error as? CLIError) == .stopped
                let message = stopped ? "Response stopped." : ((error as? CLIError)?.errorDescription ?? "The CLI could not start. Check its executable path and sign-in in setup.")
                app.finishReply(replyID, state: stopped ? .stopped : .failed, message: message)
                if !stopped { runErrors[bot.id] = message }
            }
            tasks[replyID] = nil; runs[replyID] = nil; runOwners[replyID] = nil
            if !runOwners.values.contains(bot.id) { runningBots.remove(bot.id) }
        }
    }
}
