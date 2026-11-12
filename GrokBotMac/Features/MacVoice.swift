import AppKit
import CryptoKit
import SwiftUI
import WebKit

// MARK: - Voice hub (0.9.3)

/// Voice mode belongs to the window, not to one chat: it keeps listening and speaking while you open other Bots,
/// and shows as a small card, the whole window, or a small pill.
@MainActor
final class MacVoiceHub: ObservableObject {
    static let shared = MacVoiceHub()
    let conversation = VoiceConversation()
    @Published private(set) var botID: UUID?
    @Published var layout: VoiceLayout = VoiceSettings.layout
    private weak var desktop: MacAppModel?
    private var keyMonitor: Any?

    var isOn: Bool { botID != nil }

    func start(bot: Bot, desktop: MacAppModel, app: AppModel) {
        if botID == bot.id { if layout == .mini { layout = VoiceSettings.layout }; return }
        if botID != nil { stop() }
        self.desktop = desktop
        botID = bot.id; layout = VoiceSettings.layout
        desktop.setVoiceMode(bot.id, on: true)
        installSpaceToTalk()
        let current = bot, model = desktop, workspace = app
        // Names recognition should expect: every Bot's name.
        let names = workspace.workspace.bots.map(\.name)
        Task {
            await conversation.start(
                botVoice: current.voice,
                send: { text in model.send(text, to: current, app: workspace) },
                latestReply: {
                    guard let entry = workspace.entries(for: current).last(where: { $0.kind == .bot }) else { return nil }
                    let finished = entry.state != .streaming && !model.runningBots.contains(current.id)
                    return VoiceReply(id: entry.id, text: entry.text, finished: finished)
                },
                stopReply: { model.stop(botID: current.id) },
                activity: { workspace.entries(for: current).suffix(12).filter { $0.kind == .activity }.map { VoiceStep(id: $0.id, text: $0.text, date: $0.date) } },
                vocabulary: names)
            // Could not start (no microphone, models not ready): leave the card up so the reason stays visible.
        }
    }

    func stop() {
        guard let id = botID else { return }
        conversation.stop()
        desktop?.setVoiceMode(id, on: false)
        botID = nil
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
    }

    /// Hold Space (while not typing) to keep talking; let go to send.
    private func installSpaceToTalk() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        let session = conversation.session
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { [weak self] event in
            guard event.keyCode == 49, event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty,
                  !(event.window?.firstResponder is NSTextView) else { return event }
            let layout = MainActor.assumeIsolated { self?.layout }
            guard let layout, layout != .mini else { return event }
            MainActor.assumeIsolated {
                if event.type == .keyDown { if !event.isARepeat { session.hold(true) } } else { session.hold(false) }
            }
            return nil
        }
    }
}

/// Draws the voice UI above the whole workspace.
struct MacVoiceOverlay: View {
    @ObservedObject var hub: MacVoiceHub
    @EnvironmentObject private var app: AppModel
    @EnvironmentObject private var desktop: MacAppModel

    var body: some View {
        if let id = hub.botID, let bot = app.workspace.bots.first(where: { $0.id == id }) {
            let color = bot.appearance?.color ?? bot.color
            let plain = bot.appearance == nil && bot.color == "white"
            VoiceModeView(conversation: hub.conversation, botName: bot.name,
                          tint: plain ? .primary : AvatarArtwork.color(color),
                          ink: plain ? MacTheme.canvas : (["white", "amber", "orange", "green", "teal", "gray"].contains(color) ? .black : .white),
                          face: AnyView(MacBotAvatar(color: bot.color, size: 26, appearance: bot.appearance)),
                          layout: $hub.layout,
                          openBot: { desktop.selectedID = id; if hub.layout == .full { hub.layout = .card } },
                          close: { hub.stop() })
            .transition(.opacity)
        }
    }
}

// MARK: - Open-source voice engine (Kokoro + Whisper in a hidden web view)

