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
struct RemoteSnapshot: Codable, Sendable {
    var protocolVersion: Int = 1
    var hostName: String
    var revision: String
    var workspace: Workspace
    var running: [UUID]
    var providers: [RemoteProvider]
    var defaultProvider: CLIProvider?
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
    var appearance: BotAppearance?
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
