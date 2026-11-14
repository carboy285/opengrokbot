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
    /// Tools for local models (0.9.7): one native tool, app_action, carries any operation the instructions describe. A
    /// call becomes the same opengrokbot-action block a CLI writes, so the app runs it exactly as it would for a CLI.
    static func appTool() -> [String: Any] {
        let text: [String: Any] = ["type": "string"]
        return ["type": "function", "function": [
            "name": "app_action",
            "description": "Ask OpenGrokBot to do something for the human: any operation listed in your instructions, such as searching the web, reading a page, adding a reminder, scheduling a task, making an image, finding or running a connected-app tool, or messaging another Bot. Put the operation name in \"action\" and its fields next to it, exactly as the instructions show. The result comes back in the next turn.",
            "parameters": [
                "type": "object",
                "properties": ["action": ["type": "string", "description": "The operation, for example search_web, apple_add_reminder, schedule_task, generate_image, composio_find or composio_run."],
                               "query": text, "url": text, "text": text, "prompt": text, "name": text, "at": text, "to": text, "tool": text, "arguments": ["type": "object"]],
                "required": ["action"],
                "additionalProperties": true
            ] as [String: Any]
        ] as [String: Any]]
    }

    /// Turns finished tool calls into action blocks. Calls that are not valid app actions are dropped.
    static func actionBlocks(_ calls: [(name: String, arguments: String)]) -> String {
        calls.compactMap { call -> String? in
            guard call.name.isEmpty || call.name == "app_action", let data = call.arguments.data(using: .utf8),
                  let value = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let action = value["action"] as? String, action.range(of: "^[a-z_]{2,40}$", options: .regularExpression) != nil,
                  let json = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]), json.count <= 16_000,
                  let text = String(data: json, encoding: .utf8) else { return nil }
            return "\n```opengrokbot-action\n" + text + "\n```"
        }.joined()
    }

    static func chat(provider: CLIProvider, base: String, prompt: String, model: String, tools: Bool = true, onText: @escaping @Sendable (String) -> Void) async throws -> String {
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
        func open(withTools: Bool) async throws -> (URLSession.AsyncBytes, Int) {
            var request = URLRequest(url: url)
            request.httpMethod = "POST"; request.timeoutInterval = 600
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            var body: [String: Any] = ["model": chosen, "stream": true, "messages": [["role": "user", "content": prompt]]]
            if withTools { body["tools"] = [appTool()] }
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            do {
                let (bytes, response) = try await URLSession.shared.bytes(for: request)
                return (bytes, (response as? HTTPURLResponse)?.statusCode ?? 0)
            }
            catch is CancellationError { throw CLIError.stopped }
            catch { if Task.isCancelled { throw CLIError.stopped }; throw Failure("\(name) isn’t running at \(origin). Open \(name) and start its server, then retry.") }
        }
        var (bytes, status) = try await open(withTools: tools)
        if tools, status == 400 {
            // Models without tool support reject the request; they still read the instructions and can write action blocks.
            var reason = ""
            for try await line in bytes.lines { reason += line; if reason.count > 2000 { break } }
            if reason.lowercased().contains("tool") { (bytes, status) = try await open(withTools: false) }
        }
        guard status == 200 else {
            if status == 404 { throw Failure("That model isn’t available in \(name). Choose another in the Bot’s side panel.") }
            throw Failure("\(name) stopped with an error (HTTP \(status)). Check the model is loaded and try again.")
        }
        var raw = ""
        var calls: [(name: String, arguments: String)] = []
        do {
            for try await line in bytes.lines {
                try Task.checkCancellation()
                guard line.hasPrefix("data:") else { continue }
                let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                guard payload != "[DONE]", let data = payload.data(using: .utf8),
                      let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let choice = (object["choices"] as? [[String: Any]])?.first else { continue }
                let delta = (choice["delta"] as? [String: Any]) ?? (choice["message"] as? [String: Any]) ?? [:]
                // Tool calls stream in pieces: a name first, then the arguments a few characters at a time.
                for item in delta["tool_calls"] as? [[String: Any]] ?? [] {
                    let index = item["index"] as? Int ?? calls.count
                    while calls.count <= index && calls.count < 8 { calls.append((name: "", arguments: "")) }
                    guard index < calls.count, let function = item["function"] as? [String: Any] else { continue }
                    if let part = function["name"] as? String { calls[index].name += part }
                    if let part = function["arguments"] as? String { calls[index].arguments += part }
                    else if let object = function["arguments"], let data = try? JSONSerialization.data(withJSONObject: object), let part = String(data: data, encoding: .utf8) { calls[index].arguments = part }
                }
                let piece = (delta["content"] as? String) ?? ""
                guard !piece.isEmpty else { continue }
                raw += piece
                guard raw.count <= 400_000 else { break }
                onText(visibleText(raw))
            }
        } catch is CancellationError { throw CLIError.stopped }
        catch { if Task.isCancelled { throw CLIError.stopped }; throw Failure("The connection to \(name) was lost. Retry.") }
        let blocks = actionBlocks(calls)
        let text = (visibleText(raw) + blocks).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw Failure("\(name) returned an empty reply. Try another model.") }
        if !blocks.isEmpty { onText(text) }
        return text
    }
}

