import Foundation

struct WebSearchHit: Equatable, Sendable {
    let title: String
    let url: String
    let snippet: String
}

/// Web search through Composio's own search toolkit, so a Bot never has to open a browser window to look something up.
/// The project key stays in this app; only the search text is sent, and only to Composio.
enum ComposioSearch {
    static let toolkit = "composio_search"
    /// Tried in order. The first that returns results wins; a tool Composio does not know is skipped.
    static let tools = ["COMPOSIO_SEARCH_DUCK_DUCK_GO_SEARCH", "COMPOSIO_SEARCH_WEB"]
    static let maxHits = 8

    private static func clip(_ value: Any?, _ length: Int) -> String {
        let text = (value as? String) ?? ""
        return String(text.split(whereSeparator: \.isWhitespace).joined(separator: " ").prefix(length))
    }
    private static func first(_ object: [String: Any], _ names: [String]) -> String {
        for name in names { if let text = object[name] as? String, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return text } }
        return ""
    }
    static func webURL(_ value: String) -> String? {
        guard value.count <= 2000, let url = URL(string: value), let scheme = url.scheme, ["https", "http"].contains(scheme), url.host != nil, url.user == nil, url.password == nil else { return nil }
        return url.absoluteString
    }

    /// Finds result-like objects (a link plus a title) anywhere in a response, whatever shape the tool used.
    static func hits(in value: Any) -> [WebSearchHit] {
        var found: [WebSearchHit] = [], seen = Set<String>()
        func visit(_ node: Any, _ depth: Int) {
            guard found.count < maxHits, depth <= 8 else { return }
            if let list = node as? [Any] { for item in list { visit(item, depth + 1) }; return }
            guard let object = node as? [String: Any] else { return }
            if let link = webURL(first(object, ["url", "link", "href"])), !first(object, ["title", "name", "heading"]).isEmpty, !seen.contains(link) {
                seen.insert(link)
                found.append(WebSearchHit(title: clip(first(object, ["title", "name", "heading"]), 140), url: link,
                                          snippet: clip(first(object, ["snippet", "description", "content", "text", "body", "summary", "excerpt"]), 240)))
                return
            }
            for key in object.keys.sorted() { if let child = object[key] { visit(child, depth + 1) } }
        }
        visit(value, 0)
        return Array(found.prefix(maxHits))
    }

    enum Failure: Error, Equatable { case rejected, rateLimited, unreachable, unsupported(String) }
    static func message(_ failure: Failure) -> String {
        switch failure {
        case .rejected: "Composio rejected this project key."
        case .rateLimited: "Composio’s rate limit was reached."
        case .unreachable: "Composio could not be reached."
        case .unsupported(let detail): detail.isEmpty ? "Composio search did not succeed." : detail
        }
    }

    /// The outcome of one tool call: results (possibly none), or the reason it could not be used.
    enum Outcome: Equatable { case hits([WebSearchHit]), skip(Failure), stop(Failure) }
    static func outcome(status: Int, data: Data) -> Outcome {
        if status == 401 || status == 403 { return .stop(.rejected) }
        if status == 429 { return .stop(.rateLimited) }
        guard (200..<300).contains(status) else { return .skip(.unsupported("Composio search failed (HTTP \(status)).")) }
        guard data.count < 4_000_000, let body = try? JSONSerialization.jsonObject(with: data) else { return .skip(.unsupported("Composio returned an unsupported response.")) }
        if let object = body as? [String: Any], (object["successful"] as? Bool) == false {
            return .skip(.unsupported(clip(object["error"], 160)))
        }
        let payload = (body as? [String: Any])?["data"] ?? body
        return .hits(hits(in: payload))
    }

    /// Runs the search tools in order. Returns hits (empty means it ran and found nothing) or throws why it could not run.
    static func search(query: String, userID: String, run: (_ tool: String, _ body: Data) async throws -> (Int, Data)) async throws -> [WebSearchHit] {
        let body = try JSONSerialization.data(withJSONObject: ["user_id": userID, "arguments": ["query": query], "version": "latest"] as [String: Any])
        var last = Failure.unreachable, ran = false
        for tool in tools {
            let status: Int, data: Data
            do { (status, data) = try await run(tool, body) } catch { last = .unreachable; continue }
            switch outcome(status: status, data: data) {
            case .hits(let hits): ran = true; if !hits.isEmpty { return hits }
            case .skip(let failure): last = failure
            case .stop(let failure): throw failure
            }
        }
        if ran { return [] }
        throw last
    }
}

extension ComposioClient {
    /// POST /api/v3/tools/execute/{tool}. The tool name comes only from `ComposioSearch.tools`.
    func webSearch(_ query: String, userID: String) async throws -> [WebSearchHit] {
        try await ComposioSearch.search(query: query, userID: userID) { tool, body in
            guard ComposioSearch.tools.contains(tool), let url = URL(string: "https://backend.composio.dev/api/v3/tools/execute/" + tool) else { throw ComposioError.invalidResponse }
            var request = URLRequest(url: url, timeoutInterval: 30)
            request.httpMethod = "POST"; request.httpBody = body
            request.setValue(key, forHTTPHeaderField: "x-api-key")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            let (data, response) = try await transport.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw ComposioError.invalidResponse }
            return (http.statusCode, data)
        }
    }
}
