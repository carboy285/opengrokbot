import Foundation

// A stdio MCP transport for the user-scoped Composio session. Never receives the project API key.
// stdout is exclusively JSON-RPC. Diagnostics deliberately omit request bodies and capability URLs.
final class NoRedirect: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) { completionHandler(nil) }
}
actor Bridge {
    let endpoint: URL
    let transport = URLSession(configuration: .ephemeral, delegate: NoRedirect(), delegateQueue: nil)
    var sessionID: String?
    var protocolVersion: String?
    init(endpoint: URL) { self.endpoint = endpoint }
    func handle(_ line: String) async {
        guard line.utf8.count < 4_000_000, let data = line.data(using: .utf8), let value = try? JSONSerialization.jsonObject(with: data) as? [String:Any] else { return }
        let id = value["id"]
        do {
            var request = URLRequest(url: endpoint)
            request.httpMethod = "POST"; request.httpBody = data; request.timeoutInterval = 180
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("application/json, text/event-stream", forHTTPHeaderField: "Accept")
            if let sessionID { request.setValue(sessionID, forHTTPHeaderField: "Mcp-Session-Id") }
            if let protocolVersion { request.setValue(protocolVersion, forHTTPHeaderField: "MCP-Protocol-Version") }
            let (bytes, response) = try await transport.bytes(for: request)
            guard let response = response as? HTTPURLResponse, (200..<300).contains(response.statusCode) else { throw BridgeError.request }
            if let header = response.value(forHTTPHeaderField: "Mcp-Session-Id") { sessionID = header }
            if response.statusCode == 202 || id == nil { return }
            if response.value(forHTTPHeaderField: "Content-Type")?.contains("text/event-stream") == true {
                var event = "", size = 0
                for try await part in bytes.lines {
                    size += part.utf8.count
                    guard size < 16_000_000 else { throw BridgeError.request }
                    if part.isEmpty {
                        if !event.isEmpty, emit(event, matching: id) { return }
                        event = ""
                    } else if part.hasPrefix("data:") {
                        if !event.isEmpty { event += "\n" }
                        event += part.dropFirst(5).trimmingCharacters(in: .whitespaces)
                    }
                }
                if !event.isEmpty, emit(event, matching: id) { return }
                throw BridgeError.request
            } else {
                var output = Data()
                for try await byte in bytes { output.append(byte); guard output.count < 16_000_000 else { throw BridgeError.request } }
                guard emit(String(decoding: output, as: UTF8.self), matching: id) else { throw BridgeError.request }
            }
        } catch {
            guard let id else { return }
            let response: [String:Any] = ["jsonrpc":"2.0", "id":id, "error":["code":-32000, "message":"Composio tool request failed. Refresh connections in OpenGrokBot and try again."]]
            if let data = try? JSONSerialization.data(withJSONObject: response) { output(data) }
        }
    }
    private func emit(_ text: String, matching id: Any?) -> Bool {
        guard let data = text.data(using: .utf8), let value = try? JSONSerialization.jsonObject(with: data) as? [String:Any], value["jsonrpc"] as? String == "2.0" else { return false }
        // The proxy handles client-to-server methods. Never surface server request IDs as client responses.
        guard value["method"] == nil, let actual = value["id"], let id,
              String(describing: actual) == String(describing: id) else { return false }
        if let result = value["result"] as? [String:Any], let version = result["protocolVersion"] as? String { protocolVersion = version }
        output(data); return true
    }
    private func output(_ data: Data) { try? FileHandle.standardOutput.write(contentsOf: data + Data([10])) }
    enum BridgeError: Error { case request }
}
let raw = ProcessInfo.processInfo.environment["OPENGROKBOT_COMPOSIO_MCP_URL"] ?? ""
guard let endpoint = URL(string: raw), endpoint.scheme == "https", let host = endpoint.host?.lowercased(),
      (host == "composio.dev" || host.hasSuffix(".composio.dev")), endpoint.user == nil, endpoint.password == nil,
      endpoint.port == nil || endpoint.port == 443 else { exit(1) }
let bridge = Bridge(endpoint: endpoint)
// Read on a worker so URLSession and the actor remain schedulable while stdin waits.
await withTaskGroup(of: Void.self) { group in
    await Task.detached {
        while let line = readLine(strippingNewline: true) {
            await bridge.handle(line)
        }
    }.value
}
