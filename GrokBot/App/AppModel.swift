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
        let matchingChats = search.isEmpty ? Set<UUID>() : Set(workspace.entries.filter { $0.text.localizedCaseInsensitiveContains(search) }.map(\.botID))
        return workspace.bots.enumerated().filter {
            search.isEmpty || $0.element.name.localizedCaseInsensitiveContains(search) || $0.element.purpose.localizedCaseInsensitiveContains(search) || matchingChats.contains($0.element.id)
        }.sorted { ($0.element.sortOrder ?? $0.offset) < ($1.element.sortOrder ?? $1.offset) }.map(\.element)
    }

    func recentlyUsed(_ bots: [Bot]) -> [Bot] {
        var latest: [UUID:Date] = [:]
        for entry in workspace.entries { latest[entry.botID] = max(latest[entry.botID] ?? .distantPast, entry.date) }
        for bot in bots { if let value = bot.lastUsedAt.flatMap(BotSchedule.date) { latest[bot.id] = max(latest[bot.id] ?? .distantPast, value) } }
        return bots.enumerated().sorted { left, right in
            let a = latest[left.element.id] ?? .distantPast, b = latest[right.element.id] ?? .distantPast
            return a == b ? left.offset < right.offset : a > b
        }.map(\.element)
    }
    @discardableResult
    func touchBot(_ id: UUID) -> Bool {
        guard let index = workspace.bots.firstIndex(where: { $0.id == id }) else { return false }
        if let last = workspace.bots[index].lastUsedAt.flatMap(BotSchedule.date), Date().timeIntervalSince(last) < 2 { return true }
        return commit { $0.bots[index].lastUsedAt = ISO8601DateFormatter().string(from: Date()) }
    }
    func enterPreview() {
        do { workspace = try store.load() ?? .fresh }
        catch {
            workspace = .fresh
            loadFailed = true
            errorMessage = "Saved workspace could not be read. Your saved file has been kept."
        }
        previewEnabled = true
        for index in (workspace.teamMessages ?? []).indices where workspace.teamMessages?[index].status == .running { workspace.teamMessages?[index].status = .failed }
        for index in workspace.entries.indices where workspace.entries[index].state == .streaming {
            workspace.entries[index].state = .stopped
            if workspace.entries[index].text.isEmpty { workspace.entries[index].text = "Response interrupted when the app closed." }
        }
    }

    func applyRemoteSnapshot(_ snapshot: Workspace) { workspace = snapshot; previewEnabled = true; loadFailed = false }

    func leavePreview() { previewEnabled = false; search = "" }
    func entries(for bot: Bot) -> [Entry] { workspace.entries.filter { $0.botID == bot.id } }
    func latest(for bot: Bot) -> String { entries(for: bot).last?.text ?? bot.purpose }

    @discardableResult
    func addNote(_ text: String, to bot: Bot, id: UUID? = nil) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard previewEnabled, !trimmed.isEmpty, workspace.bots.contains(where: { $0.id == bot.id }) else { return false }
        var entry = Entry(botID: bot.id, kind: .user, text: trimmed, id: id ?? UUID()); entry.delivery = "delivered"
        return commit { $0.entries.append(entry) }
    }

    @discardableResult
    func addBot(name: String, purpose: String, color: String) -> Bool {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard previewEnabled, !cleanName.isEmpty, !workspace.bots.contains(where: { $0.name.caseInsensitiveCompare(cleanName) == .orderedSame }) else { return false }
        return commit { $0.bots.append(Bot(id: UUID(), name: cleanName, purpose: purpose, color: color, symbol: "sparkles")) }
    }

    @discardableResult
    func setAIConfiguration(_ configuration: BotAIConfiguration, for bot: Bot) -> Bool {
        guard let index = workspace.bots.firstIndex(where: { $0.id == bot.id }),
              configuration.providers.count <= CLIProvider.allCases.count,
              Set(configuration.providers.map(\.provider)).count == configuration.providers.count,
              configuration.providers.allSatisfy({ $0.model.count <= 200 && !$0.model.contains(where: { $0.isNewline }) }) else { return false }
        var selected = configuration; selected.replyMode = .one
        return commit { $0.bots[index].aiConfiguration = selected }
    }

    @discardableResult
    func organize(_ bot: Bot, pinned: Bool? = nil, folder: String? = nil) -> Bool {
        guard let index = workspace.bots.firstIndex(where: { $0.id == bot.id }), (folder?.count ?? 0) <= 80 else { return false }
        return commit {
            if let pinned { $0.bots[index].isPinned = pinned }
            if let folder { $0.bots[index].folder = folder.trimmingCharacters(in: .whitespacesAndNewlines) }
        }
    }
    @discardableResult
    func moveBot(_ id: UUID, before target: UUID) -> Bool {
        guard id != target, workspace.bots.contains(where: { $0.id == id }), workspace.bots.contains(where: { $0.id == target }) else { return false }
        var ids = workspace.bots.enumerated().sorted { ($0.element.sortOrder ?? $0.offset) < ($1.element.sortOrder ?? $1.offset) }.map { $0.element.id }
        ids.removeAll { $0 == id }; guard let index = ids.firstIndex(of: target) else { return false }; ids.insert(id, at: index)
        return commit { value in for index in value.bots.indices { value.bots[index].sortOrder = ids.firstIndex(of: value.bots[index].id) } }
    }

    func removeBot(_ bot: Bot) {
        guard bot.isMain != true else { return }
        commit { value in
            value.bots.removeAll { $0.id == bot.id }
            value.entries.removeAll { $0.botID == bot.id }
            value.teamMessages?.removeAll { $0.to == bot.id || $0.from == bot.id }
            for index in value.bots.indices { value.bots[index].memberIDs?.removeAll { $0 == bot.id } }
            value.sessions = value.sessions?.filter { !$0.key.hasPrefix(bot.id.uuidString + "|") }
        }
    }

    @discardableResult
    func setAppearance(_ appearance: BotAppearance?, for bot: Bot) -> Bool {
        guard appearance?.valid != false,
              let index = workspace.bots.firstIndex(where: { $0.id == bot.id }) else { return false }
        return commit {
            $0.bots[index].appearance = appearance
            $0.bots[index].color = appearance?.color ?? (bot.isMain == true ? "white" : "purple")
        }
    }

    @discardableResult
    func updateSchedule(_ task: BotSchedule, botID: UUID) -> Bool {
        guard let bot = workspace.bots.firstIndex(where: { $0.id == botID }), let index = workspace.bots[bot].schedules?.firstIndex(where: { $0.id == task.id }) else { return false }
        return commit { $0.bots[bot].schedules?[index] = task }
    }
    @discardableResult
    func removeSchedule(_ id: UUID, botID: UUID) -> Bool {
        guard let bot = workspace.bots.firstIndex(where: { $0.id == botID }) else { return false }
        return commit { $0.bots[bot].schedules?.removeAll { $0.id == id } }
    }
    func activity(_ text: String, for botID: UUID) {
        _ = commit { $0.entries.append(Entry(botID: botID, kind: .activity, text: text)) }
    }

    /// Applies only completed assistant output; all mutations save together before publishing.
    @discardableResult
    func applyBotActions(_ response: String, replyID: UUID, bot: Bot, configuration: BotAIConfiguration, delivery: TeamMessage?) -> Bool {
        guard workspace.bots.contains(where: { $0.id == bot.id }) else { return false }
        let parsed = BotTeamwork.parse(response)
        return commit { value in
            if let index = value.entries.firstIndex(where: { $0.id == replyID }) {
                value.entries[index].text = parsed.text
                value.entries[index].state = .complete
            }
            let root = delivery?.rootID ?? replyID, depth = delivery?.depth ?? 0
            func note(_ text: String) { value.entries.append(Entry(botID: bot.id, kind: .activity, text: text)) }
            func target(_ name: String) -> Bot? { value.bots.first { $0.id.uuidString.caseInsensitiveCompare(name) == .orderedSame || $0.name.caseInsensitiveCompare(name) == .orderedSame } }
            for action in parsed.actions {
                switch action.action {
                case "browse_web", "open_vm", "vm_exec": break // Executed by the desktop after successful CLI completion.
                case "schedule_task":
                    guard delivery == nil, value.entries.last(where: { $0.botID == bot.id && $0.kind == .user })?.text.hasPrefix("Scheduled task:") != true, !(value.bots.first(where: { $0.id == bot.id })?.schedules ?? []).contains(where: { $0.name == action.name && $0.enabled }),
                          let task = BotSchedule.make(action), let index = value.bots.firstIndex(where: { $0.id == bot.id }), (value.bots[index].schedules ?? []).count < 100 else { note("Task not scheduled: use a unique name, a future ISO date, valid timezone and recurrence, or message_received trigger."); continue }
                    if value.bots[index].schedules == nil { value.bots[index].schedules = [] }
                    var created = task
                    created.lastEvent = value.entries.last(where: { $0.botID == bot.id && $0.senderBotID != nil && $0.kind == .activity })?.id
                    value.bots[index].schedules?.append(created)
                    note("Scheduled · \(task.name) · \(task.nextRun ?? "on incoming Bot message") · \(task.recurrence) · desktop must be available")
                case "list_tasks":
                    let tasks = value.bots.first(where: { $0.id == bot.id })?.schedules ?? []
                    let descriptions = tasks.map { task in
                        "\(task.id): \(task.name) · \(task.enabled ? (task.nextRun ?? "message_received") : "paused") · \(task.recurrence) · \(task.timezone)"
                    }
                    note(descriptions.isEmpty ? "No scheduled tasks." : descriptions.joined(separator: "\n"))
                case "cancel_task":
                    guard delivery == nil, value.entries.last(where: { $0.botID == bot.id && $0.kind == .user })?.text.hasPrefix("Scheduled task:") != true, let id = action.id.flatMap(UUID.init(uuidString:)), let index = value.bots.firstIndex(where: { $0.id == bot.id }) else { note("Task not cancelled: use its exact UUID."); continue }
                    value.bots[index].schedules?.removeAll { $0.id == id }; note("Cancelled task · \(id)")
                case "create_bot":
                    guard let name = action.name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty, name.count <= 200,
                          let purpose = action.purpose, purpose.count <= 2000, value.bots.count < 100, target(name) == nil else { note("Bot could not be created: use a unique name and a description of up to 2,000 characters."); continue }
                    var created = Bot(id: UUID(), name: name, purpose: purpose, color: "purple", symbol: "sparkles")
                    created.aiConfiguration = configuration
                    value.bots.append(created); note("Created · \(name)")
                case "message_bot":
                    guard let name = action.to, let recipient = target(name), recipient.memberIDs == nil, recipient.id != bot.id,
                          let text = action.text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, text.count <= 8000,
                          depth < 4, (value.teamMessages ?? []).filter({ $0.rootID == root }).count < 12 else { note("Message not sent: choose another Bot and keep requests within the teamwork limits."); continue }
                    let message = TeamMessage(id: UUID(), rootID: root, from: bot.id, to: recipient.id, text: text, depth: depth + 1)
                    if value.teamMessages == nil { value.teamMessages = [] }; value.teamMessages?.append(message)
                    note("Queued message · \(recipient.name)")
                case "remember":
                    guard let text = action.text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty, text.count <= 2000,
                          action.scope == "private" || action.scope == "shared" else { note("Memory not saved: choose private or shared and use up to 2,000 characters."); continue }
                    if action.scope == "shared" {
                        var memory = value.sharedMemory ?? []; if !memory.contains(text) { memory.append(text) }
                        guard memory.count <= 100 else { note("Shared memory is full."); continue }; value.sharedMemory = memory
                    } else if let index = value.bots.firstIndex(where: { $0.id == bot.id }) {
                        var memory = value.bots[index].memory ?? []; if !memory.contains(text) { memory.append(text) }
                        guard memory.count <= 100 else { note("This Bot’s memory is full."); continue }; value.bots[index].memory = memory
                    }
                    note(action.scope == "shared" ? "Saved to shared memory" : "Saved to this Bot’s memory")
                case "create_group":
                    guard let name = action.name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty, name.count <= 200, target(name) == nil, value.bots.count < 100,
                          let names = action.members, (2...8).contains(names.count) else { note("Group not created: use a unique name and 2–8 Bots."); continue }
                    let members = names.compactMap { target($0) }.filter { $0.memberIDs == nil }.map(\.id)
                    guard Set(members).count == names.count else { note("Group not created: each member must be a different existing Bot."); continue }
                    var group = Bot(id: UUID(), name: name, purpose: "Group conversation", color: "ochre", symbol: "person.3")
                    group.memberIDs = members; value.bots.append(group); note("Created group · \(name)")
                default: note("Unsupported app operation: \(String(action.action.prefix(60))). Only you can delete Bots or approve external actions.")
                }
            }
            if let delivery, value.bots.contains(where: { $0.id == delivery.from }) {
                var result = Entry(botID: delivery.from, kind: .bot, text: parsed.text.isEmpty ? "Request completed. See \(bot.name)’s chat for activity." : parsed.text)
                result.senderBotID = bot.id; result.senderName = bot.name
                result.provider = value.entries.first(where: { $0.id == replyID })?.provider
                result.state = .complete; value.entries.append(result)
            }
        }
    }

    @discardableResult
    func beginDelivery(_ message: TeamMessage) -> Bool {
        commit { value in
            guard let index = value.teamMessages?.firstIndex(where: { $0.id == message.id }) else { return }
            value.teamMessages?[index].status = .running
            let sender = value.bots.first { $0.id == message.from }?.name ?? "Deleted Bot"
            var entry = Entry(botID: message.to, kind: .activity, text: "Message from \(sender):\n\(message.text)")
            entry.senderBotID = message.from; entry.senderName = sender
            value.entries.append(entry)
        }
    }

    func finishDelivery(_ message: TeamMessage, status: TeamMessage.Status) {
        _ = commit { value in
            if let index = value.teamMessages?.firstIndex(where: { $0.id == message.id }) { value.teamMessages?[index].status = status }
            if status != .complete, value.bots.contains(where: { $0.id == message.from }) {
                let name = value.bots.first { $0.id == message.to }?.name ?? "Deleted Bot"
                value.entries.append(Entry(botID: message.from, kind: .activity, text: "\(name)’s request \(status == .stopped ? "was stopped" : "could not be completed"). Open its chat to check setup or retry."))
            }
        }
    }

    @discardableResult
    func requeueDelivery(to botID: UUID) -> Bool {
        guard let index = workspace.teamMessages?.lastIndex(where: { $0.to == botID && ($0.status == .failed || $0.status == .stopped) }) else { return false }
        return commit { $0.teamMessages?[index].status = .queued }
    }

    func sendGroup(_ text: String, group: Bot, id: UUID? = nil) -> Bool {
        guard text.count <= 8000 else { errorMessage = "Keep group messages within 8,000 characters."; return false }
        guard let members = group.memberIDs, !members.isEmpty else { return false }
        return commit { value in
            let entry = Entry(botID: group.id, kind: .user, text: text, id: id ?? UUID()); value.entries.append(entry)
            if value.teamMessages == nil { value.teamMessages = [] }
            for member in members where value.bots.contains(where: { $0.id == member }) {
                value.teamMessages?.append(TeamMessage(id: UUID(), rootID: entry.id, from: group.id, to: member, text: text, depth: 1))
            }
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
