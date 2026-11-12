import SwiftUI

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var workspace = Workspace() { didSet { entryRevision &+= 1 } }
    @Published var previewEnabled = false
    @Published var errorMessage: String?
    @Published var search = ""
    let client: any HarnessClient = UnverifiedHarnessClient()
    private let store: WorkspaceStore
    private var loadFailed = false
    /// When on, changes appear at once and are written to disk a moment later on a background queue, so a click never waits for the disk.
    /// Call `flushSaves()` when the app is about to quit. Off by default so tests and simple callers get an immediate write.
    private let deferSaves: Bool
    private var dirty = false
    private var saveGeneration = 0
    private let saveQueue = DispatchQueue(label: "org.opengrokbot.workspace-save", qos: .utility)
    private var entryRevision = 0
    private var entryCache: (revision: Int, byBot: [UUID: [Entry]])?
    private var pendingReplyText: [UUID: String] = [:]
    private var replyFlushScheduled = false

    init(store: WorkspaceStore = .application, deferSaves: Bool = false) { self.store = store; self.deferSaves = deferSaves }

    var visibleBots: [Bot] {
        let matchingChats = search.isEmpty ? Set<UUID>() : Set(workspace.entries.filter { $0.text.localizedCaseInsensitiveContains(search) }.map(\.botID))
        return workspace.bots.enumerated().filter {
            (search.isEmpty && $0.element.hidden != true) || (!search.isEmpty && ($0.element.name.localizedCaseInsensitiveContains(search) || $0.element.purpose.localizedCaseInsensitiveContains(search) || matchingChats.contains($0.element.id)))
        }.sorted { ($0.element.sortOrder ?? $0.offset) < ($1.element.sortOrder ?? $1.offset) }.map(\.element)
    }

    func recentlyUsed(_ bots: [Bot]) -> [Bot] {
        var latest: [UUID:Date] = [:]
        for bot in bots { if let value = bot.lastUsedAt.flatMap(BotSchedule.date) { latest[bot.id] = max(latest[bot.id] ?? .distantPast, value) } }
        return bots.enumerated().sorted { left, right in
            let a = latest[left.element.id] ?? .distantPast, b = latest[right.element.id] ?? .distantPast
            return a == b ? left.offset < right.offset : a > b
        }.map(\.element)
    }
    @discardableResult
    func touchBot(_ id: UUID) -> Bool {
        guard let index = workspace.bots.firstIndex(where: { $0.id == id }) else { return false }
        let formatter = ISO8601DateFormatter(); formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return commit { $0.bots[index].lastUsedAt = formatter.string(from: Date()) }
    }
    @discardableResult
    func updateDetails(_ bot: Bot, name: String, purpose: String, memory: [String]) -> Bool {
        let cleaned = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let index = workspace.bots.firstIndex(where: { $0.id == bot.id }), !cleaned.isEmpty, cleaned.count <= 200,
              purpose.count <= 2000, memory.count <= 100, memory.allSatisfy({ !$0.isEmpty && $0.count <= 2000 }),
              !workspace.bots.contains(where: { $0.id != bot.id && $0.name.caseInsensitiveCompare(cleaned) == .orderedSame }) else {
            errorMessage = "Use a unique Bot name, a purpose up to 2,000 characters, and at most 100 memory items up to 2,000 characters each."
            return false
        }
        return commit { value in value.bots[index].name = cleaned; value.bots[index].purpose = purpose; value.bots[index].memory = memory }
    }
    /// Replaces the memory every Bot shares (used to remove or add items).
    @discardableResult
    func updateSharedMemory(_ items: [String]) -> Bool {
        let cleaned = items.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        guard cleaned.count <= 100, cleaned.allSatisfy({ $0.count <= 2000 }) else {
            errorMessage = "Shared memory can hold at most 100 items of up to 2,000 characters each."
            return false
        }
        return commit { $0.sharedMemory = cleaned }
    }
    func enterPreview() {
        do { workspace = try store.load() ?? .fresh }
        catch {
            workspace = .fresh
            loadFailed = true
            errorMessage = "Saved workspace could not be read. Your saved file has been kept."
        }
        previewEnabled = true
        var interrupted = false
        for bot in workspace.bots.indices {
            for index in (workspace.bots[bot].schedules ?? []).indices where workspace.bots[bot].schedules?[index].lastResult == "running" {
                workspace.bots[bot].schedules?[index].lastResult = "interrupted"
                if let history = workspace.bots[bot].schedules?[index].history {
                    workspace.bots[bot].schedules?[index].history = history.map { run in var item = run; if item.status == "running" { item.status = "interrupted" }; return item }
                }
                interrupted = true
            }
        }
        if interrupted && !loadFailed { do { try store.save(workspace) } catch { errorMessage = "The interrupted routine status could not be saved." } }
        for index in (workspace.teamMessages ?? []).indices where workspace.teamMessages?[index].status == .running { workspace.teamMessages?[index].status = .failed }
        for index in workspace.entries.indices where workspace.entries[index].state == .streaming {
            workspace.entries[index].state = .stopped
            if workspace.entries[index].text.isEmpty { workspace.entries[index].text = "Response interrupted when the app closed." }
        }
    }

    func applyRemoteSnapshot(_ snapshot: Workspace) { workspace = snapshot; previewEnabled = true; loadFailed = false }

    func leavePreview() { previewEnabled = false; search = "" }
    /// Messages grouped by Bot, rebuilt once after each change instead of by every row on every redraw.
    func entries(for bot: Bot) -> [Entry] {
        if entryCache?.revision != entryRevision { entryCache = (entryRevision, Dictionary(grouping: workspace.entries, by: \.botID)) }
        return entryCache?.byBot[bot.id] ?? []
    }
    func latest(for bot: Bot) -> String { entries(for: bot).last?.text ?? bot.purpose }

    @discardableResult
    func addNote(_ text: String, to bot: Bot, id: UUID? = nil, automated: Bool = false) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard previewEnabled, !trimmed.isEmpty, workspace.bots.contains(where: { $0.id == bot.id }) else { return false }
        var entry = Entry(botID: bot.id, kind: .user, text: trimmed, id: id ?? UUID()); entry.delivery = automated ? "scheduled" : "delivered"
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
        var selected = configuration; if selected.replyMode != .compare || selected.providers.count < 2 { selected.replyMode = .one }
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

    /// Adds a copied Bot and its history as one saved change. The caller has already rebuilt it with fresh IDs.
    @discardableResult
    func importBot(_ bot: Bot, entries: [Entry], note: String) -> Bool {
        guard bot.memberIDs == nil, workspace.bots.count < 100, !workspace.bots.contains(where: { $0.id == bot.id }) else { return false }
        return commit { value in
            value.bots.append(bot)
            value.entries.append(contentsOf: entries)
            value.entries.append(Entry(botID: bot.id, kind: .activity, text: note))
        }
    }

    /// A new group chat of 2 to 8 individual Bots.
    @discardableResult
    func addGroup(name: String, members: [UUID]) -> Bool {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let valid = members.filter { id in workspace.bots.contains { $0.id == id && $0.memberIDs == nil } }
        guard previewEnabled, !clean.isEmpty, clean.count <= 200, (2...8).contains(Set(valid).count), workspace.bots.count < 100,
              !workspace.bots.contains(where: { $0.name.caseInsensitiveCompare(clean) == .orderedSame }) else { return false }
        var group = Bot(id: UUID(), name: clean, purpose: "Group conversation", color: "ochre", symbol: "person.3")
        group.memberIDs = Array(Set(valid))
        return commit { $0.bots.append(group) }
    }

    @discardableResult
    func renameBot(_ bot: Bot, to name: String) -> Bool {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let index = workspace.bots.firstIndex(where: { $0.id == bot.id }), !clean.isEmpty, clean.count <= 200,
              !workspace.bots.contains(where: { $0.id != bot.id && $0.name.caseInsensitiveCompare(clean) == .orderedSame }) else { return false }
        return commit { $0.bots[index].name = clean }
    }

    @discardableResult
    func setHidden(_ hidden: Bool, for bot: Bot) -> Bool {
        guard let index = workspace.bots.firstIndex(where: { $0.id == bot.id }), bot.isMain != true || !hidden else { return false }
        return commit { $0.bots[index].hidden = hidden ? true : nil }
    }

    /// Saves this Bot's voice choices (nil or empty goes back to the app-wide settings). Speed is kept between 0.75 and 1.5.
    @discardableResult
    func setVoice(_ voice: BotVoice?, for botID: UUID) -> Bool {
        guard let index = workspace.bots.firstIndex(where: { $0.id == botID }) else { return false }
        var clean = voice
        if let speed = clean?.speed { clean?.speed = min(max(speed, 0.75), 1.5) }
        if let code = clean?.language, !VoiceSettings.languages.contains(where: { $0.code == code }) { clean?.language = nil }
        if let name = clean?.speaker, VoiceProvider(rawValue: name) == nil { clean?.speaker = nil }
        let value = (clean?.isEmpty ?? true) ? nil : clean
        guard workspace.bots[index].voice != value else { return true }
        return commit { $0.bots[index].voice = value }
    }

    @discardableResult
    func setUnread(_ unread: Bool, for botID: UUID) -> Bool {
        guard let index = workspace.bots.firstIndex(where: { $0.id == botID }), (workspace.bots[index].unread == true) != unread else { return false }
        return commit { $0.bots[index].unread = unread ? true : nil }
    }

    /// One emoji reaction per message; nil clears it.
    @discardableResult
    func setReaction(_ emoji: String?, for entryID: UUID) -> Bool {
        guard let index = workspace.entries.firstIndex(where: { $0.id == entryID }), (emoji?.count ?? 0) <= 8 else { return false }
        return commit { $0.entries[index].reaction = emoji }
    }

    @discardableResult
    func setPinned(_ pinned: Bool, for entryID: UUID) -> Bool {
        guard let index = workspace.entries.firstIndex(where: { $0.id == entryID }) else { return false }
        return commit { $0.entries[index].pinned = pinned ? true : nil }
    }

    @discardableResult
    func deleteEntry(_ id: UUID) -> Bool {
        guard workspace.entries.contains(where: { $0.id == id && $0.state != .streaming }) else { return false }
        return commit { $0.entries.removeAll { $0.id == id } }
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
    func createSchedule(_ task: BotSchedule, botID: UUID) -> Bool {
        guard let index = workspace.bots.firstIndex(where: { $0.id == botID }),
              !task.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, task.name.count <= 200,
              !task.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, task.text.count <= 8000,
              (workspace.bots[index].schedules ?? []).count < 100,
              (task.eventBased ? task.recurrence == "none" && (task.contains?.count ?? 0) <= 200 : task.nextRun.flatMap(BotSchedule.date).map({ $0 > Date() }) == true),
              ["none", "hourly", "daily", "weekly"].contains(task.recurrence), TimeZone(identifier: task.timezone) != nil else {
            errorMessage = "Enter a valid name, instruction, time zone and trigger. Timed routines need a future time."
            return false
        }
        return commit { value in
            if value.bots[index].schedules == nil { value.bots[index].schedules = [] }
            value.bots[index].schedules?.append(task)
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
    /// Records something that happened on this Mac (new mail, an event about to start) that can start a routine.
    func triggerEvent(_ text: String, source: String, for botID: UUID) {
        _ = commit { var entry = Entry(botID: botID, kind: .activity, text: text); entry.provider = "trigger:" + source; $0.entries.append(entry) }
    }

    /// Finishes a reply with plain text and no tool actions (used when several models answer the same question).
    func completeReply(_ replyID: UUID, text: String) {
        _ = commit { value in
            if let index = value.entries.firstIndex(where: { $0.id == replyID }) { value.entries[index].text = text; value.entries[index].state = .complete }
        }
    }

    func activity(_ text: String, for botID: UUID, detail: String? = nil) {
        _ = commit { var entry = Entry(botID: botID, kind: .activity, text: text); entry.detail = detail; $0.entries.append(entry) }
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
                case "browse_web", "open_vm", "vm_exec", "vm_use": break // Executed by the desktop after successful CLI completion.
                case let name where name.hasPrefix("apple_") || name.hasPrefix("browser_") || ["secure_login", "search_web", "search_knowledge", "read_knowledge"].contains(name): break // Mac-only tools, executed by the Mac app after successful CLI completion.
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
                case "forget":
                    guard let wanted = action.text?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), wanted.count >= 3, wanted.count <= 2000,
                          action.scope == "private" || action.scope == "shared" else { note("Nothing forgotten: choose private or shared and name the item (at least 3 characters)."); continue }
                    var removed = 0
                    if action.scope == "shared" {
                        let before = value.sharedMemory ?? []; let kept = before.filter { !$0.lowercased().contains(wanted) }
                        removed = before.count - kept.count; value.sharedMemory = kept
                    } else if let index = value.bots.firstIndex(where: { $0.id == bot.id }) {
                        let before = value.bots[index].memory ?? []; let kept = before.filter { !$0.lowercased().contains(wanted) }
                        removed = before.count - kept.count; value.bots[index].memory = kept
                    }
                    note(removed == 0 ? "No memory matched “\(String(wanted.prefix(60)))”" : "Forgot \(removed) memory item\(removed == 1 ? "" : "s")")
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

    /// Streaming text arrives many times a second. Only the newest text matters, so it is shown at most about twenty times a second.
    func updateReply(_ id: UUID, text: String) {
        pendingReplyText[id] = text
        guard !replyFlushScheduled else { return }
        replyFlushScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in MainActor.assumeIsolated { self?.flushReplyText() } }
    }

    private func flushReplyText() {
        replyFlushScheduled = false
        guard !pendingReplyText.isEmpty else { return }
        let pending = pendingReplyText; pendingReplyText = [:]
        for (id, text) in pending {
            // The streaming message is at the end, so search from there.
            guard let index = workspace.entries.lastIndex(where: { $0.id == id }), workspace.entries[index].text != text else { continue }
            workspace.entries[index].text = text
        }
    }

    func finishReply(_ id: UUID, state: MessageState, message: String? = nil) {
        flushReplyText()
        guard let index = workspace.entries.lastIndex(where: { $0.id == id }) else { return }
        workspace.entries[index].state = state
        if let message, workspace.entries[index].text.isEmpty { workspace.entries[index].text = message }
        if deferSaves { scheduleSave(); return }
        do { try store.save(workspace) }
        catch { errorMessage = "The reply is visible but could not be saved. Check available storage before closing the app." }
    }

    // MARK: Saving
    private func scheduleSave() {
        dirty = true; saveGeneration &+= 1
        let generation = saveGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in MainActor.assumeIsolated { self?.writeIfCurrent(generation) } }
    }

    private func writeIfCurrent(_ generation: Int) {
        guard generation == saveGeneration, dirty else { return }
        dirty = false
        let snapshot = workspace, store = store
        saveQueue.async { [weak self] in
            do { try store.save(snapshot) }
            catch { DispatchQueue.main.async { MainActor.assumeIsolated { self?.errorMessage = "Your changes could not be saved. Check available device storage and try again." } } }
        }
    }

    /// Writes any pending change now, after any write already under way. Call when the app is about to quit or go to the background.
    func flushSaves() {
        flushReplyText()
        guard dirty else { return }
        dirty = false; saveGeneration &+= 1
        let snapshot = workspace, store = store
        do { try saveQueue.sync { try store.save(snapshot) } }
        catch { errorMessage = "Your changes could not be saved. Check available device storage and try again." }
    }

    /// Replaces everything with a restored backup. CLI session IDs belong to the original device and are dropped.
    @discardableResult
    func restoreWorkspace(_ restored: Workspace) -> Bool {
        guard restored.bots.filter({ $0.isMain == true }).count == 1 else { errorMessage = "This backup is missing its main Bot."; return false }
        var value = restored
        value.sessions = [:]
        for index in value.entries.indices where value.entries[index].state == .streaming { value.entries[index].state = .stopped }
        loadFailed = false
        return commit { $0 = value }
    }

    func session(for key: String) -> String? { workspace.sessions?[key] }
    func setSession(_ id: String, for key: String) { commit { value in if value.sessions == nil { value.sessions = [:] }; value.sessions?[key] = id } }
    func clearSession(for key: String) { commit { $0.sessions?.removeValue(forKey: key) } }

    @discardableResult
    private func commit(_ change: (inout Workspace) -> Void) -> Bool {
        guard !loadFailed else { errorMessage = "Saved data could not be read. It has been kept. Restore the file or explicitly reset conversations before writing new data."; return false }
        if deferSaves { change(&workspace); scheduleSave(); return true }
        var updated = workspace
        change(&updated)
        do { try store.save(updated); workspace = updated; return true }
        catch { errorMessage = "Your changes could not be saved. Check available device storage and try again."; return false }
    }
}
