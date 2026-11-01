import Foundation

struct Bot: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    var name: String
    var purpose: String
    var color: String
    var symbol: String
    var isMain: Bool? = nil
    var aiConfiguration: BotAIConfiguration? = nil
    var memory: [String]? = nil
    var memberIDs: [UUID]? = nil
    var appearance: BotAppearance? = nil
    var isPinned: Bool? = nil
    var folder: String? = nil
    var sortOrder: Int? = nil
    var lastUsedAt: String? = nil
    var schedules: [BotSchedule]? = nil
}

struct BotAppearance: Codable, Hashable, Sendable {
    var shape: BotAvatarShape = .hexagon
    var color = "purple"
    var imageData: Data? = nil
    static let colors = ["black", "ochre", "red", "orange", "amber", "green", "teal", "blue", "purple", "pink", "gray", "white"]
    var valid: Bool { Self.colors.contains(color) && (imageData?.count ?? 0) <= 24_576 }
}

enum BotAvatarShape: String, Codable, CaseIterable, Sendable {
    case circle, cloud, square, sparkle, flower, heart, clover
    case droplet, capsule, triangle, pebble, star, hexagon, fruit
    var label: String { rawValue.capitalized }
}

struct Entry: Identifiable, Codable, Equatable, Sendable {
    enum Kind: String, Codable, Sendable { case user, bot, activity }
    let id: UUID
    let botID: UUID
    let kind: Kind
    var text: String
    var state: MessageState? = nil
    var provider: String? = nil
    var senderBotID: UUID? = nil
    var senderName: String? = nil
    var delivery: String? = nil
    let date: Date

    init(botID: UUID, kind: Kind, text: String, id: UUID = UUID()) {
        self.id = id
        self.botID = botID
        self.kind = kind
        self.text = text
        date = Date()
    }
}

enum MessageState: String, Codable, Sendable { case streaming, complete, stopped, failed }

struct Workspace: Codable, Equatable, Sendable {
    var bots: [Bot] = []
    var entries: [Entry] = []
    var schemaVersion: Int? = 2
    var sessions: [String: String]? = [:]
    var sharedMemory: [String]? = nil
    var teamMessages: [TeamMessage]? = nil

    static var fresh: Workspace {
        Workspace(bots: [Bot(id: UUID(), name: "Grok Bot", purpose: "Your AI assistant, powered by a CLI on this device.", color: "white", symbol: "sparkles", isMain: true)])
    }

    /// Reject inconsistent identities before SwiftUI lists or dictionary construction
    /// can trap. The saved file is preserved when validation fails.
    func validateIdentities() throws {
        var botIDs = Set<UUID>(), entryIDs = Set<UUID>(), teamIDs = Set<UUID>()
        for bot in bots {
            guard botIDs.insert(bot.id).inserted else { throw CloudError.message("The workspace contains duplicate Bot IDs. Restore a valid workspace on the computer.") }
            let schedules = bot.schedules ?? []
            guard schedules.count <= 100, Set(schedules.map(\.id)).count == schedules.count,
                  schedules.allSatisfy({ !$0.name.isEmpty && $0.name.count <= 200 && !$0.text.isEmpty && $0.text.count <= 8000 && ["none","hourly","daily","weekly"].contains($0.recurrence) && TimeZone(identifier: $0.timezone) != nil && ($0.nextRun == nil || BotSchedule.date($0.nextRun ?? "") != nil) }) else { throw CloudError.message("The workspace contains invalid scheduled tasks.") }
        }
        for entry in entries {
            guard entryIDs.insert(entry.id).inserted, botIDs.contains(entry.botID) else { throw CloudError.message("The workspace contains inconsistent message IDs. Refresh or restore it on the computer.") }
        }
        for message in teamMessages ?? [] { guard teamIDs.insert(message.id).inserted else { throw CloudError.message("The workspace contains duplicate teamwork IDs.") } }
    }

    // Kept as a source-compatible alias; no demo Bots or messages are seeded.
    static var preview: Workspace { .fresh }