/// Downloads models once from Hugging Face (only the repositories listed here) and the WebAssembly runtime from a
/// pinned copy checked by SHA-256, then serves them offline. Mirrors desktop-windows/app/local-voice.cjs.
final class MacLocalVoiceStore: @unchecked Sendable {
    static let ttsRepo = "onnx-community/Kokoro-82M-v1.0-ONNX"
    static let sttRepos = ["onnx-community/whisper-tiny.en", "onnx-community/whisper-tiny", "onnx-community/whisper-base.en", "onnx-community/whisper-base", "onnx-community/whisper-small.en", "onnx-community/whisper-small"]
    static let runtimeBase = "https://cdn.jsdelivr.net/npm/@huggingface/transformers@3.7.6/dist/"
    static let runtime: [String: String] = [
        "ort-wasm-simd-threaded.jsep.mjs": "08fb86ec433c78bfb032c5d84a68b8e8e5a8d81268fa39e24314179a5767a5b9",
        "ort-wasm-simd-threaded.jsep.wasm": "c46655e8a94afc45338d4cb2b840475f88e5012d524509916e505079c00bfa39"
    ]
    let root: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/OpenGrokBot/LocalVoice")

    struct Source { let url: URL; let sha256: String?; let cache: URL }

    /// Where an ogb-models:// path comes from, or nil when it is not an approved file.
    func source(_ path: String) -> Source? {
        let clean = (path.removingPercentEncoding ?? path).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !clean.contains(".."), !clean.contains("\\") else { return nil }
        if clean.hasPrefix("ort/") {
            let name = String(clean.dropFirst(4))
            guard let hash = Self.runtime[name], let url = URL(string: Self.runtimeBase + name) else { return nil }
            return Source(url: url, sha256: hash, cache: root.appendingPathComponent("runtime/" + name))
        }
        guard clean.hasPrefix("hf/") else { return nil }
        let rest = String(clean.dropFirst(3))
        guard let repo = ([Self.ttsRepo] + Self.sttRepos).first(where: { rest.hasPrefix($0 + "/resolve/") }) else { return nil }
        let file = String(rest.dropFirst(repo.count + "/resolve/".count))
        guard file.range(of: "^[A-Za-z0-9._-]+/[A-Za-z0-9._/-]+$", options: .regularExpression) != nil,
              let url = URL(string: "https://huggingface.co/" + rest) else { return nil }
        return Source(url: url, sha256: nil, cache: root.appendingPathComponent("hf/" + rest))
    }

    static func contentType(_ name: String) -> String {
        name.hasSuffix(".mjs") || name.hasSuffix(".js") ? "text/javascript" : name.hasSuffix(".wasm") ? "application/wasm" : name.hasSuffix(".json") ? "application/json" : "application/octet-stream"
    }

    struct Failure: LocalizedError { let errorDescription: String? }

    /// The file's bytes: from the cache, or downloaded once. Returns nil for a file the source does not have (404).
    func file(_ path: String) async throws -> (data: Data, type: String)? {
        guard let source = source(path) else { return nil }
        if let data = try? Data(contentsOf: source.cache) { return (data, Self.contentType(source.cache.lastPathComponent)) }
        let (data, response) = try await URLSession.shared.data(from: source.url)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 404 { return nil }
        guard status == 200 else { throw Failure(errorDescription: "Download failed (HTTP \(status)).") }
        if let expected = source.sha256 {
            let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            guard digest == expected else { throw Failure(errorDescription: "The voice runtime download did not match its checksum.") }
        }
        try FileManager.default.createDirectory(at: source.cache.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: source.cache, options: .atomic)
        return (data, Self.contentType(source.cache.lastPathComponent))
    }

    func installed(_ repo: String) -> Bool { FileManager.default.fileExists(atPath: root.appendingPathComponent("hf/" + repo).path) }
    func remove() { try? FileManager.default.removeItem(at: root) }
}

/// Serves the engine script from the app bundle and model files from the store to the hidden web view.
@MainActor
final class MacModelSchemeHandler: NSObject, WKURLSchemeHandler {
    let store: MacLocalVoiceStore
    private var live: Set<ObjectIdentifier> = []
    init(store: MacLocalVoiceStore) { self.store = store }

