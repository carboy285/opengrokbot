import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Ready-made Bots, and a plain file format for sharing a Bot with a friend. A shared Bot carries only its name, job and color:
/// never memory, chats, logins, files or settings.
struct BotTemplate: Identifiable, Equatable {
    let id: String
    let name: String
    let purpose: String
    let color: String
    let symbol: String

    static let all: [BotTemplate] = [
        BotTemplate(id: "fantasy", name: "Fantasy Sports Helper", purpose: "Help me win my fantasy leagues: read my league pages, compare players, suggest drafts, trades and lineups, and explain why. Keep answers short and ask before changing anything.", color: "ochre", symbol: "sportscourt"),
        BotTemplate(id: "inbox", name: "Inbox Triage", purpose: "Look through my recent Mail, tell me what needs a reply or action, and draft replies for me to review. Never send anything without asking me first.", color: "pink", symbol: "envelope"),
        BotTemplate(id: "briefing", name: "Daily Briefing", purpose: "Every morning give me a short briefing: my calendar and reminders for today, anything urgent in my email, and the weather and news I care about.", color: "purple", symbol: "sun.max"),
        BotTemplate(id: "research", name: "Research Assistant", purpose: "Research a question across several sources, compare them, and give me a clear answer with the links you used. Say how sure you are.", color: "white", symbol: "magnifyingglass"),
        BotTemplate(id: "travel", name: "Trip Planner", purpose: "Plan trips: find options, build a day-by-day itinerary, and keep a packing list. Never book or pay for anything without asking me.", color: "ochre", symbol: "airplane"),
        BotTemplate(id: "study", name: "Study Buddy", purpose: "Teach me what I am studying, quiz me, make flashcards from my Knowledge files, and keep track of what I find hard.", color: "purple", symbol: "book"),
        BotTemplate(id: "writing", name: "Writing Coach", purpose: "Improve my writing while keeping my voice: tighten drafts, fix mistakes, and explain the changes briefly.", color: "pink", symbol: "pencil"),
        BotTemplate(id: "home", name: "Home & Errands", purpose: "Keep my reminders, shopping lists and household to-dos organized. Put things in the right Reminders list and remind me at the right time.", color: "white", symbol: "house")
    ]
}

struct SharedBot: Codable, Equatable {
    var format = "opengrokbot-bot"
    var version = 1
    var name: String
    var purpose: String
    var color: String

    static let fileExtension = "opengrokbot"
    static let colors: Set<String> = ["purple", "pink", "ochre", "white"]

    init(name: String, purpose: String, color: String) { self.name = name; self.purpose = purpose; self.color = color }
    init(_ bot: Bot) { self.init(name: bot.name, purpose: bot.purpose, color: bot.color) }

    func encoded() throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }

    /// Nil unless the file is a small, well-formed shared Bot. Unknown colors fall back to purple.
    static func decode(_ data: Data) -> SharedBot? {
        guard data.count <= 20_000, let shared = try? JSONDecoder().decode(SharedBot.self, from: data), shared.format == "opengrokbot-bot", shared.version == 1 else { return nil }
        let name = shared.name.trimmingCharacters(in: .whitespacesAndNewlines), purpose = shared.purpose.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (1...60).contains(name.count), purpose.count <= 2000, !name.contains(where: \.isNewline) else { return nil }
        return SharedBot(name: name, purpose: purpose, color: colors.contains(shared.color) ? shared.color : "purple")
    }
}

enum BotSharing {
    @MainActor static func export(_ bot: Bot) -> String? {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = bot.name.replacingOccurrences(of: "/", with: "-") + "." + SharedBot.fileExtension
        panel.message = "This file holds only the Bot’s name and job. Memory, chats, logins and files stay on this Mac."
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        do { try SharedBot(bot).encoded().write(to: url, options: .atomic); return "Saved “\(url.lastPathComponent)”." } catch { return "The Bot could not be saved." }
    }

    @MainActor static func choose() -> SharedBot? {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false; panel.canChooseDirectories = false
        panel.message = "Choose a Bot file someone shared with you."
        guard panel.runModal() == .OK, let url = panel.url, (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) ?? 0 <= 20_000, let data = try? Data(contentsOf: url) else { return nil }
        return SharedBot.decode(data)
    }
}
