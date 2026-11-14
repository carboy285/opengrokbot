import Darwin
import Foundation

/// Each request owns one subprocess. Prompts use stdin or a private file, never a shell.
final class LocalCLIRun: @unchecked Sendable {
    private let keys: KeychainSecretStore
    init(keys: KeychainSecretStore = ProviderAPIKeys.defaultStore) { self.keys = keys }
    private let lock = NSLock()
    private let process = Process()
    private var cancelled = false
    private var timedOut = false
    /// Ollama and LM Studio replies run as an HTTP task instead of a process.
    private var serverTask: Task<Void, Never>?

    func cancel(timeout: Bool = false, immediately: Bool = false) {
        lock.lock()
        cancelled = true
        timedOut = timedOut || timeout
        let running = process.isRunning
        let server = serverTask
        lock.unlock()
        server?.cancel()
        if running {
            if immediately { Darwin.kill(process.processIdentifier, SIGKILL); return }
            process.interrupt()
            DispatchQueue.global().asyncAfter(deadline: .now() + 2) { [self] in
                if process.isRunning { process.terminate() }
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + 5) { [self] in
                if process.isRunning { Darwin.kill(process.processIdentifier, SIGKILL) }
            }
        }
    }

    static func stream(cli: InstalledCLI, prompt: String, session: String?, directory: URL, mcpURL: String? = nil, model: String = "", keys: KeychainSecretStore = ProviderAPIKeys.defaultStore) -> AsyncThrowingStream<CLIEvent, Error> {
        LocalCLIRun(keys: keys).events(cli: cli, prompt: prompt, session: session, directory: directory, mcpURL: mcpURL, model: model)
    }

    func events(cli: InstalledCLI, prompt: String, session: String?, directory: URL, mcpURL: String? = nil, model: String = "", fast: Bool = false) -> AsyncThrowingStream<CLIEvent, Error> {
        let run = self
        if cli.provider.isLocalServer {
            return AsyncThrowingStream { continuation in
                let task = Task<Void, Never> {
                    do {
                        let text = try await LocalModelServer.chat(provider: cli.provider, base: cli.path, prompt: prompt, model: model) { partial in continuation.yield(.text(partial)) }
                        continuation.yield(.text(text)); continuation.finish()
                    } catch { continuation.finish(throwing: error) }
                }
                run.lock.lock(); run.serverTask = task; run.lock.unlock()
                continuation.onTermination = { @Sendable _ in task.cancel() }
            }
        }
        return AsyncThrowingStream { continuation in
            continuation.onTermination = { @Sendable _ in run.cancel() }
            DispatchQueue.global(qos: .userInitiated).async {
                run.execute(cli: cli, prompt: prompt, session: session, directory: directory, mcpURL: mcpURL, model: model, fast: fast, continuation: continuation)
            }
        }
    }

    /// FileHandle.read(upToCount:) can fill its requested buffer before returning on Darwin.
    /// One POSIX read delivers each available pipe chunk, so partial replies and stop remain responsive.
    private func readChunk(_ handle: FileHandle) throws -> Data? {
        var buffer = [UInt8](repeating: 0, count: 16_384)
        while true {
            let count = buffer.withUnsafeMutableBytes { Darwin.read(handle.fileDescriptor, $0.baseAddress, $0.count) }
            if count > 0 { return Data(buffer.prefix(count)) }
            if count == 0 { return nil }
            if errno != EINTR { throw CLIError.invalidOutput }
        }
    }