    func webView(_ webView: WKWebView, start urlSchemeTask: any WKURLSchemeTask) {
        let id = ObjectIdentifier(urlSchemeTask)
        live.insert(id)
        guard let url = urlSchemeTask.request.url, url.host == "local" else { fail(urlSchemeTask, status: 404); return }
        if url.path == "/engine.html" {
            respond(urlSchemeTask, url: url, data: Data("<!doctype html><html><head><meta charset=\"utf-8\"><script src=\"engine.js\"></script></head><body></body></html>".utf8), type: "text/html"); return
        }
        if url.path == "/engine.js" {
            guard let file = Bundle.main.url(forResource: "local-voice-engine", withExtension: "js"), let data = try? Data(contentsOf: file) else { fail(urlSchemeTask, status: 404); return }
            respond(urlSchemeTask, url: url, data: data, type: "text/javascript"); return
        }
        let store = self.store, path = url.path
        Task { @MainActor [weak self] in
            do {
                let found = try await store.file(path)
                guard let self, self.live.contains(id) else { return }
                if let found { self.respond(urlSchemeTask, url: url, data: found.data, type: found.type) } else { self.fail(urlSchemeTask, status: 404) }
            } catch {
                guard let self, self.live.contains(id) else { return }
                self.fail(urlSchemeTask, status: 502)
            }
        }
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: any WKURLSchemeTask) { live.remove(ObjectIdentifier(urlSchemeTask)) }

    private func respond(_ task: any WKURLSchemeTask, url: URL, data: Data, type: String) {
        guard live.remove(ObjectIdentifier(task)) != nil else { return }
        // COOP/COEP make the engine page cross-origin isolated, so the WebAssembly runtime can use several cores.
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": type, "Access-Control-Allow-Origin": "*", "Content-Length": String(data.count),
            "Cross-Origin-Opener-Policy": "same-origin", "Cross-Origin-Embedder-Policy": "require-corp", "Cross-Origin-Resource-Policy": "cross-origin"])!
        task.didReceive(response); task.didReceive(data); task.didFinish()
    }
    private func fail(_ task: any WKURLSchemeTask, status: Int) {
        guard live.remove(ObjectIdentifier(task)) != nil, let url = task.request.url else { return }
        let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: ["Access-Control-Allow-Origin": "*", "Content-Length": "0"])!
        task.didReceive(response); task.didReceive(Data()); task.didFinish()
    }
}

/// Receives download progress from the engine without the web view keeping the engine alive.
@MainActor
private final class ProgressProxy: NSObject, WKScriptMessageHandler {
    var onMessage: ((Int, Int, String) -> Void)?
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any] else { return }
        onMessage?((body["loaded"] as? NSNumber)?.intValue ?? 0, (body["total"] as? NSNumber)?.intValue ?? 0, body["kind"] as? String ?? "")
    }
}

/// Runs local-voice-engine.js (Kokoro speaking, Whisper listening) in a hidden web view.
@MainActor
final class MacLocalVoiceEngine: NSObject, LocalVoiceBackend, WKNavigationDelegate {
    static let shared = MacLocalVoiceEngine()
    let store = MacLocalVoiceStore()
    private var webView: WKWebView?
    private var loading: CheckedContinuation<Void, Error>?
    private let proxy = ProgressProxy()
    private var progressLine: (@MainActor (String) -> Void)?

    struct Plan: Equatable {
        var ttsDtype: String, ttsDevice: String, sttModel: String, sttDevice: String
        var tier: String, why: String, downloadMB: Int
    }

