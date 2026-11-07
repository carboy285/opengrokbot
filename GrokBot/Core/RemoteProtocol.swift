import Foundation

enum RemoteError: Error, LocalizedError, Sendable {
    case incompatible, unauthorized, unavailable
    var errorDescription: String? {
        switch self {
        case .incompatible: "Update the Mac and iPhone apps to compatible versions."
        case .unauthorized: "Sign in again and approve this phone on your computer."
        case .unavailable: "Keep the Mac awake with OpenGrokBot running and phone access enabled."
        }
    }
}

struct RemoteProvider: Codable, Equatable, Sendable, Identifiable {
    var provider: CLIProvider
    var version: String
    var id: String { provider.rawValue }
}
/// A Bot request waiting for a yes or no on the Mac that the approved phone can answer too.
struct RemoteApproval: Codable, Sendable, Equatable, Identifiable {
    var id: UUID
    var title: String
    var detail: String
}
struct RemoteSnapshot: Codable, Sendable {
    var protocolVersion: Int = 1
    var hostName: String
    var revision: String
    var workspace: Workspace
    var running: [UUID]
    var providers: [RemoteProvider]
    var defaultProvider: CLIProvider?
    var overview: Bool? = nil
    var approval: RemoteApproval? = nil

    func botOverview() -> RemoteSnapshot {
        var result = self
        result.overview = true; result.revision = "overview-" + revision
        var latest: [UUID:Entry] = [:]
        for entry in workspace.entries { latest[entry.botID] = entry }
        result.workspace.entries = workspace.bots.compactMap { bot in
            guard var entry = latest[bot.id] else { return nil }; entry.text = String(entry.text.prefix(1000)); return entry
        }
        result.workspace.sharedMemory = nil; result.workspace.teamMessages = nil
        for index in result.workspace.bots.indices { result.workspace.bots[index].memory = nil; result.workspace.bots[index].schedules = nil }
        return result
    }
}
struct RemoteCommand: Codable, Sendable {
    var requestID: UUID = UUID()
    var action: String
    var botID: UUID?
    var text: String?
    var name: String?
    var purpose: String?
    var color: String?
    var configuration: BotAIConfiguration?
    var taskID: UUID?
    var appearance: BotAppearance?
    var attachments: [RemoteAttachment]?
}
/// An image sent with a message. Hosts store it in the Bot's Attachments folder.
struct RemoteAttachment: Codable, Sendable, Equatable {
    static let maxCount = 3
    static let maxTotalBytes = 2_400_000
    var name: String
    var mime: String
    var data: Data
}
struct RemoteFile: Codable, Sendable, Identifiable { var name: String; var id: String { name } }

/// Application RPC DTOs carried inside encrypted relay packets; no HTTP listener.
struct RemoteHostRequest: Sendable {
    let method: String
    let target: String
    let body: Data
}
struct RemoteHostResponse: Sendable {
    var status: Int = 200
    var body: Data = Data()
    static func json<T: Encodable>(_ value: T, status: Int = 200) throws -> RemoteHostResponse {
        RemoteHostResponse(status:status,body:try CloudCoding.encoder().encode(value))
    }
    static func error(_ status: Int, _ message: String) -> RemoteHostResponse {
        (try? .json(["error":message],status:status)) ?? RemoteHostResponse(status:500)
    }
}


struct RemoteBrowserPreview: Codable, Sendable {
    var title: String
    var url: String
    var imageData: Data?
}