    private func execute(cli: InstalledCLI, prompt: String, session: String?, directory: URL, mcpURL: String?, model: String, fast: Bool = false, continuation: AsyncThrowingStream<CLIEvent, Error>.Continuation) {
        var promptFile: URL?
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            if cli.provider == .grok {
                let file = directory.appendingPathComponent(".prompt-\(UUID().uuidString).txt")
                try Data(prompt.utf8).write(to: file, options: .atomic)
                try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
                promptFile = file
            }
            defer { if let promptFile { try? FileManager.default.removeItem(at: promptFile) } }
            let mcp = try ComposioCLIConfiguration.make(provider: cli.provider, directory: directory, sessionURL: mcpURL)
            defer { mcp.cleanup() }
            let command = CLICommand.chat(provider: cli.provider, prompt: prompt, session: session, promptFile: promptFile?.path, model: model, allowConnectedApps: mcpURL != nil && UserDefaults.standard.bool(forKey: "claudeAllowConnectedApps"), fast: fast)
            let input = Pipe(), output = Pipe(), error = Pipe()
            process.executableURL = URL(fileURLWithPath: cli.path)
            process.arguments = command.arguments + mcp.arguments
            process.currentDirectoryURL = directory
            // An API key the user saved for this provider goes to the CLI only through its environment: never argv, files, or logs.
            process.environment = CLIInstallationScanner.environment.merging(mcp.environment) { _, new in new }
                .merging(ProviderAPIKeys.environment(for: cli.provider, store: keys)) { _, new in new }
            process.standardInput = input; process.standardOutput = output; process.standardError = error
            // A child exiting before consuming stdin must not terminate the GUI with SIGPIPE.
            _ = fcntl(input.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1)
            lock.lock()
            if cancelled { lock.unlock(); continuation.finish(throwing: CLIError.stopped); return }
            if !FileManager.default.isExecutableFile(atPath: cli.path) { lock.unlock(); throw CLIError.notInstalled }
            do { try process.run(); lock.unlock() } catch { lock.unlock(); throw error }
            let timeout = DispatchWorkItem { [weak self] in self?.cancel(timeout: true) }
            DispatchQueue.global().asyncAfter(deadline: .now() + 600, execute: timeout)
            defer { timeout.cancel() }
            let stderr = BoundedData(limit: 32_768)
            let readers = DispatchGroup()
            readers.enter()
            DispatchQueue.global().async {
                defer { readers.leave() }
                while let bytes = try? error.fileHandleForReading.read(upToCount: 8192), !bytes.isEmpty { stderr.append(bytes) }
            }
            readers.enter()
            DispatchQueue.global().async {
                defer { try? input.fileHandleForWriting.close(); readers.leave() }
                if !command.input.isEmpty { try? input.fileHandleForWriting.write(contentsOf: Data(command.input.utf8)) }
            }
            var pending = Data(), parser = CLIEventParser(), total = 0, protocolFailed = false
            while let bytes = try readChunk(output.fileHandleForReading) {
                total += bytes.count
                guard total <= 32 * 1024 * 1024 else { cancel(); throw CLIError.invalidOutput }
                pending.append(bytes)
                guard pending.count <= 2 * 1024 * 1024 else { cancel(); throw CLIError.invalidOutput }
                while let newline = pending.firstIndex(of: 10) {
                    let line = pending.prefix(upTo: newline)
                    pending.removeSubrange(...newline)
                    for event in parser.parse(Data(line)) {
                        if event == .failed { protocolFailed = true }
                        continuation.yield(event)
                    }
                }
            }
            if !pending.isEmpty { for event in parser.parse(pending) { if event == .failed { protocolFailed = true }; continuation.yield(event) } }
            process.waitUntilExit()
            readers.wait()
            lock.lock(); let stopped = cancelled, expired = timedOut; lock.unlock()
            if expired { throw CLIError.timedOut }
            if stopped { throw CLIError.stopped }
            if process.terminationStatus != 0 || protocolFailed {
                let diagnostic = String(data: stderr.value, encoding: .utf8) ?? ""
                throw CLIError.classify(stderr: diagnostic, exitCode: process.terminationStatus)
            }
            guard !parser.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw CLIError.invalidOutput }
            continuation.finish()
        } catch {
            if process.isRunning { process.terminate() }
            continuation.finish(throwing: error)
        }
    }
}

final class BoundedData: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()
    private let limit: Int
    init(limit: Int) { self.limit = limit }
    func append(_ bytes: Data) { lock.lock(); defer { lock.unlock() }; if data.count < limit { data.append(bytes.prefix(limit - data.count)) } }
    var value: Data { lock.lock(); defer { lock.unlock() }; return data }
}

