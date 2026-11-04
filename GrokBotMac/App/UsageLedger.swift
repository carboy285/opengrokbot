import Foundation

/// One finished Bot reply, for the Usage screen. Sizes are text lengths, so token counts are estimates, not billing data.
struct UsageRecord: Codable, Identifiable, Equatable, Sendable {
    var id = UUID()
    var date: Date
    var botID: UUID
    var botName: String
    var provider: String
    var model: String
    var apiKey: Bool
    var inputChars: Int
    var outputChars: Int
}

struct UsageRow: Identifiable, Equatable {
    let id: String
    let messages: Int
    let tokensIn: Int
    let tokensOut: Int
    let apiMessages: Int
}

@MainActor
final class UsageLedger: ObservableObject {
    static let shared = UsageLedger()
    @Published private(set) var records: [UsageRecord] = []
    private let file: URL

    init(file: URL? = nil) {
        self.file = file ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/OpenGrokBot/usage.json")
        if let data = try? Data(contentsOf: self.file), let loaded = try? JSONDecoder().decode([UsageRecord].self, from: data) { records = loaded }
    }

    func record(botID: UUID, botName: String, provider: String, model: String, apiKey: Bool, inputChars: Int, outputChars: Int) {
        records.append(UsageRecord(date: Date(), botID: botID, botName: botName, provider: provider, model: model, apiKey: apiKey, inputChars: inputChars, outputChars: outputChars))
        if records.count > 5000 { records.removeFirst(records.count - 5000) }
        save()
    }

    func clear() { records = []; save() }

    private func save() {
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(records) { try? data.write(to: file, options: .atomic) }
    }

    nonisolated static func tokens(fromCharacters count: Int) -> Int { (count + 3) / 4 }

    /// Groups records since a date by a key (provider name, Bot name…), busiest first.
    nonisolated static func summarize(_ records: [UsageRecord], since: Date, key: (UsageRecord) -> String) -> [UsageRow] {
        var groups: [String: [UsageRecord]] = [:]
        for record in records where record.date >= since { groups[key(record), default: []].append(record) }
        return groups.map { name, items in
            UsageRow(id: name, messages: items.count, tokensIn: tokens(fromCharacters: items.reduce(0) { $0 + $1.inputChars }), tokensOut: tokens(fromCharacters: items.reduce(0) { $0 + $1.outputChars }), apiMessages: items.filter(\.apiKey).count)
        }.sorted { $0.messages != $1.messages ? $0.messages > $1.messages : $0.id < $1.id }
    }
}
