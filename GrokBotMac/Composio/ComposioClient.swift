import Foundation

struct ComposioSession: Codable, Sendable {
    struct MCP: Codable, Sendable { let url: String }
    let session_id: String
    let mcp: MCP
}
struct ComposioToolkit: Decodable, Identifiable, Sendable {
    struct Account: Decodable, Sendable { let status: String }
    let slug: String
    let name: String
    let enabled: Bool
    let is_no_auth: Bool
    let connected_account: Account?
    var id: String { slug }
    var connected: Bool { connected_account?.status.uppercased() == "ACTIVE" }
}
enum ComposioError: LocalizedError {
    case status(Int), invalidResponse, storage, missing
    var errorDescription: String? {
        switch self {
        case .status(401), .status(403): "Composio rejected this key. Check the project key and its session permissions."
        case .status(429): "Composio’s rate limit was reached. Wait a moment and refresh."
        case .status(let code): "Composio could not complete the request (HTTP \(code)). Try again or check your project."
        case .invalidResponse: "Composio returned an unsupported response. No connection was opened."
        case .storage: "Unlock your Mac so the Composio credentials can be stored in Keychain."
        case .missing: "Set up your Composio project first."
        }
    }
}

/// v3.1 Tool Router API. Project credentials are sent only to the fixed API origin.
struct ComposioClient: Sendable {
    let key: String
    var transport: URLSession = URLSession(configuration: .ephemeral, delegate: ComposioNoRedirect(), delegateQueue: nil)
    static func trustedURL(_ value: String) -> URL? {
        guard let url = URL(string: value), url.scheme == "https", let host = url.host?.lowercased(),
              (host == "composio.dev" || host.hasSuffix(".composio.dev")), url.user == nil, url.password == nil,
              url.port == nil || url.port == 443 else { return nil }
        return url
    }
    func request<T: Decodable & Sendable>(_ path: String, method: String = "GET", body: Data? = nil) async throws -> T {
        var request = URLRequest(url: URL(string: "https://backend.composio.dev/api/v3.1/tool_router/session" + path)!)
        request.httpMethod = method; request.httpBody = body; request.timeoutInterval = 30
        request.setValue(key, forHTTPHeaderField: "x-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // An ephemeral session prevents persistent credential-bearing request caches.
        let (data, response) = try await transport.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw ComposioError.invalidResponse }
        guard (200..<300).contains(response.statusCode) else { throw ComposioError.status(response.statusCode) }
        guard data.count < 4_000_000, let value = try? JSONDecoder().decode(T.self, from: data) else { throw ComposioError.invalidResponse }
        return value
    }
    func create(userID: String, toolkits: [String]) async throws -> ComposioSession {
        let body = try JSONSerialization.data(withJSONObject: ["user_id":userID, "toolkits":["enable":toolkits], "manage_connections":["enable":false]])
        let session: ComposioSession = try await request("", method: "POST", body: body)
        guard Self.trustedURL(session.mcp.url) != nil, Self.validID(session.session_id) else { throw ComposioError.invalidResponse }
        return session
    }
    func toolkits(sessionID: String) async throws -> [ComposioToolkit] {
        struct Page: Decodable, Sendable { let items: [ComposioToolkit]; let next_cursor: String? }
        guard Self.validID(sessionID) else { throw ComposioError.invalidResponse }
        var items: [ComposioToolkit] = [], cursor: String?
        for _ in 0..<50 {
            var path = "/\(sessionID)/toolkits?limit=50"
            if let cursor { path += "&cursor=" + (cursor.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? "") }
            let page: Page = try await request(path)
            items += page.items
            guard let next = page.next_cursor, !next.isEmpty, next != cursor else { return items }
            cursor = next
        }
        throw ComposioError.invalidResponse
    }
    func link(sessionID: String, toolkit: String) async throws -> URL {
        struct Link: Decodable, Sendable { let redirect_url: String }
        guard Self.validID(sessionID), Self.validID(toolkit) else { throw ComposioError.invalidResponse }
        let data = try JSONSerialization.data(withJSONObject: ["toolkit":toolkit])
        let value: Link = try await request("/\(sessionID)/link", method: "POST", body: data)
        guard let url = Self.trustedURL(value.redirect_url) else { throw ComposioError.invalidResponse }
        return url
    }
    static func validID(_ text: String) -> Bool { !text.isEmpty && text.count < 300 && text.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_" || $0 == "-") } }
}

final class ComposioNoRedirect: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) { completionHandler(nil) }
}
