import SwiftUI

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var workspace = Workspace()
    @Published var previewEnabled = false
    @Published var errorMessage: String?
    @Published var search = ""
    let client: any HarnessClient = UnverifiedHarnessClient()
    private let store: WorkspaceStore

    init(store: WorkspaceStore = .application) { self.store = store }

    var visibleBots: [Bot] {
        workspace.bots.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) || $0.purpose.localizedCaseInsensitiveContains(search) }
    }

    func enterPreview() {
        do { workspace = try store.load() ?? .preview }
        catch {
            workspace = .preview
            errorMessage = "Saved preview could not be read. Your saved file has been kept."
        }
        previewEnabled = true
    }

    func leavePreview() { previewEnabled = false; search = "" }
    func entries(for bot: Bot) -> [Entry] { workspace.entries.filter { $0.botID == bot.id } }
    func latest(for bot: Bot) -> String { entries(for: bot).last?.text ?? bot.purpose }

    @discardableResult
    func addNote(_ text: String, to bot: Bot) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard previewEnabled, !trimmed.isEmpty, workspace.bots.contains(where: { $0.id == bot.id }) else { return false }
        return commit { $0.entries.append(Entry(botID: bot.id, kind: .user, text: trimmed)) }
    }

    @discardableResult
    func addBot(name: String, purpose: String, color: String) -> Bool {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard previewEnabled, !cleanName.isEmpty else { return false }
        return commit { $0.bots.append(Bot(id: UUID(), name: cleanName, purpose: purpose, color: color, symbol: "sparkles")) }
    }

    func removeBot(_ bot: Bot) {
        commit { value in
            value.bots.removeAll { $0.id == bot.id }
            value.entries.removeAll { $0.botID == bot.id }
        }
    }

    func resetPreview() { commit { $0 = .preview } }

    @discardableResult
    private func commit(_ change: (inout Workspace) -> Void) -> Bool {
        var updated = workspace
        change(&updated)
        do { try store.save(updated); workspace = updated; return true }
        catch { errorMessage = "Your changes could not be saved. Check available device storage and try again."; return false }
    }
}
