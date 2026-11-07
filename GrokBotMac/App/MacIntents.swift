import AppIntents
import Foundation

/// Lets Siri and the Shortcuts app on this Mac send a request to a Bot ("Ask OpenGrokBot …").
@MainActor
final class MacIntentHub {
    static let shared = MacIntentHub()
    private weak var app: AppModel?
    private weak var desktop: MacAppModel?
    private var pending: [(bot: String, text: String)] = []

    func attach(app: AppModel, desktop: MacAppModel) { self.app = app; self.desktop = desktop; flush() }

    /// The Bot named (exactly, then partly), else the main Bot, else the first one.
    static func choose(_ name: String, from bots: [Bot]) -> Bot? {
        let wanted = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let singles = bots.filter { $0.memberIDs == nil }
        let named = wanted.isEmpty ? nil : (singles.first { $0.name.lowercased() == wanted } ?? singles.first { $0.name.lowercased().contains(wanted) })
        return named ?? singles.first { $0.isMain == true } ?? singles.first
    }

    /// Returns a short sentence about what happened, for Siri to speak.
    func ask(bot name: String, text: String) -> String {
        pending.append((name, text))
        flush()
        return pending.isEmpty ? "Sent." : "OpenGrokBot is still starting. It will send that as soon as it is ready."
    }

    private func flush() {
        guard let app, let desktop else { return }
        var remaining: [(bot: String, text: String)] = []
        for item in pending {
            guard let bot = Self.choose(item.bot, from: app.workspace.bots) else { remaining.append(item); continue }
            if desktop.send(item.text, to: bot, app: app) { desktop.selectedID = bot.id } else { remaining.append(item) }
        }
        pending = remaining
    }
}

struct MacAskBotIntent: AppIntent {
    static var title: LocalizedStringResource { "Ask a Bot" }
    static var description: IntentDescription { IntentDescription("Sends a request to one of your OpenGrokBot Bots.") }
    static var openAppWhenRun: Bool { true }

    @Parameter(title: "Request") var request: String
    @Parameter(title: "Bot name", description: "Leave blank for your main Bot.") var botName: String?

    static var parameterSummary: some ParameterSummary { Summary("Ask \(\.$botName) \(\.$request)") }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let text = String(request.trimmingCharacters(in: .whitespacesAndNewlines).prefix(8000))
        guard !text.isEmpty else { return .result(dialog: "There was nothing to send.") }
        return .result(dialog: IntentDialog(stringLiteral: MacIntentHub.shared.ask(bot: botName ?? "", text: text)))
    }
}

struct MacShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: MacAskBotIntent(), phrases: ["Ask \(.applicationName)", "Ask my Bot in \(.applicationName)"], shortTitle: "Ask a Bot", systemImageName: "text.bubble")
    }
}
