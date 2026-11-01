import Foundation

struct RemotePairing: Codable, Equatable, Sendable {
    let baseURL: URL
    let token: String

    init(address: String, token: String) throws {
        guard var parts = URLComponents(string: address.trimmingCharacters(in: .whitespacesAndNewlines)),
              let host = parts.host, !host.isEmpty, parts.user == nil, parts.password == nil,
              parts.query == nil, parts.fragment == nil, parts.path.isEmpty || parts.path == "/",
              parts.port == nil || (1...65535).contains(parts.port!),
              parts.scheme == "https" || (parts.scheme == "http" && Self.isLocalHost(host)),
              token.range(of: "^[A-Za-z0-9_-]{43,128}$", options: .regularExpression) != nil else { throw RemoteError.invalidPairing }
        parts.path = ""
        guard let url = parts.url else { throw RemoteError.invalidPairing }
        self.baseURL = url; self.token = token
    }

    init(link: String) throws {
        guard let parts = URLComponents(string: link), parts.scheme == "opengrokbot", parts.host == "pair",
              let address = parts.queryItems?.first(where: { $0.name == "host" })?.value, let token = parts.fragment else { throw RemoteError.invalidPairing }
        try self.init(address: address, token: token)
    }
    var link: URL {
        var parts = URLComponents(); parts.scheme = "opengrokbot"; parts.host = "pair"
        parts.queryItems = [URLQueryItem(name: "host", value: baseURL.absoluteString)]; parts.fragment = token
        return parts.url!
    }
    static func isLocalHost(_ address: String) -> Bool {
        let host = address.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        if host == "localhost" || host.hasSuffix(".local") || host == "::1" || host.hasPrefix("fc") && host.contains(":") || host.hasPrefix("fd") && host.contains(":") || host.hasPrefix("fe80:") { return true }
        let parts = host.split(separator: ".", omittingEmptySubsequences: false)
        let numbers = parts.compactMap { Int($0) }
        guard parts.count == 4, numbers.count == 4, numbers.allSatisfy({ (0...255).contains($0) }) else { return false }
        return numbers[0] == 10 || numbers[0] == 127 || numbers[0] == 192 && numbers[1] == 168 || numbers[0] == 172 && (16...31).contains(numbers[1]) || numbers[0] == 169 && numbers[1] == 254 || numbers[0] == 100 && (64...127).contains(numbers[1])
    }
}

enum RemoteError: Error, LocalizedError, Sendable {
    case invalidPairing, unauthorized, incompatible, unavailable, rejected(String)
    var errorDescription: String? {
        switch self {
        case .invalidPairing: "Paste a desktop pairing link, or use HTTPS and its pairing key. Plain HTTP works only with a private Wi-Fi or Tailscale address."
        case .unauthorized: "This pairing key was revoked or is incorrect. Pair again from the desktop app."
        case .incompatible: "Update the desktop and iPhone apps to compatible versions."
        case .unavailable: "The desktop is unreachable. Check that it is awake, remote access is on, and Wi-Fi or Tailscale is connected."
        case .rejected(let message): message
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
}
struct RemoteFile: Codable, Sendable, Identifiable { var name: String; var id: String { name } }

struct HostHTTPRequest: Sendable {
    let method: String
    let target: String
    let headers: [String:String]
    let body: Data

    static func parse(_ buffer: Data) throws -> HostHTTPRequest? {
        guard let separator = buffer.range(of: Data([13,10,13,10])) else { if buffer.count > 8192 { throw RemoteError.rejected("Request headers too large") }; return nil }
        guard separator.lowerBound <= 8192, let header = String(data: buffer[..<separator.lowerBound], encoding: .utf8) else { throw RemoteError.rejected("Invalid request") }
        let lines = header.components(separatedBy: "\r\n"), first = lines[0].split(separator: " ")
        guard first.count == 3, first[2] == "HTTP/1.1" || first[2] == "HTTP/1.0", first[1].hasPrefix("/"), first[1].count <= 2048 else { throw RemoteError.rejected("Invalid request") }
        var headers: [String:String] = [:]
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":") else { throw RemoteError.rejected("Invalid header") }
            let key = line[..<colon].lowercased(), value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            guard headers[key] == nil else { throw RemoteError.rejected("Duplicate header") }; headers[key] = value
        }
        guard headers["transfer-encoding"] == nil, headers["origin"] == nil,
              let length = Int(headers["content-length"] ?? "0"), (0...131072).contains(length) else { throw RemoteError.rejected("Invalid request body") }
        let total = separator.upperBound + length
        guard buffer.count >= total else { return nil }
        guard buffer.count == total else { throw RemoteError.rejected("Pipelined requests are not supported") }
        return HostHTTPRequest(method: String(first[0]), target: String(first[1]), headers: headers, body: Data(buffer[separator.upperBound..<total]))
    }
    func authorized(token: String) -> Bool {
        let expected = Array(("Bearer " + token).utf8), actual = Array((headers["authorization"] ?? "").utf8)
        guard expected.count == actual.count else { return false }
        return zip(expected, actual).reduce(UInt8(0)) { $0 | ($1.0 ^ $1.1) } == 0
    }
}
struct HostHTTPResponse: Sendable {
    var status: Int = 200
    var body: Data = Data()
    var contentType: String = "application/json"
    var wireData: Data {
        let text = "HTTP/1.1 \(status) \(status == 200 ? "OK" : status == 204 ? "No Content" : "Error")\r\nContent-Type: \(contentType)\r\nContent-Length: \(body.count)\r\nConnection: close\r\nCache-Control: no-store\r\nX-Content-Type-Options: nosniff\r\n\r\n"
        return Data(text.utf8) + body
    }
    static func json<T: Encodable>(_ value: T, status: Int = 200) throws -> HostHTTPResponse {
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        return HostHTTPResponse(status: status, body: try encoder.encode(value))
    }
    static func error(_ status: Int, _ message: String) -> HostHTTPResponse {
        (try? .json(["error":message], status: status)) ?? HostHTTPResponse(status: 500)
    }
}