// MARK: - Ollama model manager (0.9.5)

struct OllamaModel: Identifiable, Equatable, Sendable { let name: String; let bytes: Int64; let parameters: String; var id: String { name } }
struct OllamaSuggestion: Identifiable, Sendable { let name: String; let sizeGB: Double; let minMemoryGB: Double; let voice: Bool; let about: String; var id: String { name } }

extension LocalModelServer {
    /// Models worth downloading, smallest first. `voice` marks the quick ones that suit voice mode. Mirrors local-llm.cjs.
    static let ollamaRecommended: [OllamaSuggestion] = [
        OllamaSuggestion(name: "llama3.2:3b", sizeGB: 2.0, minMemoryGB: 8, voice: true, about: "Meta Llama 3.2 · quick, good for voice"),
        OllamaSuggestion(name: "qwen3:4b", sizeGB: 2.6, minMemoryGB: 8, voice: true, about: "Qwen 3 · quick and capable"),
        OllamaSuggestion(name: "gemma3:4b", sizeGB: 3.3, minMemoryGB: 8, voice: true, about: "Google Gemma 3 · quick, understands images"),
        OllamaSuggestion(name: "llama3.1:8b", sizeGB: 4.9, minMemoryGB: 16, voice: false, about: "Meta Llama 3.1 · stronger answers"),
        OllamaSuggestion(name: "qwen3:8b", sizeGB: 5.2, minMemoryGB: 16, voice: false, about: "Qwen 3 · stronger answers and tools"),
        OllamaSuggestion(name: "gemma3:12b", sizeGB: 8.1, minMemoryGB: 24, voice: false, about: "Google Gemma 3 · best quality here")
    ]
    static func validModelName(_ name: String) -> Bool { name.range(of: "^[A-Za-z0-9][A-Za-z0-9._:/-]{0,100}$", options: .regularExpression) != nil }
    static var ollamaBase: String { origin(UserDefaults.standard.dictionary(forKey: "localCLIPaths")?["ollama"] as? String ?? "") ?? CLIProvider.ollama.defaultServer }

    /// Installed models, or nil when Ollama is not running.
    static func ollamaModels() async -> [OllamaModel]? {
        guard let url = URL(string: ollamaBase + "/api/tags") else { return nil }
        var request = URLRequest(url: url); request.timeoutInterval = 3
        guard let (data, response) = try? await URLSession.shared.data(for: request), (response as? HTTPURLResponse)?.statusCode == 200,
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return ((object["models"] as? [[String: Any]]) ?? []).compactMap { item in
            guard let name = item["name"] as? String, validModelName(name) else { return nil }
            return OllamaModel(name: name, bytes: (item["size"] as? NSNumber)?.int64Value ?? 0, parameters: (item["details"] as? [String: Any])?["parameter_size"] as? String ?? "")
        }
    }

    /// Downloads a model; `progress(status, completed, total)` is called as it goes.
    static func ollamaPull(_ name: String, progress: @escaping @Sendable (String, Int64, Int64) -> Void) async throws {
        guard validModelName(name), let url = URL(string: ollamaBase + "/api/pull") else { throw Failure("Choose a valid model name, like llama3.2:3b.") }
        var request = URLRequest(url: url); request.httpMethod = "POST"; request.timeoutInterval = 3600
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["model": name, "stream": true])
        let connection: (URLSession.AsyncBytes, URLResponse)
        do { connection = try await URLSession.shared.bytes(for: request) } catch { throw Failure("Ollama isn’t running. Open Ollama, then try again.") }
        guard (connection.1 as? HTTPURLResponse)?.statusCode == 200 else { throw Failure("Ollama could not download \(name). Check the name on ollama.com/library.") }
        for try await line in connection.0.lines {
            guard let object = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any] else { continue }
            if let error = object["error"] as? String { throw Failure("Ollama: " + String(error.prefix(200))) }
            progress(object["status"] as? String ?? "", (object["completed"] as? NSNumber)?.int64Value ?? 0, (object["total"] as? NSNumber)?.int64Value ?? 0)
        }
    }

    static func ollamaDelete(_ name: String) async throws {
        guard validModelName(name), let url = URL(string: ollamaBase + "/api/delete") else { throw Failure("Invalid model name.") }
        var request = URLRequest(url: url); request.httpMethod = "DELETE"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["model": name])
        let (_, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw Failure("Ollama could not remove \(name).") }
    }

    /// The quickest installed model for voice: a recommended voice model if present, else the smallest.
    static func voicePick(_ models: [OllamaModel]) -> String {
        let quick = ollamaRecommended.filter(\.voice).map(\.name)
        return models.first { quick.contains($0.name) }?.name ?? models.min { $0.bytes < $1.bytes }?.name ?? ""
    }
}