    /// Picks models for this Mac (0.9.4). Speaking: Kokoro q8 on the processor, which is quick and works everywhere;
    /// the graphics chip is used only after "Test speed" shows it is faster. Listening: Apple's on-device recognizer is the
    /// fastest on a Mac and gives live captions, so Whisper is optional (base, or tiny on small Macs).
    static func recommendation(webgpu: Bool) -> Plan {
        let memoryGB = Double(ProcessInfo.processInfo.physicalMemory) / 1_073_741_824
        #if arch(arm64)
        let appleSilicon = true
        #else
        let appleSilicon = false
        #endif
        let english = (Locale.current.language.languageCode?.identifier ?? "en") == "en"
        let size = appleSilicon || memoryGB >= 8 ? "base" : "tiny"
        let why = appleSilicon ? "Kokoro’s small model speaks faster than real time on Apple silicon. For listening, Apple’s own recognizer is quicker on a Mac and shows live captions; Whisper is optional."
            : "Kokoro’s small model keeps speech quick on this Mac. For listening, Apple’s recognizer is the fastest; Whisper is optional."
        return Plan(ttsDtype: "q8", ttsDevice: "wasm", sttModel: "onnx-community/whisper-\(size)\(english ? ".en" : "")", sttDevice: "wasm",
                    tier: appleSilicon ? "fast" : memoryGB >= 8 ? "balanced" : "light", why: why, downloadMB: 92 + 22)
    }

    /// The plan in use: the recommendation, with any sizes the human chose.
    func plan() async -> Plan {
        var plan = Self.recommendation(webgpu: false)
        let defaults = UserDefaults.standard
        if let dtype = defaults.string(forKey: "localVoiceTTSDtype"), ["q8", "fp16", "fp32"].contains(dtype) { plan.ttsDtype = dtype }
        if let model = defaults.string(forKey: "localVoiceSTTModel"), MacLocalVoiceStore.sttRepos.contains(model) { plan.sttModel = model }
        if let device = defaults.string(forKey: "localVoiceDevice"), ["wasm", "webgpu"].contains(device) { plan.ttsDevice = device; plan.sttDevice = device }
        return plan
    }

    private var gpuChecked: Bool?
    func webGPU() async -> Bool {
        if let gpuChecked { return gpuChecked }
        guard let view = try? await engine() else { return false }
        let value = (try? await view.callAsyncJavaScript("const c = await OGBLocalVoice.capabilities(); return c.webgpu ? 'yes' : 'no';", arguments: [:], in: nil, contentWorld: .page)) as? String
        gpuChecked = value == "yes"
        return value == "yes"
    }

    private var loadTask: Task<WKWebView, Error>?

    /// One hidden web view, loaded once; callers that arrive while it loads wait for the same load.
    private func engine() async throws -> WKWebView {
        if let loadTask { return try await loadTask.value }
        let task = Task { @MainActor in try await self.makeEngine() }
        loadTask = task
        do { return try await task.value } catch { loadTask = nil; throw error }
    }

