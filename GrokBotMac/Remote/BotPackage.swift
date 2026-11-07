import Foundation

/// Everything needed to copy a Bot to another computer on the same account: its job, provider settings, memory, chat history,
/// routines (paused) and small Knowledge files. It never carries the AI CLI's own session, logins, API keys or other computers' files.
/// A package from another computer is untrusted input, so `sanitized` rebuilds every field with fresh IDs and hard limits.
struct BotPackage: Codable, Sendable {
    struct File: Codable, Sendable { var name: String; var data: Data }

    static let format = "opengrokbot-bot-package"
    static let maxBytes = 2_300_000
    static let maxEntries = 2000
    static let maxKnowledgeBytes = 800_000

    var format = BotPackage.format
    var version = 1
    var sourceName: String
    var bot: Bot
    var entries: [Entry]
    var sharedMemory: [String]?
    var knowledge: [File]

    /// Builds a package from a Bot on this Mac. History is trimmed (newest kept) so the whole thing fits the encrypted relay.
    @MainActor
    static func make(bot: Bot, workspace: Workspace, sourceName: String, directory: URL) -> BotPackage {
        var entries = workspace.entries.filter { $0.botID == bot.id }.map { entry -> Entry in var copy = entry; copy.detail = nil; copy.state = copy.state == .streaming ? .complete : copy.state; return copy }
        if entries.count > maxEntries { entries = Array(entries.suffix(maxEntries)) }
        var knowledge: [File] = [], used = 0
        for url in KnowledgeSearch.files(in: directory) {
            guard let data = try? Data(contentsOf: url), used + data.count <= maxKnowledgeBytes, knowledge.count < 50 else { continue }
            used += data.count; knowledge.append(File(name: url.lastPathComponent, data: data))
        }
        var package = BotPackage(sourceName: sourceName, bot: bot, entries: entries, sharedMemory: workspace.sharedMemory, knowledge: knowledge)
        // Drop the oldest messages until the encoded package fits.
        while package.entries.count > 20, ((try? CloudCoding.encoder().encode(package).count) ?? 0) > maxBytes { package.entries.removeFirst(max(package.entries.count / 5, 1)) }
        return package
    }

    func encoded() throws -> Data { try CloudCoding.encoder().encode(self) }

    static func decode(_ data: Data) throws -> BotPackage {
        guard data.count <= maxBytes + 400_000, let package = try? CloudCoding.decoder().decode(BotPackage.self, from: data), package.format == Self.format, package.version == 1 else {
            throw CloudError.message("That is not a Bot package this version understands. Update OpenGrokBot on both computers.")
        }
        return package
    }

    struct Clean { var bot: Bot; var entries: [Entry]; var knowledge: [File] }