enum CLIInstallationScanner {
    static var directories: [String] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        var dirs = (ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin").split(separator: ":").map(String.init)
        dirs += ["/opt/homebrew/bin", "/usr/local/bin", home + "/.local/bin", home + "/.npm-global/bin", home + "/.bun/bin", home + "/.opencode/bin", home + "/.volta/bin", home + "/.asdf/shims"]
        let nvm = URL(fileURLWithPath: home + "/.nvm/versions/node")
        if let versions = try? FileManager.default.contentsOfDirectory(at: nvm, includingPropertiesForKeys: nil) {
            dirs += versions.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedDescending }.prefix(6).map { $0.appendingPathComponent("bin").path }
        }
        return Array(NSOrderedSet(array: dirs)) as? [String] ?? dirs
    }
    static var environment: [String:String] {
        var value = ProcessInfo.processInfo.environment
        value["PATH"] = directories.joined(separator: ":")
        return value
    }

    static func scan(overrides: [String:String]) -> [InstalledCLI] {
        CLIProvider.allCases.compactMap { provider in
            if provider.isLocalServer {
                // Ollama and LM Studio: found when their local server answers.
                let base = LocalModelServer.origin(overrides[provider.rawValue] ?? "") ?? provider.defaultServer
                guard let models = LocalModelServer.modelsBlocking(base) else { return nil }
                return InstalledCLI(provider: provider, path: base, version: "\(models.count) model\(models.count == 1 ? "" : "s") · \(base.replacingOccurrences(of: "http://", with: ""))")
            }
            let custom = overrides[provider.rawValue] ?? ""
            let candidates = custom.isEmpty ? directories.map { $0 + "/" + provider.executable } : [custom]
            guard let path = candidates.first(where: { $0.hasPrefix("/") && FileManager.default.isExecutableFile(atPath: $0) }) else { return nil }
            let version = capture(path: path, arguments: ["--version"])
            guard version.exit == 0 else { return nil }
            return InstalledCLI(provider: provider, path: path, version: version.text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(100).description)
        }
    }

    static func capture(path: String, arguments: [String], timeout: TimeInterval = 4, limit: Int = 4096) -> (exit: Int32, text: String) {
        let task = Process(), stdout = Pipe(), stderr = Pipe(), collected = BoundedData(limit: limit)
        task.executableURL = URL(fileURLWithPath: path); task.arguments = arguments
        task.environment = environment; task.standardInput = FileHandle.nullDevice
        task.standardOutput = stdout; task.standardError = stderr
        let finished = DispatchSemaphore(value: 0), drains = DispatchGroup()
        task.terminationHandler = { _ in finished.signal() }
        do {
            try task.run()
            drains.enter(); DispatchQueue.global().async { defer { drains.leave() }; while let data = try? stdout.fileHandleForReading.read(upToCount: 4096), !data.isEmpty { collected.append(data) } }
            drains.enter(); DispatchQueue.global().async { defer { drains.leave() }; while let data = try? stderr.fileHandleForReading.read(upToCount: 4096), !data.isEmpty {} }
            if finished.wait(timeout: .now() + timeout) == .timedOut {
                task.terminate()
                if finished.wait(timeout: .now() + 1) == .timedOut { Darwin.kill(task.processIdentifier, SIGKILL); _ = finished.wait(timeout: .now() + 1) }
                return (-1, "")
            }
            _ = drains.wait(timeout: .now() + 1)
            return (task.terminationStatus, String(data: collected.value, encoding: .utf8) ?? "")
        } catch { return (-1, "") }
    }
}


/// Optional API keys for the provider CLIs. A saved key is injected into that CLI's environment instead of its
/// sign-in/subscription; remove the key to go back to the CLI's own login. Keys live only in this Mac's Keychain.
enum ProviderAPIKeys {
    static let defaultStore = KeychainSecretStore(service: "org.opengrokbot.mac.provider-api-keys")

    struct Info {
        let variables: [String]
        let console: URL
        let example: String
        let billing: String
    }