    private func makeEngine() async throws -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.setURLSchemeHandler(MacModelSchemeHandler(store: store), forURLScheme: "ogb-models")
        configuration.userContentController.add(proxy, name: "progress")
        configuration.userContentController.addUserScript(WKUserScript(source: "globalThis.ogbVoiceProgress = p => window.webkit.messageHandlers.progress.postMessage({kind: String(p.kind), loaded: p.loaded || 0, total: p.total || 0});", injectionTime: .atDocumentStart, forMainFrameOnly: true))
        let view = WKWebView(frame: CGRect(x: 0, y: 0, width: 10, height: 10), configuration: configuration)
        view.navigationDelegate = self
        proxy.onMessage = { [weak self] loaded, total, kind in
            guard total > 0 else { return }
            self?.progressLine?("Downloading the \(kind == "stt" ? "listening" : "speaking") model… \(Int(100 * Double(loaded) / Double(total)))%")
        }
        webView = view
        guard let start = URL(string: "ogb-models://local/engine.html") else { throw MacLocalVoiceStore.Failure(errorDescription: "The voice engine could not load.") }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            loading = continuation
            view.load(URLRequest(url: start))
        }
        let defined = (try? await view.callAsyncJavaScript("return typeof OGBLocalVoice === 'object' ? 'yes' : 'no';", arguments: [:], in: nil, contentWorld: .page)) as? String
        guard defined == "yes" else { throw MacLocalVoiceStore.Failure(errorDescription: "The voice engine could not start.") }
        return view
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { loading?.resume(); loading = nil }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: any Error) { fail(error) }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: any Error) { fail(error) }
    private func fail(_ error: any Error) { loading?.resume(throwing: error); loading = nil; webView = nil }

    private func call(_ body: String, _ arguments: [String: Any] = [:]) async throws -> String {
        let view = try await engine()
        do {
            let value = try await view.callAsyncJavaScript(body, arguments: arguments, in: nil, contentWorld: .page)
            return value as? String ?? ""
        } catch {
            let message = ((error as NSError).userInfo["WKJavaScriptExceptionMessage"] as? String) ?? error.localizedDescription
            throw MacLocalVoiceStore.Failure(errorDescription: String(message.replacingOccurrences(of: "Error: ", with: "").prefix(300)))
        }
    }

    // LocalVoiceBackend

    func prepare(listening: Bool, speaking: Bool, progress: @escaping @MainActor (String) -> Void) async throws {
        progressLine = progress
        defer { progressLine = nil }
        let plan = await plan()
        if speaking {
            let used = try await call("const r = await OGBLocalVoice.loadTTS({dtype, device}); return r.device;", ["dtype": plan.ttsDtype, "device": plan.ttsDevice])
            if used != plan.ttsDevice { UserDefaults.standard.set("wasm", forKey: "localVoiceDevice") } // The graphics chip failed: stay on the processor.
        }
        if listening { _ = try await call("await OGBLocalVoice.loadSTT({model, device}); return 'ok';", ["model": plan.sttModel, "device": plan.sttDevice]) }
    }

    func speak(_ text: String) async throws -> Data {
        let plan = await plan()
        _ = try await call("await OGBLocalVoice.loadTTS({dtype, device}); return 'ok';", ["dtype": plan.ttsDtype, "device": plan.ttsDevice])
        let encoded = try await call("return await OGBLocalVoice.speak(text, {voice, speed: 1, encoding: 'base64'});", ["text": String(text.prefix(1000)), "voice": VoiceSettings.kokoroVoice])
        guard let data = Data(base64Encoded: encoded), !data.isEmpty else { throw MacLocalVoiceStore.Failure(errorDescription: "The local voice returned no audio.") }
        return data
    }

    func transcribe(_ samples: [Float], sampleRate: Double, language: String) async throws -> String {
        let plan = await plan()
        _ = try await call("await OGBLocalVoice.loadSTT({model, device}); return 'ok';", ["model": plan.sttModel, "device": plan.sttDevice])
        // Whisper wants 16 kHz mono float samples.
        let ratio = max(1, sampleRate / 16_000), count = Int(Double(samples.count) / ratio)
        var resampled = [Float](repeating: 0, count: count)
        for index in 0..<count {
            let start = Int(Double(index) * ratio), end = min(samples.count, max(start + 1, Int(Double(index + 1) * ratio)))
            var sum: Float = 0
            for j in start..<end { sum += samples[j] }
            resampled[index] = sum / Float(end - start)
        }
        let encoded = resampled.withUnsafeBufferPointer { Data(buffer: $0) }.base64EncodedString()
        return try await call("return await OGBLocalVoice.transcribe(samples, {language});", ["samples": encoded, "language": String(language.prefix(2))])
    }

    func reset() { webView = nil; loadTask = nil; gpuChecked = nil }

    struct Speed { var speakingRTF: Double?; var listeningRTF: Double?; var heard: String; var threads: Int; var device: String }

    /// Times Kokoro (and Whisper, when listening uses it) on this Mac with the current settings.
    func measure(listening: Bool) async throws -> Speed {
        try await prepare(listening: listening, speaking: true) { _ in }
        let json = try await call("return JSON.stringify(await OGBLocalVoice.benchmark());")
        let object = (try? JSONSerialization.jsonObject(with: Data(json.utf8))) as? [String: Any] ?? [:]
        let tts = object["tts"] as? [String: Any], stt = object["stt"] as? [String: Any]
        return Speed(speakingRTF: (tts?["realTimeFactor"] as? NSNumber)?.doubleValue, listeningRTF: (stt?["realTimeFactor"] as? NSNumber)?.doubleValue,
                     heard: stt?["heard"] as? String ?? "", threads: (object["threads"] as? NSNumber)?.intValue ?? 1, device: await plan().ttsDevice)
    }

    /// Tries the graphics chip and the processor and keeps whichever speaks faster on this Mac.
    func pickFastestDevice() async throws -> Speed {
        UserDefaults.standard.set("wasm", forKey: "localVoiceDevice")
        let processor = try await measure(listening: false)
        guard await webGPU() else { return processor }
        UserDefaults.standard.set("webgpu", forKey: "localVoiceDevice")
        guard let graphics = try? await measure(listening: false), let fast = graphics.speakingRTF, let slow = processor.speakingRTF, fast < slow * 0.8 else {
            UserDefaults.standard.set("wasm", forKey: "localVoiceDevice"); return processor
        }
        return graphics
    }
}

