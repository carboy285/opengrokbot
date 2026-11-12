import Foundation

/// Self-hosted models (0.9.3): Ollama and LM Studio serve an OpenAI-compatible API on this Mac (or your local network).
/// A Bot that uses one gets the same prompt a CLI would, streamed back over HTTP. Only loopback and private
/// addresses are accepted, so a Bot's chat never goes to an arbitrary host.
enum LocalModelServer {
    struct Failure: LocalizedError {
        let errorDescription: String?
        init(_ message: String) { errorDescription = message }
    }

    /// The server's origin when the address is on this computer or a private network.
    static func origin(_ value: String) -> String? {
        guard let url = URL(string: value.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
              url.user == nil, url.password == nil, let host = url.host?.lowercased() else { return nil }
        let parts = host.split(separator: ".").compactMap { Int($0) }
        let privateIP: Bool = parts.count == 4 && (parts[0] == 127 || parts[0] == 10 || (parts[0] == 192 && parts[1] == 168) || (parts[0] == 172 && (16...31).contains(parts[1])) || (parts[0] == 100 && (64...127).contains(parts[1])))
        guard host == "localhost" || host == "::1" || host.hasSuffix(".local") || privateIP else { return nil }
        return scheme + "://" + (host.contains(":") ? "[\(host)]" : host) + (url.port.map { ":\($0)" } ?? "")
    }

    /// Removes the private reasoning some local models print before their answer.
    static func visibleText(_ raw: String) -> String {
        var text = raw
        while let start = text.range(of: "<think>") {
            if let end = text.range(of: "</think>", range: start.upperBound..<text.endIndex) { text.removeSubrange(start.lowerBound..<end.upperBound) }
            else { text.removeSubrange(start.lowerBound..<text.endIndex) }
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private final class Box: @unchecked Sendable { var models: [String]? }

    /// Model IDs the server offers, or nil when nothing answers. Blocking: call it off the main thread.
    static func modelsBlocking(_ base: String, timeout: TimeInterval = 1.5) -> [String]? {
        guard let origin = origin(base), let url = URL(string: origin + "/v1/models") else { return nil }
        var request = URLRequest(url: url); request.timeoutInterval = timeout
        let box = Box(), done = DispatchSemaphore(value: 0)
        URLSession.shared.dataTask(with: request) { data, response, _ in
            defer { done.signal() }
            guard (response as? HTTPURLResponse)?.statusCode == 200, let data,
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
            box.models = ((object["data"] as? [[String: Any]]) ?? []).compactMap { $0["id"] as? String }.filter { $0.count <= 200 }
        }.resume()
        _ = done.wait(timeout: .now() + timeout + 0.5)
        return box.models
    }

    static func models(_ base: String) async -> [String]? {
        await Task.detached { modelsBlocking(base, timeout: 4) }.value
    }

    /// Streams a reply. `onText` gets the visible text so far.
    static func chat(provider: CLIProvider, base: String, prompt: String, model: String, onText: @escaping @Sendable (String) -> Void) async throws -> String {
        let name = provider.name
        guard let origin = origin(base), let url = URL(string: origin + "/v1/chat/completions") else {
            throw Failure("The \(name) address must be on this Mac or your local network.")
        }
        var chosen = model
        if chosen.isEmpty {
            guard let available = await models(origin) else { throw Failure("\(name) isn’t running at \(origin). Open \(name) and start its server, then retry.") }
            guard let first = available.first else { throw Failure("\(name) has no models yet. \(provider == .ollama ? "Run ollama pull llama3.2 in Terminal" : "Load a model in LM Studio"), then retry.") }
            chosen = first
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"; request.timeoutInterval = 600
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["model": chosen, "stream": true, "messages": [["role": "user", "content": prompt]]])
        let connection: (URLSession.AsyncBytes, URLResponse)
        do { connection = try await URLSession.shared.bytes(for: request) }
        catch is CancellationError { throw CLIError.stopped }
        catch { if Task.isCancelled { throw CLIError.stopped }; throw Failure("\(name) isn’t running at \(origin). Open \(name) and start its server, then retry.") }
        let (bytes, response) = connection
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            if status == 404 { throw Failure("That model isn’t available in \(name). Choose another in the Bot’s side panel.") }
            throw Failure("\(name) stopped with an error (HTTP \(status)). Check the model is loaded and try again.")
        }
        var raw = ""
        do {
            for try await line in bytes.lines {
                try Task.checkCancellation()
                guard line.hasPrefix("data:") else { continue }
                let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                guard payload != "[DONE]", let data = payload.data(using: .utf8),
                      let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let choice = (object["choices"] as? [[String: Any]])?.first else { continue }
                let piece = ((choice["delta"] as? [String: Any])?["content"] as? String) ?? ((choice["message"] as? [String: Any])?["content"] as? String) ?? ""
                guard !piece.isEmpty else { continue }
                raw += piece
                guard raw.count <= 400_000 else { break }
                onText(visibleText(raw))
            }
        } catch is CancellationError { throw CLIError.stopped }
        catch { if Task.isCancelled { throw CLIError.stopped }; throw Failure("The connection to \(name) was lost. Retry.") }
        let text = visibleText(raw)
        guard !text.isEmpty else { throw Failure("\(name) returned an empty reply. Try another model.") }
        return text
    }
}