    /// Environment variable(s) each CLI reads. OpenCode is not listed: it keeps its own per-provider keys (`opencode auth login`).
    static func info(for provider: CLIProvider) -> Info? {
        switch provider {
        case .codex: Info(variables: ["CODEX_API_KEY", "OPENAI_API_KEY"], console: URL(string: "https://platform.openai.com/api-keys")!, example: "sk-…", billing: "OpenAI API usage is billed per token to your API account, separately from a ChatGPT subscription.")
        case .claude: Info(variables: ["ANTHROPIC_API_KEY"], console: URL(string: "https://console.anthropic.com/settings/keys")!, example: "sk-ant-…", billing: "Claude Code uses a configured API key instead of your Claude subscription, so usage is billed per token to your Anthropic API account.")
        case .grok: Info(variables: ["XAI_API_KEY"], console: URL(string: "https://console.x.ai")!, example: "xai-…", billing: "xAI API usage is billed per token to your xAI account, separately from any X or Grok subscription.")
        case .gemini: Info(variables: ["GEMINI_API_KEY"], console: URL(string: "https://aistudio.google.com/apikey")!, example: "AIza…", billing: "Gemini API usage follows your Google AI Studio plan and quota.")
        case .opencode, .ollama, .lmstudio: nil
        }
    }

    /// Keys contain no whitespace or control characters. Anything else is a paste mistake and is rejected rather than stored.
    static func normalized(_ raw: String) -> String? {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (8...512).contains(value.count), value.unicodeScalars.allSatisfy({ (0x21...0x7E).contains($0.value) }) else { return nil }
        return value
    }

    static func masked(_ key: String) -> String { "••••" + key.suffix(4) }

    static func get(_ provider: CLIProvider, store: KeychainSecretStore = defaultStore) -> String? {
        guard let data = try? store.read(account: provider.rawValue), let text = String(data: data, encoding: .utf8) else { return nil }
        return normalized(text)
    }

    @discardableResult
    static func save(_ raw: String, for provider: CLIProvider, store: KeychainSecretStore = defaultStore) throws -> Bool {
        guard info(for: provider) != nil, let key = normalized(raw) else { return false }
        try store.save(Data(key.utf8), account: provider.rawValue)
        return true
    }

    static func remove(_ provider: CLIProvider, store: KeychainSecretStore = defaultStore) throws { try store.delete(account: provider.rawValue) }

    /// Variables to add to the CLI's environment; empty when no key is saved (the CLI then uses its own sign-in).
    static func environment(for provider: CLIProvider, store: KeychainSecretStore = defaultStore) -> [String:String] {
        guard let info = info(for: provider), let key = get(provider, store: store) else { return [:] }
        return Dictionary(uniqueKeysWithValues: info.variables.map { ($0, key) })
    }
}

// MARK: - Image and video generation (0.9.7)
// A Bot asks with generate_image or generate_video; the app calls the provider with the human's own key (in the
// Keychain, never shown to the model), saves the file in the Bot's folder, and the chat shows it.

enum MediaProvider: String, CaseIterable, Identifiable, Sendable {
    case flux, google, openai, replicate
    var id: String { rawValue }
    var name: String {
        switch self {
        case .flux: "Flux (Black Forest Labs)"
        case .google: "Google (Imagen, Veo)"
        case .openai: "OpenAI images"
        case .replicate: "Replicate (many image and video models)"
        }
    }
    var shortName: String { String(name.split(separator: " (").first ?? Substring(name)) }
    var kinds: [String] { self == .flux || self == .openai ? ["image"] : ["image", "video"] }
    func defaultModel(_ kind: String) -> String {
        switch (self, kind) {
        case (.flux, _): "flux-pro-1.1"
        case (.google, "video"): "veo-3.0-generate-001"
        case (.google, _): "imagen-4.0-generate-001"
        case (.openai, _): "gpt-image-1"
        case (.replicate, "video"): "minimax/video-01"
        case (.replicate, _): "black-forest-labs/flux-schnell"
        }
    }
    var keyHelp: URL {
        switch self {
        case .flux: URL(string: "https://dashboard.bfl.ai/")!
        case .google: URL(string: "https://aistudio.google.com/apikey")!
        case .openai: URL(string: "https://platform.openai.com/api-keys")!
        case .replicate: URL(string: "https://replicate.com/account/api-tokens")!
        }
    }
}