// MARK: - Settings section

/// Voice settings → Open-source voice on this Mac: what the Mac can run, one-click download, sizes and voices.
struct MacLocalVoiceSection: View {
    @State private var plan: MacLocalVoiceEngine.Plan?
    @State private var recommended: MacLocalVoiceEngine.Plan?
    @State private var status: String?
    @State private var working = false
    @State private var voice = VoiceSettings.kokoroVoice
    @State private var speed: String?
    private var engine: MacLocalVoiceEngine { MacLocalVoiceEngine.shared }

    var body: some View {
        Section {
            if let plan, let recommended {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Recommended for this Mac · \(recommended.tier)").font(.caption.weight(.semibold)).foregroundStyle(MacTheme.working)
                    Text(recommended.why).font(.callout)
                    Text("Speaking: Kokoro-82M (\(plan.ttsDtype), \(plan.ttsDevice == "webgpu" ? "graphics chip" : "processor")) · Listening: Apple, or \(plan.sttModel.replacingOccurrences(of: "onnx-community/", with: "").replacingOccurrences(of: "-", with: " ").capitalized)")
                        .font(.caption).foregroundStyle(.secondary)
                }
                let speaking = engine.store.installed(MacLocalVoiceStore.ttsRepo)
                let listening = engine.store.installed(plan.sttModel)
                HStack {
                    Button(working ? "Working…" : speaking ? "Check Kokoro" : "Download Kokoro voice (\(recommended.downloadMB) MB)") { download(listening: false) }
                        .disabled(working)
                    Button(listening ? "Use Whisper for listening" : "Also download Whisper for listening") { download(listening: true) }
                        .disabled(working)
                }
                HStack {
                    Button("Test speed") { test() }.disabled(working || !speaking)
                    Button("Use the graphics chip if it’s faster") { pickDevice() }.disabled(working || !speaking)
                }
                if let speed { Text(speed).font(.caption).foregroundStyle(.secondary) }
                Picker("Listening model", selection: Binding(get: { plan.sttModel }, set: { UserDefaults.standard.set($0, forKey: "localVoiceSTTModel"); refresh() })) {
                    Text("Whisper tiny · English · fastest").tag("onnx-community/whisper-tiny.en")
                    Text("Whisper base · English").tag("onnx-community/whisper-base.en")
                    Text("Whisper small · English · most accurate").tag("onnx-community/whisper-small.en")
                    Text("Whisper tiny · any language").tag("onnx-community/whisper-tiny")
                    Text("Whisper base · any language").tag("onnx-community/whisper-base")
                    Text("Whisper small · any language").tag("onnx-community/whisper-small")
                }
                Picker("Speaking model", selection: Binding(get: { plan.ttsDtype }, set: { UserDefaults.standard.set($0, forKey: "localVoiceTTSDtype"); refresh() })) {
                    Text("Kokoro · small and quick (92 MB)").tag("q8")
                    Text("Kokoro · balanced (163 MB)").tag("fp16")
                    Text("Kokoro · full quality (326 MB)").tag("fp32")
                }
                HStack {
                    Picker("Kokoro voice", selection: $voice) { ForEach(VoiceSettings.kokoroVoices, id: \.id) { Text($0.name).tag($0.id) } }
                        .onChange(of: voice) { _, value in VoiceSettings.kokoroVoice = value }
                    Button("Preview") { preview() }.disabled(working)
                }
                Button("Remove downloaded models", role: .destructive) { engine.store.remove(); engine.reset(); status = "Voice models removed."; refresh() }
                    .disabled(working)
            } else {
                Text("Checking this Mac…").foregroundStyle(.secondary)
            }
            if let status { Text(status).font(.caption).foregroundStyle(.secondary) }
        } header: { Text("Open-source voice on this Mac") } footer: {
            Text("Kokoro speaks and (optionally) Whisper listens, running on your Mac with nothing sent anywhere. Models download once from Hugging Face. “Test speed” shows how fast they run here: below 0.5× real time feels instant.")
        }
        .task { refresh() }
    }

    private func refresh() {
        Task {
            let current = await engine.plan()
            recommended = MacLocalVoiceEngine.recommendation(webgpu: false)
            plan = current
        }
    }

    private func download(listening: Bool) {
        working = true; status = "Starting download…"
        UserDefaults.standard.removeObject(forKey: "localVoiceTTSDtype")
        Task {
            do {
                try await engine.prepare(listening: listening, speaking: true) { line in status = line }
                VoiceSettings.speaker = .local
                if listening { VoiceSettings.transcriber = .local }
                status = listening ? "Kokoro speaks and Whisper listens now." : "Kokoro speaks now. Listening stays with \(VoiceSettings.transcriber.title)."
            } catch { status = error.localizedDescription }
            working = false; refresh()
        }
    }

    private func describe(_ result: MacLocalVoiceEngine.Speed) -> String {
        func pace(_ value: Double?) -> String {
            guard let value else { return "not tested" }
            return String(format: "%.2f× real time", value) + (value < 0.5 ? " (instant)" : value < 1 ? " (good)" : " (slow: try a smaller model)")
        }
        var line = "Speaking: \(pace(result.speakingRTF)) on the \(result.device == "webgpu" ? "graphics chip" : "processor") · \(result.threads) core\(result.threads == 1 ? "" : "s")"
        if result.listeningRTF != nil { line += " · Listening: \(pace(result.listeningRTF)) · heard “\(result.heard)”" }
        return line
    }

    private func test() {
        working = true; speed = "Testing…"
        Task {
            do { speed = describe(try await engine.measure(listening: VoiceSettings.transcriber == .local)) } catch { speed = error.localizedDescription }
            working = false
        }
    }

    private func pickDevice() {
        working = true; speed = "Comparing the processor and the graphics chip…"
        Task {
            do { speed = describe(try await engine.pickFastestDevice()) } catch { speed = error.localizedDescription }
            working = false; refresh()
        }
    }

    private func preview() {
        working = true; status = nil
        let chosen = voice
        Task {
            VoiceSettings.kokoroVoice = chosen
            do {
                let data = try await engine.speak("Hi! This is how I sound when I talk to you.")
                PreviewSound.play(data)
            } catch { status = error.localizedDescription }
            working = false
        }
    }
}

/// Keeps the voice preview playing until the next one.
@MainActor
private enum PreviewSound {
    static var current: NSSound?
    static func play(_ data: Data) { current?.stop(); current = NSSound(data: data); current?.play() }
}

/// Settings → Voice: the same options as the gear in voice mode, in a sheet so its form scrolls on its own.
struct MacVoiceSettingsPage: View {
    @State private var open = false
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Voice mode listens and talks back hands-free. It keeps going when you open another Bot, and shows as a small card, full screen, or a small pill.")
                .foregroundStyle(MacTheme.secondary).fixedSize(horizontal: false, vertical: true)
            Text("Run it free and private with open-source models on this Mac (Whisper listens, Kokoro speaks), or use Apple’s voices or a cloud provider. Hold Space or the orb to keep talking as long as you like.")
                .foregroundStyle(MacTheme.secondary).fixedSize(horizontal: false, vertical: true)
            MacPillButton(title: "Open voice settings", prominent: true) { open = true }
        }
        .sheet(isPresented: $open) { VoiceSettingsView() }
    }
}