    mutating func migrateLegacyDemo() {
        guard schemaVersion != 2 else { return }
        let signatures = ["Grok Bot": "A place to bring it all together", "Soccer & Percussion": "Practice plans, one day at a time", "AI Brief": "Research worth your time", "STEMBound": "Make room for your next idea", "School": "Make a plan for the week ahead"]
        let seeded = Set(bots.filter { signatures[$0.name] == $0.purpose }.map(\.id))
        let fixtures: Set<String> = [
            "Your week is coming together. You’ve got percussion practice, a STEMBound meeting, and a Spanish test on Wednesday.\n\nWant me to have the School bot help you study for Wednesday’s Spanish test?",
            "Messaged · School", "Message from · School",
            "I sent it to the School bot. It’ll ask you in its own chat what the Spanish test covers, then put together a study plan for Sunday through Tuesday and some practice questions. Do you have a study guide or notes you can share with it?",
            "Nice! Send it right here, either a photo of the study guide or a quick list of the topics, and I’ll pass it to School so it can build your plan.",
            "Want me to set up those snare drum routines for the week?",
            "Which workflow do you want? A quick daily brief, a deeper research note, or a running list of ideas?",
            "What’s on your plate right now?", "What do you need help with for Wednesday’s Spanish test?",
            "This is an offline interface preview. Nothing here is sent to Grok Bot. You can explore conversations, write local notes, and create preview Bots.",
            "Example handoff · School",
            "A study guide, a few practice questions, and time to review. This is where a Bot’s progress and finished work would appear.",
            "What would you like to work on? Add a local note below to try the conversation layout."
        ]
        let legacyMain = bots.first { $0.name == "Grok Bot" && seeded.contains($0.id) }?.id
        let legacyPrefix = Array(entries.filter { $0.botID == legacyMain }.prefix(7))
        let hasFullFixture = legacyPrefix.count == 7 && legacyPrefix.enumerated().allSatisfy { index, entry in
            if index == 1 { return entry.kind == .user && entry.text == "Sure" }
            if index == 5 { return entry.kind == .user && entry.text == "Yea" }
            return entry.kind != .user && fixtures.contains(entry.text)
        }
        let fixtureUserIDs: Set<UUID> = hasFullFixture ? Set([legacyPrefix[1].id, legacyPrefix[5].id]) : []
        entries = entries.filter { entry in
            if seeded.contains(entry.botID) && entry.kind != .user && fixtures.contains(entry.text) { return false }
            return !fixtureUserIDs.contains(entry.id)
        }
        bots.removeAll { bot in seeded.contains(bot.id) && bot.id != legacyMain && !entries.contains { $0.botID == bot.id } }
        if let main = bots.firstIndex(where: { $0.name == "Grok Bot" && ($0.id == legacyMain || $0.isMain == true) }) {
            bots[main].isMain = true
            bots[main].purpose = "Your AI assistant, powered by a CLI on this device."
            let value = bots.remove(at: main); bots.insert(value, at: 0)
        } else { bots.insert(Self.fresh.bots[0], at: 0) }
        schemaVersion = 2
    }

    private enum CodingKeys: String, CodingKey { case bots, entries, schemaVersion, sessions, sharedMemory, teamMessages }
    init(bots: [Bot] = [], entries: [Entry] = [], schemaVersion: Int? = 2, sessions: [String:String]? = [:]) {
        self.bots = bots; self.entries = entries; self.schemaVersion = schemaVersion; self.sessions = sessions
    }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        bots = try values.decode([Bot].self, forKey: .bots)
        entries = try values.decode([Entry].self, forKey: .entries)
        schemaVersion = try values.decodeIfPresent(Int.self, forKey: .schemaVersion)
        sessions = try values.decodeIfPresent([String:String].self, forKey: .sessions) ?? [:]
        sharedMemory = try values.decodeIfPresent([String].self, forKey: .sharedMemory)
        teamMessages = try values.decodeIfPresent([TeamMessage].self, forKey: .teamMessages)
    }
}

enum IntegrationError: Error, LocalizedError, Equatable {
    case protocolUnverified
    case insecureAddress
    case invalidAddress
    case loopbackAddress

    var errorDescription: String? {
        switch self {
        case .protocolUnverified: "The Grok Bot 0.78.1 client protocol has not been verified. No connection was attempted."
        case .insecureAddress: "Use an HTTPS address with a valid trusted certificate."
        case .invalidAddress: "Enter an HTTPS server address without credentials, a path, query, or fragment."
        case .loopbackAddress: "Localhost points to the device running this app. Use a reachable server hostname."
        }
    }
}

/// A saved origin is a local planning aid, never proof of a compatible service.
struct ConnectionDraft: Codable, Equatable, Sendable {
    let origin: URL

    init(address: String) throws {
        guard let parts = URLComponents(string: address.trimmingCharacters(in: .whitespacesAndNewlines)),
              let host = parts.host, !host.isEmpty,
              parts.user == nil, parts.password == nil,
              parts.query == nil, parts.fragment == nil,
              parts.path.isEmpty || parts.path == "/",
              parts.port == nil || (1...65535).contains(parts.port!),
              let url = parts.url else { throw IntegrationError.invalidAddress }
        guard parts.scheme?.lowercased() == "https" else { throw IntegrationError.insecureAddress }
        let normalized = host.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "[]."))
        guard normalized != "localhost", !normalized.hasSuffix(".localhost"),
              normalized != "::1", normalized != "0.0.0.0", normalized != "::",
              !normalized.hasPrefix("127."), !normalized.hasPrefix("::ffff:127.") else {
            throw IntegrationError.loopbackAddress
        }
        origin = url
    }
}

struct HarnessCapabilities: Sendable {
    let verifiedVersion: String?
    let canConnect: Bool
    let reason: String
    static let unavailable = HarnessCapabilities(verifiedVersion: nil, canConnect: false,
        reason: "The supplied installer is labeled 0.78.1. Its protocol, authentication contract, and compatibility have not been inspected.")
}

/// Intentionally no guessed transport, headers, RPC names, or authentication flow.
protocol HarnessClient: Sendable {
    var capabilities: HarnessCapabilities { get }
    func connect() async throws
    func disconnect() async
}

struct UnverifiedHarnessClient: HarnessClient {
    let capabilities = HarnessCapabilities.unavailable
    func connect() async throws { throw IntegrationError.protocolUnverified }
    func disconnect() async {}
}