enum MediaKeys {
    static let store = KeychainSecretStore(service: "org.opengrokbot.mac.media-api-keys")
    static func get(_ provider: MediaProvider) -> String? {
        guard let data = try? store.read(account: provider.rawValue), let text = String(data: data, encoding: .utf8) else { return nil }
        return ProviderAPIKeys.normalized(text)
    }
    @discardableResult static func save(_ raw: String, for provider: MediaProvider) throws -> Bool {
        guard let key = ProviderAPIKeys.normalized(raw) else { return false }
        try store.save(Data(key.utf8), account: provider.rawValue); return true
    }
    static func remove(_ provider: MediaProvider) throws { try store.delete(account: provider.rawValue) }
    static var ready: [MediaProvider] { MediaProvider.allCases.filter { get($0) != nil } }
    static func model(_ provider: MediaProvider, _ kind: String) -> String {
        let saved = UserDefaults.standard.string(forKey: "media.model.\(provider.rawValue).\(kind)")?.trimmingCharacters(in: .whitespaces) ?? ""
        return MediaGenerator.validModel(saved) ? saved : provider.defaultModel(kind)
    }
    /// The one asked for if it has a key and can make this kind, else the default for the kind, else the first that can.
    static func choose(_ kind: String, wanted: String?) -> MediaProvider? {
        let ready = ready.filter { $0.kinds.contains(kind) }
        if let wanted = wanted.flatMap({ MediaProvider(rawValue: $0.lowercased()) }), ready.contains(wanted) { return wanted }
        if let saved = UserDefaults.standard.string(forKey: "media.default.\(kind)").flatMap(MediaProvider.init(rawValue:)), ready.contains(saved) { return saved }
        return ready.first
    }
    /// What a Bot is told when a key is saved.
    static func note() -> String {
        let list = ready.map { "\($0.rawValue) (\($0.kinds.joined(separator: " and ")))" }
        guard !list.isEmpty else { return "" }
        return "\nImage and video tools: when the human asks for a picture or a video, append {\"action\":\"generate_image\",\"prompt\":\"a detailed description\"} or {\"action\":\"generate_video\",\"prompt\":\"…\"} in an opengrokbot-action fence. Add \"provider\" to choose one of: \(list.joined(separator: ", ")). The app makes it with the human's own API key and shows it in this chat; videos can take a few minutes. Make one per request, and only when asked."
    }
}

enum MediaGenerator {
    struct Failure: LocalizedError { let message: String; init(_ message: String) { self.message = message }; var errorDescription: String? { message } }
    static func validModel(_ value: String) -> Bool { value.range(of: "^[A-Za-z0-9._-]{1,100}(/[A-Za-z0-9._-]{1,100})?(:[A-Za-z0-9]{1,100})?$", options: .regularExpression) != nil }

    private static func json(_ url: URL, method: String = "GET", headers: [String: String], body: [String: Any]? = nil, label: String) async throws -> [String: Any] {
        var request = URLRequest(url: url, timeoutInterval: 120)
        request.httpMethod = method
        for (name, value) in headers { request.setValue(value, forHTTPHeaderField: name) }
        if let body { request.setValue("application/json", forHTTPHeaderField: "Content-Type"); request.httpBody = try JSONSerialization.data(withJSONObject: body) }
        let data: Data, response: URLResponse
        do { (data, response) = try await URLSession.shared.data(for: request) } catch { throw Failure("\(label) could not be reached.") }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        if [401, 403].contains(status) { throw Failure("\(label) rejected the API key. Check it in Settings → API Keys.") }
        if status == 402 { throw Failure("\(label) says the account has no credit left.") }
        if status == 429 { throw Failure("\(label)’s rate limit was reached. Try again in a minute.") }
        guard (200..<300).contains(status), let object else {
            let reason = ((object?["error"] as? [String: Any])?["message"] as? String) ?? (object?["detail"] as? String) ?? (object?["error"] as? String) ?? "HTTP \(status)"
            throw Failure("\(label) could not make it: \(String(reason.prefix(200)))")
        }
        return object
    }

