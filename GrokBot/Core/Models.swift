import Foundation

struct Bot: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    var name: String
    var purpose: String
    var color: String
    var symbol: String
}

struct Entry: Identifiable, Codable, Equatable, Sendable {
    enum Kind: String, Codable, Sendable { case user, bot, activity }
    let id: UUID
    let botID: UUID
    let kind: Kind
    var text: String
    let date: Date

    init(botID: UUID, kind: Kind, text: String) {
        id = UUID()
        self.botID = botID
        self.kind = kind
        self.text = text
        date = Date()
    }
}

struct Workspace: Codable, Equatable, Sendable {
    var bots: [Bot] = []
    var entries: [Entry] = []

    static var preview: Workspace {
        let bots = [
            Bot(id: UUID(), name: "Grok Bot", purpose: "A place to bring it all together", color: "white", symbol: "sparkles"),
            Bot(id: UUID(), name: "Soccer & Percussion", purpose: "Practice plans, one day at a time", color: "purple", symbol: "music.note"),
            Bot(id: UUID(), name: "AI Brief", purpose: "Research worth your time", color: "purple", symbol: "newspaper"),
            Bot(id: UUID(), name: "STEMBound", purpose: "Make room for your next idea", color: "pink", symbol: "atom"),
            Bot(id: UUID(), name: "School", purpose: "Make a plan for the week ahead", color: "ochre", symbol: "book.closed")
        ]
        return Workspace(bots: bots, entries: [
            Entry(botID: bots[0].id, kind: .bot, text: "Your week is coming together. You’ve got percussion practice, a STEMBound meeting, and a Spanish test on Wednesday.\n\nWant me to have the School bot help you study for Wednesday’s Spanish test?"),
            Entry(botID: bots[0].id, kind: .user, text: "Sure"),
            Entry(botID: bots[0].id, kind: .activity, text: "Messaged · School"),
            Entry(botID: bots[0].id, kind: .bot, text: "I sent it to the School bot. It’ll ask you in its own chat what the Spanish test covers, then put together a study plan for Sunday through Tuesday and some practice questions. Do you have a study guide or notes you can share with it?"),
            Entry(botID: bots[0].id, kind: .activity, text: "Message from · School"),
            Entry(botID: bots[0].id, kind: .user, text: "Yea"),
            Entry(botID: bots[0].id, kind: .bot, text: "Nice! Send it right here, either a photo of the study guide or a quick list of the topics, and I’ll pass it to School so it can build your plan."),
            Entry(botID: bots[1].id, kind: .bot, text: "Want me to set up those snare drum routines for the week?"),
            Entry(botID: bots[2].id, kind: .bot, text: "Which workflow do you want? A quick daily brief, a deeper research note, or a running list of ideas?"),
            Entry(botID: bots[3].id, kind: .bot, text: "What’s on your plate right now?"),
            Entry(botID: bots[4].id, kind: .bot, text: "What do you need help with for Wednesday’s Spanish test?")
        ])
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