    /// A fresh Bot and history from this package: new IDs, no groups, no main-Bot status, routines paused, providers limited to those
    /// installed here (or the default provider), names made unique.
    func sanitized(existingNames: [String], installed: [CLIProvider], defaultProvider: CLIProvider?) -> Clean? {
        guard bot.memberIDs == nil else { return nil }
        let id = UUID()
        var name = String(bot.name.trimmingCharacters(in: .whitespacesAndNewlines).filter { !$0.isNewline }.prefix(60))
        guard !name.isEmpty else { return nil }
        let taken = Set(existingNames.map { $0.lowercased() })
        if taken.contains(name.lowercased()) {
            var number = 1, candidate = name + " (copy)"
            while taken.contains(candidate.lowercased()), number < 100 { number += 1; candidate = name + " (copy \(number))" }
            name = candidate
        }
        var copy = Bot(id: id, name: name, purpose: String(bot.purpose.prefix(2000)), color: ["purple", "pink", "ochre", "white"].contains(bot.color) ? bot.color : "purple", symbol: "sparkles")
        copy.appearance = bot.appearance?.valid == true ? bot.appearance : nil
        copy.memory = Array((bot.memory ?? []).filter { !$0.isEmpty && $0.count <= 2000 }.prefix(100))
        copy.folder = bot.folder.map { String($0.prefix(80)) }
        copy.schedules = Array((bot.schedules ?? []).prefix(100).map { schedule -> BotSchedule in
            var paused = schedule; paused.enabled = false; paused.lastEvent = nil; paused.history = nil; paused.lastRun = nil; paused.lastResult = nil; paused.occurrence = UUID(); paused.id = UUID(); return paused
        }.filter { !$0.name.isEmpty && $0.name.count <= 200 && !$0.text.isEmpty && $0.text.count <= 8000 && ["none", "hourly", "daily", "weekly"].contains($0.recurrence) && TimeZone(identifier: $0.timezone) != nil })
        if let configuration = bot.aiConfiguration {
            var providers = configuration.providers.filter { installed.contains($0.provider) && $0.model.count <= 200 && !$0.model.contains(where: \.isNewline) }
            if providers.isEmpty, let fallback = defaultProvider ?? installed.first { providers = [BotAIProvider(provider: fallback, model: "")] }
            if !providers.isEmpty {
                var next = BotAIConfiguration(providers: providers, activeProvider: providers.contains { $0.provider == configuration.activeProvider } ? configuration.activeProvider : providers[0].provider, replyMode: configuration.replyMode)
                if next.replyMode != .compare || providers.count < 2 { next.replyMode = .one }
                copy.aiConfiguration = next
            }
        }
        let history = entries.suffix(Self.maxEntries).map { old -> Entry in
            var entry = Entry(botID: id, kind: old.kind, text: String(old.text.prefix(100_000)), date: old.date)
            entry.state = old.state == .streaming ? .complete : old.state
            entry.provider = old.provider.map { String($0.prefix(200)) }
            entry.senderName = old.senderName.map { String($0.prefix(100)) }
            entry.delivery = old.delivery == "scheduled" ? "scheduled" : nil
            return entry
        }
        var total = 0
        let files = knowledge.prefix(50).compactMap { file -> File? in
            let clean = (file.name as NSString).lastPathComponent
            guard !clean.isEmpty, !clean.hasPrefix("."), KnowledgeSearch.isSupported((clean as NSString).pathExtension.lowercased()), file.data.count <= KnowledgeSearch.maxFileBytes, total + file.data.count <= Self.maxKnowledgeBytes else { return nil }
            total += file.data.count; return File(name: clean, data: file.data)
        }
        return Clean(bot: copy, entries: Array(history), knowledge: files)
    }
}

extension MacAppModel {
    /// The Bot, its history and small Knowledge files, encoded for another computer.
    func packageForCopy(_ bot: Bot, app: AppModel) -> Data? {
        try? BotPackage.make(bot: bot, workspace: app.workspace, sourceName: Host.current().localizedName ?? "Mac", directory: workingDirectory(for: bot)).encoded()
    }

    /// Adds a Bot copied from another computer to `app` (the real workspace of this Mac). Returns a sentence describing what was copied.
    func importBotPackage(_ data: Data, into app: AppModel) throws -> String {
        let package = try BotPackage.decode(data)
        guard let clean = package.sanitized(existingNames: app.workspace.bots.map(\.name), installed: installedCLIs.map(\.provider), defaultProvider: selectedCLI?.provider) else {
            throw CloudError.message("That Bot cannot be copied (groups and unnamed Bots are not supported).")
        }
        let note = "Copied from \(package.sourceName). The AI here starts a fresh session, so it does not remember earlier chats word for word, but its memory and these messages came along."
        guard app.importBot(clean.bot, entries: clean.entries, note: note) else { throw CloudError.message("The Bot could not be saved on this computer.") }
        if !clean.knowledge.isEmpty {
            let folder = KnowledgeSearch.folder(for: workingDirectory(for: clean.bot))
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            for file in clean.knowledge { try? file.data.write(to: folder.appendingPathComponent(file.name), options: .atomic) }
        }
        return "Copied “\(clean.bot.name)” with \(clean.entries.count) messages, \(clean.bot.memory?.count ?? 0) memory items and \(clean.knowledge.count) Knowledge files. Routines were copied paused."
    }
}
