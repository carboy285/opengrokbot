import AppKit
import UniformTypeIdentifiers
import SwiftUI

enum MacPanel: String, Identifiable {
    case settings, apps, newBot, integration
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
    @Published var selectedID: UUID?
    @Published var panel: MacPanel?
    @Published var settingsTab = SettingsTab.general
    @Published var showSearch = false
    @Published var drafts: [UUID: String] = [:]
    @Published var importFeedback: String?

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
        panel.nameFieldStringValue = "\(bot.name)-preview.txt"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let heading = "OpenGrokBot — OFFLINE PREVIEW\nNo messages were sent to Grok Bot.\n\n"
        let body = app.entries(for: bot).map { entry in
            let label = entry.kind == .user ? "Local note" : entry.kind == .activity ? "Example activity" : "Example Bot"
            return "\(label): \(entry.text)"
        }.joined(separator: "\n\n")
        do { try (heading + body).write(to: url, atomically: true, encoding: .utf8) }
        catch { app.errorMessage = "The conversation could not be exported. Choose a writable folder and try again." }
    }
}
