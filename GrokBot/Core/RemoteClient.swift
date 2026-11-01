import Foundation

/// Shared with Mac contract tests. No cookies, redirects, or credentials cross hosts.
final class RemoteHTTPClient: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private var session: URLSession!
    override init() {
        super.init()
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 15; config.timeoutIntervalForResource = 25
        config.httpShouldSetCookies = false; config.urlCache = nil
        session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) { completionHandler(nil) }

    func fetch(_ pairing: RemotePairing, path: String, query: [URLQueryItem] = [], command: RemoteCommand? = nil) async throws -> Data? {
        var parts = URLComponents(url: pairing.baseURL, resolvingAgainstBaseURL: false)!
        parts.path = path; parts.queryItems = query.isEmpty ? nil : query
        var request = URLRequest(url: parts.url!)
        request.setValue("Bearer " + pairing.token, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let command {
            request.httpMethod = "POST"; request.httpBody = try JSONEncoder().encode(command)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw RemoteError.unavailable }
        if http.statusCode == 204 { return nil }
        if http.statusCode == 401 { throw RemoteError.unauthorized }
        guard data.count <= 32 * 1024 * 1024 else { throw RemoteError.rejected("This response is too large to open on the phone.") }
        guard (200...299).contains(http.statusCode) else {
            let message = (try? JSONDecoder().decode([String:String].self, from: data))?["error"]
            throw RemoteError.rejected(message ?? "The host could not complete this request.")
        }
        return data
    }
    func snapshot(_ pairing: RemotePairing, since: String?) async throws -> RemoteSnapshot? {
        guard let data = try await fetch(pairing, path: "/v1/state", query: since.map { [URLQueryItem(name:"since", value:$0)] } ?? []) else { return nil }
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let snapshot = try decoder.decode(RemoteSnapshot.self, from: data)
        guard snapshot.protocolVersion == 1 else { throw RemoteError.incompatible }
        return snapshot
    }
}