    private static func download(_ link: String, kind: String, label: String, headers: [String: String] = [:]) async throws -> (Data, String) {
        guard let url = URL(string: link), url.scheme == "https" else { throw Failure("\(label) returned an unusable link.") }
        var request = URLRequest(url: url, timeoutInterval: 300)
        for (name, value) in headers { request.setValue(value, forHTTPHeaderField: name) }
        let data: Data, response: URLResponse
        do { (data, response) = try await URLSession.shared.data(for: request) } catch { throw Failure("The \(kind) could not be downloaded from \(label).") }
        guard (response as? HTTPURLResponse)?.statusCode == 200, !data.isEmpty, data.count <= (kind == "video" ? 200_000_000 : 25_000_000) else { throw Failure("The \(kind) from \(label) could not be downloaded or was too large.") }
        return (data, (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Type") ?? "")
    }

    private static func waitFor(_ label: String, every seconds: Double, limit: Double, _ check: () async throws -> [String: Any]?) async throws -> [String: Any] {
        let end = Date().addingTimeInterval(limit)
        while Date() < end {
            try Task.checkCancellation()
            if let value = try await check() { return value }
            try await Task.sleep(for: .seconds(seconds))
        }
        throw Failure("\(label) took too long. Try again or choose a faster model.")
    }

    static func fileExtension(_ type: String, kind: String) -> String {
        let value = type.lowercased()
        if value.contains("png") { return "png" }
        if value.contains("jpeg") || value.contains("jpg") { return "jpg" }
        if value.contains("webp") { return "webp" }
        if value.contains("webm") { return "webm" }
        if value.contains("quicktime") { return "mov" }
        return kind == "video" ? "mp4" : "png"
    }

    /// Makes one image or video. Returns the bytes, a file extension and the model used.
    static func generate(kind: String, provider: MediaProvider, prompt: String, key: String, model: String) async throws -> (data: Data, fileExtension: String, model: String) {
        guard provider.kinds.contains(kind) else { throw Failure("That provider cannot make this.") }
        let text = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text.count <= 4000 else { throw Failure("Describe the \(kind) in up to 4,000 characters.") }
        let label = provider.shortName
        var result: (Data, String)?
        switch (provider, kind) {
        case (.openai, _):
            let body = try await json(URL(string: "https://api.openai.com/v1/images/generations")!, method: "POST", headers: ["Authorization": "Bearer " + key], body: ["model": model, "prompt": text, "size": "1024x1024", "n": 1], label: label)
            let item = (body["data"] as? [[String: Any]])?.first
            if let base64 = item?["b64_json"] as? String, let data = Data(base64Encoded: base64) { result = (data, "image/png") }
            else if let link = item?["url"] as? String { result = try await download(link, kind: kind, label: label) }
        case (.google, "video"):
            let start = try await json(URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):predictLongRunning")!, method: "POST", headers: ["x-goog-api-key": key], body: ["instances": [["prompt": text]]], label: label)
            guard let name = start["name"] as? String, name.range(of: "^[A-Za-z0-9/._-]+$", options: .regularExpression) != nil, let poll = URL(string: "https://generativelanguage.googleapis.com/v1beta/" + name) else { throw Failure("\(label) did not start the video.") }
            let done = try await waitFor(label, every: 5, limit: 600) {
                let state = try await json(poll, headers: ["x-goog-api-key": key], label: label)
                if let error = state["error"] as? [String: Any] { throw Failure("\(label) could not make it: \(String(((error["message"] as? String) ?? "").prefix(200)))") }
                return (state["done"] as? Bool) == true ? state : nil
            }
            let response = done["response"] as? [String: Any]
            let sample = ((response?["generateVideoResponse"] as? [String: Any])?["generatedSamples"] as? [[String: Any]])?.first ?? (response?["generatedVideos"] as? [[String: Any]])?.first
            if let link = (sample?["video"] as? [String: Any])?["uri"] as? String { result = try await download(link, kind: kind, label: label, headers: ["x-goog-api-key": key]) }
        case (.google, _):
            let body = try await json(URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):predict")!, method: "POST", headers: ["x-goog-api-key": key], body: ["instances": [["prompt": text]], "parameters": ["sampleCount": 1]], label: label)
            let item = (body["predictions"] as? [[String: Any]])?.first
            if let base64 = item?["bytesBase64Encoded"] as? String, let data = Data(base64Encoded: base64) { result = (data, (item?["mimeType"] as? String) ?? "image/png") }
        case (.flux, _):
            let start = try await json(URL(string: "https://api.bfl.ai/v1/\(model)")!, method: "POST", headers: ["x-key": key], body: ["prompt": text, "width": 1024, "height": 1024], label: label)
            let pollLink = (start["polling_url"] as? String).flatMap { $0.hasPrefix("https://") ? $0 : nil } ?? (start["id"] as? String).map { "https://api.bfl.ai/v1/get_result?id=\($0)" }
            guard let pollLink, let poll = URL(string: pollLink) else { throw Failure("\(label) did not start the image.") }
            let done = try await waitFor(label, every: 2, limit: 300) {
                let state = try await json(poll, headers: ["x-key": key], label: label)
                let status = state["status"] as? String ?? ""
                if ["Error", "Failed", "Request Moderated", "Content Moderated"].contains(status) { throw Failure("\(label) could not make it (\(status)).") }
                return status == "Ready" ? state : nil
            }
            if let link = (done["result"] as? [String: Any])?["sample"] as? String { result = try await download(link, kind: kind, label: label) }
        case (.replicate, _):
            let pieces = model.split(separator: "/", maxSplits: 1).map(String.init)
            guard pieces.count == 2 else { throw Failure("Replicate models are written as owner/name, for example black-forest-labs/flux-schnell.") }
            let nameAndVersion = pieces[1].split(separator: ":", maxSplits: 1).map(String.init)
            let endpoint = nameAndVersion.count == 2 ? "https://api.replicate.com/v1/predictions" : "https://api.replicate.com/v1/models/\(pieces[0])/\(nameAndVersion[0])/predictions"
            let body: [String: Any] = nameAndVersion.count == 2 ? ["version": nameAndVersion[1], "input": ["prompt": text]] : ["input": ["prompt": text]]
            var state = try await json(URL(string: endpoint)!, method: "POST", headers: ["Authorization": "Bearer " + key, "Prefer": "wait=60"], body: body, label: label)
            let finished: Set<String> = ["succeeded", "failed", "canceled"]
            if !finished.contains(state["status"] as? String ?? "") {
                guard let selfLink = (state["urls"] as? [String: Any])?["get"] as? String, selfLink.hasPrefix("https://api.replicate.com/"), let poll = URL(string: selfLink) else { throw Failure("\(label) did not start the \(kind).") }
                state = try await waitFor(label, every: kind == "video" ? 5 : 2, limit: kind == "video" ? 900 : 300) {
                    let next = try await json(poll, headers: ["Authorization": "Bearer " + key], label: label)
                    return finished.contains(next["status"] as? String ?? "") ? next : nil
                }
            }
            guard (state["status"] as? String) == "succeeded" else { throw Failure("\(label) could not make it: \(String(((state["error"] as? String) ?? (state["status"] as? String) ?? "").prefix(200)))") }
            let output = (state["output"] as? String) ?? (state["output"] as? [Any])?.compactMap { $0 as? String }.first
            if let output { result = try await download(output, kind: kind, label: label) }
        }
        guard let result, !result.0.isEmpty else { throw Failure("\(label) finished without a \(kind).") }
        return (result.0, fileExtension(result.1, kind: kind), model)
    }

    /// A short, safe file name from the prompt.
    static func fileName(_ prompt: String, fileExtension: String, date: Date = Date()) -> String {
        let slug = String(prompt.lowercased().map { $0.isLetter && $0.isASCII || $0.isNumber && $0.isASCII ? $0 : "-" }).split(separator: "-").joined(separator: "-").prefix(40)
        let stamp = ISO8601DateFormatter().string(from: date).replacingOccurrences(of: "-", with: "").replacingOccurrences(of: ":", with: "").replacingOccurrences(of: "Z", with: "")
        return "\(stamp)-\(slug.isEmpty ? "media" : String(slug)).\(fileExtension)"
    }
}
