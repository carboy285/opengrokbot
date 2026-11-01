import SwiftUI

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var workspace = Workspace()
    @Published var previewEnabled = false
    @Published var errorMessage: String?
    @Published var search = ""
    let client: any HarnessClient = UnverifiedHarnessClient()
    private let store: WorkspaceStore
    private var loadFailed = false

    init(store: WorkspaceStore = .application) { self.store = store }

    var visibleBots: [Bot] {
        workspace.bots.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) || $0.purpose.localizedCaseInsensitiveContains(search) }
    }

    func enterPreview() {
        do { workspace = try store.load() ?? .fresh }
        catch {
            workspace = .fresh
            loadFailed = true
            errorMessage = "Saved preview could not be read. Your saved file has been kept."
        }
        previewEnabled = true
        for index in workspace.entries.indices where workspace.entries[index].state == .streaming {
            workspace.entries[index].state = .stopped
        }
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
        guard previewEnabled, !cleanName.isEmpty, !workspace.bots.contains(where: { $0.name.caseInsensitiveCompare(cleanName) == .orderedSame }) else { return false }
        return commit { $0.bots.append(Bot(id: UUID(), name: cleanName, purpose: purpose, color: color, symbol: "sparkles")) }
    }

    func removeBot(_ bot: Bot) {
        guard bot.isMain != true else { return }
        commit { value in
            value.bots.removeAll { $0.id == bot.id }
            value.entries.removeAll { $0.botID == bot.id }
        }
    }

    func resetPreview() { loadFailed = false; commit { $0 = .fresh } }

    @discardableResult
    func beginReply(for bot: Bot, provider: String) -> UUID {
        var entry = Entry(botID: bot.id, kind: .bot, text: "")
        entry.state = .streaming; entry.provider = provider
        workspace.entries.append(entry)
        return entry.id
    }

    func updateReply(_ id: UUID, text: String) {
        guard let index = workspace.entries.firstIndex(where: { $0.id == id }) else { return }
        workspace.entries[index].text = text
    }

    func finishReply(_ id: UUID, state: MessageState, message: String? = nil) {
        guard let index = workspace.entries.firstIndex(where: { $0.id == id }) else { return }
        workspace.entries[index].state = state
        if let message, workspace.entries[index].text.isEmpty { workspace.entries[index].text = message }
        do { try store.save(workspace) }
        catch { errorMessage = "The reply is visible but could not be saved. Check available storage before closing the app." }
    }

    func session(for key: String) -> String? { workspace.sessions?[key] }
    func setSession(_ id: String, for key: String) { commit { value in if value.sessions == nil { value.sessions = [:] }; value.sessions?[key] = id } }
    func clearSession(for key: String) { commit { $0.sessions?.removeValue(forKey: key) } }

    @discardableResult
    private func commit(_ change: (inout Workspace) -> Void) -> Bool {
        guard !loadFailed else { errorMessage = "Saved data could not be read. It has been kept. Restore the file or explicitly reset conversations before writing new data."; return false }
        var updated = workspace
        change(&updated)
        do { try store.save(updated); workspace = updated; return true }
        catch { errorMessage = "Your changes could not be saved. Check available device storage and try again."; return false }
    }
}
