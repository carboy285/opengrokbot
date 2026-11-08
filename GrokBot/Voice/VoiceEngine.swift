import AVFoundation
import Foundation
import Speech
import SwiftUI

// Hands-free voice mode shared by the iPhone and Mac apps.
// Default engine: Apple on-device speech recognition + AVSpeechSynthesizer (no keys).
// Optional cloud engines (Groq / OpenAI / ElevenLabs) use keys stored in the Keychain.

enum VoiceProvider: String, CaseIterable, Identifiable, Sendable {
    case apple, groq, openAI, elevenLabs, nvidiaNIM, nvidiaCloud, gemini
    var id: String { rawValue }
    var title: String {
        switch self {
        case .apple: "Apple (free, on-device)"
        case .groq: "Groq"
        case .openAI: "OpenAI"
        case .elevenLabs: "ElevenLabs"
        case .nvidiaNIM: "NVIDIA NIM (self-hosted)"
        case .nvidiaCloud: "NVIDIA Cloud (hosted Magpie)"
        case .gemini: "Google AI Studio (Gemini)"
        }
    }
    /// The NVIDIA and Gemini options here are speech output only.
    var supportsTranscription: Bool { self != .nvidiaNIM && self != .nvidiaCloud && self != .gemini }
    var supportsSpeech: Bool { true }
    var needsKey: Bool { self != .apple && self != .nvidiaNIM }
    /// A NIM you run yourself needs no key; a gateway in front of it may.
    var keyIsOptional: Bool { self == .nvidiaNIM }
    /// Longest text one speech request should carry. Longer replies are split at natural pauses.
    var maxSpeechCharacters: Int? {
        switch self {
        case .groq: 190
        case .nvidiaNIM, .nvidiaCloud: 400
        default: nil
        }
    }
    static var transcribers: [VoiceProvider] { allCases.filter(\.supportsTranscription) }
    static var speakers: [VoiceProvider] { allCases.filter(\.supportsSpeech) }
}

enum VoiceSettings {
    /// Voice choices that apply only while one Bot's voice chat is open. They never overwrite the saved app-wide settings.
    struct SessionOverride: Sendable, Equatable {
        var speaker: VoiceProvider?
        var speed: Double?
        var language: String?
        init(speaker: VoiceProvider? = nil, speed: Double? = nil, language: String? = nil) { self.speaker = speaker; self.speed = speed; self.language = language }
        init(_ voice: BotVoice?) {
            speaker = voice?.speaker.flatMap { VoiceProvider(rawValue: $0) }; speed = voice?.speed; language = voice?.language
        }
    }
    private final class OverrideBox: @unchecked Sendable {
        private let lock = NSLock(); private var stored: SessionOverride?
        var value: SessionOverride? { get { lock.lock(); defer { lock.unlock() }; return stored } set { lock.lock(); stored = newValue; lock.unlock() } }
    }
    private static let overrideBox = OverrideBox()
    static var sessionOverride: SessionOverride? { get { overrideBox.value } set { overrideBox.value = newValue } }

    static var transcriber: VoiceProvider {
        get { VoiceProvider(rawValue: UserDefaults.standard.string(forKey: "voiceTranscriber") ?? "") ?? .apple }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "voiceTranscriber") }
    }
    static var speaker: VoiceProvider {
        get { sessionOverride?.speaker ?? storedSpeaker }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "voiceSpeaker") }
    }
    /// The app-wide choice, ignoring any Bot's own voice. The settings screens show and save this one.
    static var storedSpeaker: VoiceProvider { VoiceProvider(rawValue: UserDefaults.standard.string(forKey: "voiceSpeaker") ?? "") ?? .apple }
    /// How fast replies are spoken: 0.75x to 1.5x. Applies to the built-in voice and to cloud audio.
    static var speed: Double {
        get { min(max(sessionOverride?.speed ?? storedSpeed, 0.75), 1.5) }
        set { UserDefaults.standard.set(min(max(newValue, 0.75), 1.5), forKey: "voiceSpeed") }
    }
    static var storedSpeed: Double { let value = UserDefaults.standard.double(forKey: "voiceSpeed"); return value == 0 ? 1.0 : min(max(value, 0.75), 1.5) }
    /// "auto" follows the system language; otherwise a BCP 47 code such as en-US. Used for listening and the built-in voice.
    static let languages: [(code: String, name: String)] = [("auto", "Auto-detect"), ("en-US", "English (US)"), ("en-GB", "English (UK)"), ("es-ES", "Spanish"), ("fr-FR", "French"), ("de-DE", "German"), ("it-IT", "Italian"), ("pt-BR", "Portuguese (Brazil)"), ("ja-JP", "Japanese"), ("ko-KR", "Korean"), ("zh-CN", "Chinese (Simplified)")]
    static var language: String {
        get { let value = sessionOverride?.language ?? storedLanguage; return languages.contains { $0.code == value } ? value : "auto" }
        set { UserDefaults.standard.set(newValue, forKey: "voiceLanguage") }
    }
    static var storedLanguage: String { let value = UserDefaults.standard.string(forKey: "voiceLanguage") ?? "auto"; return languages.contains { $0.code == value } ? value : "auto" }
    static var locale: Locale { language == "auto" ? Locale.current : Locale(identifier: language) }
    static let groqVoices = ["autumn", "diana", "hannah", "austin", "daniel", "troy"]
    static var groqVoice: String {
        get { UserDefaults.standard.string(forKey: "voiceGroqVoice").flatMap { groqVoices.contains($0) ? $0 : nil } ?? "autumn" }
        set { UserDefaults.standard.set(newValue, forKey: "voiceGroqVoice") }
    }
    /// A NVIDIA Magpie TTS NIM you run yourself (Docker, NVIDIA GPU). NVIDIA's hosted cloud API uses gRPC and is not supported here.
    static var nimBaseURL: String {
        get { UserDefaults.standard.string(forKey: "voiceNIMBaseURL") ?? "http://localhost:9000" }
        set { UserDefaults.standard.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: "voiceNIMBaseURL") }
    }
    static var nimVoice: String {
        get { UserDefaults.standard.string(forKey: "voiceNIMVoice") ?? "Magpie-Multilingual.EN-US.Aria" }
        set { UserDefaults.standard.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: "voiceNIMVoice") }
    }
    /// The synthesize endpoint for a base address, or nil if the address is not a plain http(s) server address.
    static func nimSynthesizeURL(_ base: String) -> URL? {
        let text = base.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count <= 300, var parts = URLComponents(string: text), let scheme = parts.scheme?.lowercased(), scheme == "http" || scheme == "https",
              let host = parts.host, !host.isEmpty, parts.user == nil, parts.password == nil, parts.query == nil, parts.fragment == nil else { return nil }
        parts.path = (parts.path.hasSuffix("/") ? String(parts.path.dropLast()) : parts.path) + "/v1/audio/synthesize"
        return parts.url
    }
    // Google AI Studio (Gemini speech)
    static let geminiVoices = ["Kore", "Puck", "Zephyr", "Charon", "Fenrir", "Aoede", "Leda", "Orus", "Callirrhoe", "Enceladus"]
    static var geminiModel: String {
        get { UserDefaults.standard.string(forKey: "voiceGeminiModel") ?? "gemini-2.5-flash-preview-tts" }
        set { UserDefaults.standard.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: "voiceGeminiModel") }
    }
    static var geminiVoice: String {
        get { UserDefaults.standard.string(forKey: "voiceGeminiVoice").flatMap { geminiVoices.contains($0) ? $0 : nil } ?? "Kore" }
        set { UserDefaults.standard.set(newValue, forKey: "voiceGeminiVoice") }
    }
    static var geminiBaseURL: String {
        get { UserDefaults.standard.string(forKey: "voiceGeminiBaseURL") ?? "https://generativelanguage.googleapis.com" }
        set { UserDefaults.standard.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: "voiceGeminiBaseURL") }
    }
    /// The generateContent address for a model, or nil unless the base is a plain https address and the model name is a simple identifier.
    static func geminiURL(base: String, model: String) -> URL? {
        let name = model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard name.range(of: "^[A-Za-z0-9._-]{1,80}$", options: .regularExpression) != nil,
              var parts = URLComponents(string: base.trimmingCharacters(in: .whitespacesAndNewlines)), parts.scheme?.lowercased() == "https",
              let host = parts.host, !host.isEmpty, parts.user == nil, parts.password == nil, parts.query == nil, parts.fragment == nil else { return nil }
        parts.path = (parts.path.hasSuffix("/") ? String(parts.path.dropLast()) : parts.path) + "/v1beta/models/\(name):generateContent"
        return parts.url
    }

    // NVIDIA Cloud (hosted Magpie over gRPC)
    static var nvidiaCloudServer: String {
        get { UserDefaults.standard.string(forKey: "voiceNVCServer") ?? "grpc.nvcf.nvidia.com:443" }
        set { UserDefaults.standard.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: "voiceNVCServer") }
    }
    static var nvidiaCloudFunctionID: String {
        get { UserDefaults.standard.string(forKey: "voiceNVCFunction") ?? "877104f7-e885-42b9-8de8-f6e4c6303969" }
        set { UserDefaults.standard.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: "voiceNVCFunction") }
    }
    static var nvidiaCloudVoice: String {
        get { UserDefaults.standard.string(forKey: "voiceNVCVoice") ?? "Magpie-Multilingual.EN-US.Aria" }
        set { UserDefaults.standard.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: "voiceNVCVoice") }
    }
    /// The gRPC method address for a server such as "grpc.nvcf.nvidia.com:443" (an https:// prefix is accepted), or nil if it is not a plain host and port.
    static func nvidiaCloudURL(_ server: String) -> URL? {
        var text = server.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.lowercased().hasPrefix("https://") { text = String(text.dropFirst(8)) }
        if text.hasSuffix("/") { text = String(text.dropLast()) }
        guard text.range(of: "^[A-Za-z0-9.-]{1,200}(:[0-9]{1,5})?$", options: .regularExpression) != nil, text.contains(".") else { return nil }
        return URL(string: "https://\(text)/riva.tts.RivaSpeechSynthesis/Synthesize")
    }
    static func isValidFunctionID(_ id: String) -> Bool { id.trimmingCharacters(in: .whitespacesAndNewlines).range(of: "^[A-Za-z0-9-]{8,64}$", options: .regularExpression) != nil }
    static var elevenLabsVoiceID: String {
        get { UserDefaults.standard.string(forKey: "voiceElevenLabsVoiceID") ?? "21m00Tcm4TlvDq8ikWAM" }
        set { UserDefaults.standard.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: "voiceElevenLabsVoiceID") }
    }
    static var allowTalkOver: Bool {
        get { UserDefaults.standard.object(forKey: "voiceTalkOver") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "voiceTalkOver") }
    }
}

/// Provider API keys live in the Keychain, never in the repository or UserDefaults.
enum VoiceKeys {
    private static func query(_ provider: VoiceProvider) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: "OpenGrokBot.voice",
         kSecAttrAccount as String: provider.rawValue]
    }
    static func get(_ provider: VoiceProvider) -> String {
        var q = query(provider)
        q[kSecReturnData as String] = true; q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let data = out as? Data else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }
    static func set(_ value: String, for provider: VoiceProvider) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        SecItemDelete(query(provider) as CFDictionary)
        guard !trimmed.isEmpty else { return }
        var q = query(provider)
        q[kSecValueData as String] = Data(trimmed.utf8)
        q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(q as CFDictionary, nil)
    }
}

enum VoiceText {
    /// Splits a reply that is still streaming into speakable pieces. Returns the text from `offset` up to the
    /// last finished sentence (or everything once `final`), never cutting inside a ``` code block.
    static func nextChunk(_ text: String, from offset: Int, final: Bool, eager: Bool = false) -> (chunk: String, next: Int) {
        let chars = Array(text)
        guard offset < chars.count else { return ("", max(offset, chars.count)) }
        if final { return (String(chars[offset...]), chars.count) }
        var end = offset
        var i = chars.count - 2
        while i >= offset {
            if ".!?\n".contains(chars[i]) && chars[i + 1].isWhitespace { end = i + 1; break }
            i -= 1
        }
        if end == offset, eager {
            // Nothing has been spoken yet: start at the first natural pause instead of waiting for a whole sentence.
            var j = offset + 14
            while j < chars.count - 1 {
                if ",;:—".contains(chars[j]) && chars[j + 1].isWhitespace { end = j + 1; break }
                j += 1
            }
            // No pause yet but a good run of words: start at the last complete word instead of waiting.
            if end == offset, chars.count - offset >= 48, let space = chars[offset..<(chars.count - 1)].lastIndex(of: " "), space - offset >= 30 { end = space + 1 }
        }
        guard end > offset else { return ("", offset) }
        let candidate = String(chars[..<end])
        let fences = candidate.components(separatedBy: "```").count - 1
        if fences % 2 == 1, let open = candidate.range(of: "```", options: .backwards) {
            end = candidate.distance(from: candidate.startIndex, to: open.lowerBound)
            guard end > offset else { return ("", offset) }
        }
        return (String(chars[offset..<end]), end)
    }

    /// Splits text into pieces of at most `maxLength` characters, preferring sentence ends, then commas, then spaces.
    static func split(_ text: String, maxLength: Int) -> [String] {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return [] }
        guard maxLength > 0, clean.count > maxLength else { return [clean] }
        var parts: [String] = []
        var rest = Substring(clean)
        while rest.count > maxLength {
            let window = rest.prefix(maxLength)
            func cut(_ marks: String, minimum: Int) -> String.Index? {
                guard let found = window.lastIndex(where: { marks.contains($0) }) else { return nil }
                let after = window.index(after: found)
                return window.distance(from: window.startIndex, to: after) >= minimum ? after : nil
            }
            let end = cut(".!?", minimum: maxLength / 3) ?? cut(",;:", minimum: maxLength / 3) ?? cut(" ", minimum: 1) ?? window.endIndex
            let piece = rest[..<end].trimmingCharacters(in: .whitespacesAndNewlines)
            if !piece.isEmpty { parts.append(piece) }
            rest = rest[end...].drop(while: { $0.isWhitespace })
        }
        if !rest.isEmpty { parts.append(String(rest)) }
        return parts
    }

    /// Makes a Bot reply pleasant to hear: no code blocks, links or markdown symbols.
    static func speakable(_ raw: String) -> String {
        var text = raw
        if let fence = try? NSRegularExpression(pattern: "```[\\s\\S]*?(```|$)") {
            text = fence.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: " (code omitted) ")
        }
        if let url = try? NSRegularExpression(pattern: "https?://\\S+") {
            text = url.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: " link ")
        }
        text = text.replacingOccurrences(of: "[`*_#>|~]", with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        return String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(4000))
    }
}

private final class RecognitionSink: @unchecked Sendable {
    private let lock = NSLock()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    func set(_ value: SFSpeechAudioBufferRecognitionRequest?) { lock.lock(); request = value; lock.unlock() }
    func append(_ buffer: AVAudioPCMBuffer) { lock.lock(); let current = request; lock.unlock(); current?.append(buffer) }
}

private final class PlayerDelegate: NSObject, AVAudioPlayerDelegate {
    var finished: (@Sendable () -> Void)?
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) { finished?() }
    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) { finished?() }
}

private final class SpeechDelegate: NSObject, AVSpeechSynthesizerDelegate {
    var finished: (@Sendable () -> Void)?
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) { finished?() }
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) { finished?() }
}

@MainActor
final class VoiceSession: ObservableObject {
    enum State: Equatable { case idle, listening, thinking, speaking }
    @Published private(set) var state: State = .idle
    @Published private(set) var partial = ""
    @Published private(set) var level: Float = 0
    @Published var message: String?
    /// While muted nothing you say is heard. The Bot can still speak.
    @Published private(set) var muted = false
    /// Called with each finished thing the user said. The owner sends it and later calls `speak`.
    var onUtterance: ((String) -> Void)?

    private let engine = AVAudioEngine()
    private let sink = RecognitionSink()
    private var recognizer: SFSpeechRecognizer?
    private var task: SFSpeechRecognitionTask?
    private var generation = 0
    private var silenceTimer: Timer?
    private var active = false
    private var transcriber: VoiceProvider = .apple
    private let synthesizer = AVSpeechSynthesizer()
    private let speechDelegate = SpeechDelegate()
    private let playerDelegate = PlayerDelegate()
    private var player: AVAudioPlayer?
    private var speechDone: CheckedContinuation<Void, Never>?
    private var speechQueue: [String] = []
    private var draining = false
    private var streamFinished = false
    // Cloud voice-activity detection
    private var preRoll: [Float] = []
    private var utterance: [Float] = []
    private var inSpeech = false
    private var lastVoice = Date()
    private var bargeSeconds = 0.0
    private var sampleRate = 16_000.0

    private var usingHeadset: Bool {
        #if os(iOS)
        let headset: Set<AVAudioSession.Port> = [.headphones, .bluetoothA2DP, .bluetoothHFP, .bluetoothLE, .usbAudio]
        return AVAudioSession.sharedInstance().currentRoute.outputs.contains { headset.contains($0.portType) }
        #else
        return false
        #endif
    }

    // MARK: Lifecycle

    func begin() async -> Bool {
        guard !active else { return true }
        transcriber = VoiceSettings.transcriber
        if transcriber.needsKey, VoiceKeys.get(transcriber).isEmpty {
            message = "Add your \(transcriber.title) key in voice settings, or switch listening back to Apple."; return false
        }
        guard await Self.requestAccess(needsSpeech: transcriber == .apple) else {
            message = "Allow microphone and speech recognition for OpenGrokBot in system settings."; return false
        }
        if transcriber == .apple {
            recognizer = SFSpeechRecognizer(locale: VoiceSettings.locale) ?? SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
            Task.detached { await VoiceCloud.warmUp(VoiceSettings.speaker) }
            guard recognizer?.isAvailable == true else { message = "Speech recognition isn’t available right now."; return false }
        }
        do { try startEngine() } catch { message = "The microphone could not be started: \(error.localizedDescription)"; return false }
        active = true; message = nil
        resumeListening()
        return true
    }

    func end() {
        active = false
        silenceTimer?.invalidate(); silenceTimer = nil
        generation += 1
        task?.cancel(); task = nil; sink.set(nil)
        stopOutput()
        if engine.isRunning { engine.stop() }
        engine.inputNode.removeTap(onBus: 0)
        try? engine.inputNode.setVoiceProcessingEnabled(false)
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        #endif
        partial = ""; level = 0; utterance = []; preRoll = []; inSpeech = false; speechQueue = []; muted = false
        state = .idle
    }

    func resumeListening() {
        guard active else { return }
        partial = ""; utterance = []; inSpeech = false; bargeSeconds = 0
        state = .listening
        if transcriber == .apple, !muted { startRecognition() }
    }

    func setMuted(_ on: Bool) {
        guard active, on != muted else { return }
        muted = on
        if on {
            silenceTimer?.invalidate(); silenceTimer = nil
            generation += 1; task?.cancel(); task = nil; sink.set(nil)
            partial = ""; utterance = []; preRoll = []; inSpeech = false
        } else if state == .listening, transcriber == .apple { startRecognition() }
    }

    nonisolated static func requestAccess(needsSpeech: Bool) async -> Bool {
        if needsSpeech {
            let allowed = await withCheckedContinuation { (c: CheckedContinuation<Bool, Never>) in
                SFSpeechRecognizer.requestAuthorization { c.resume(returning: $0 == .authorized) }
            }
            if !allowed { return false }
        }
        #if os(iOS)
        return await AVAudioApplication.requestRecordPermission()
        #else
        return await AVCaptureDevice.requestAccess(for: .audio)
        #endif
    }

    // MARK: Audio engine

    private func startEngine() throws {
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .voiceChat, options: [.defaultToSpeaker, .allowBluetooth, .allowBluetoothA2DP])
        try session.setActive(true)
        #endif
        let input = engine.inputNode
        // Echo cancellation lets you talk over the Bot without it hearing itself.
        try? input.setVoiceProcessingEnabled(true)
        let format = input.outputFormat(forBus: 0)
        sampleRate = format.sampleRate > 0 ? format.sampleRate : 16_000
        input.removeTap(onBus: 0)
        let block = Self.makeTap(sink: sink, wantsSamples: transcriber != .apple) { [weak self] rms, samples, count in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.consume(level: rms, samples: samples, count: count) } }
        }
        input.installTap(onBus: 0, bufferSize: 2048, format: format, block: block)
        engine.prepare()
        try engine.start()
    }

    /// Built outside the main actor: the audio system calls this block on its own real-time thread.
    nonisolated private static func makeTap(sink: RecognitionSink, wantsSamples: Bool, deliver: @escaping @Sendable (Float, [Float], Int) -> Void) -> AVAudioNodeTapBlock {
        return { buffer, _ in
            sink.append(buffer)
            guard let channel = buffer.floatChannelData?[0] else { return }
            let count = Int(buffer.frameLength)
            var sum: Float = 0
            for i in 0..<count { sum += channel[i] * channel[i] }
            let rms = count > 0 ? (sum / Float(count)).squareRoot() : 0
            let samples = wantsSamples ? Array(UnsafeBufferPointer(start: channel, count: count)) : []
            deliver(rms, samples, count)
        }
    }

    /// Built outside the main actor: Speech calls this from its own queue.
    nonisolated private static func makeRecognitionHandler(deliver: @escaping @Sendable (String, Bool) -> Void) -> (SFSpeechRecognitionResult?, Error?) -> Void {
        return { result, error in
            deliver(result?.bestTranscription.formattedString ?? "", (result?.isFinal ?? false) || error != nil)
        }
    }

    private func consume(level rms: Float, samples: [Float], count: Int) {
        guard active else { return }
        level = max(rms * 8, level * 0.8)
        guard transcriber != .apple, !muted, state == .listening || state == .speaking else { return }
        let seconds = Double(count) / sampleRate
        let speakingNow = state == .speaking
        let threshold: Float = speakingNow ? (usingHeadset ? 0.03 : 0.08) : 0.012
        if rms > threshold {
            if speakingNow {
                bargeSeconds += seconds
                if VoiceSettings.allowTalkOver, bargeSeconds >= 0.4 { interrupt(); inSpeech = true; utterance = preRoll + samples; lastVoice = Date() }
                else { preRoll.append(contentsOf: samples) }
                return
            }
            if !inSpeech { inSpeech = true; utterance = preRoll }
            utterance.append(contentsOf: samples); lastVoice = Date()
            if utterance.count > Int(sampleRate * 60) { finishCloudUtterance() }
        } else {
            bargeSeconds = 0
            if inSpeech {
                utterance.append(contentsOf: samples)
                if Date().timeIntervalSince(lastVoice) > 0.5 { finishCloudUtterance() }
            }
        }
        if !inSpeech {
            preRoll.append(contentsOf: samples)
            let maxRoll = Int(sampleRate * 0.4)
            if preRoll.count > maxRoll { preRoll.removeFirst(preRoll.count - maxRoll) }
        }
    }

    private func finishCloudUtterance() {
        let recorded = utterance
        inSpeech = false; utterance = []; preRoll = []
        guard Double(recorded.count) / sampleRate > 0.4 else { return }
        state = .thinking; partial = "Transcribing…"
        let provider = transcriber, key = VoiceKeys.get(transcriber), rate = sampleRate
        Task {
            do {
                let wav = VoiceWAV.encode(recorded, sampleRate: rate)
                let text = try await VoiceCloud.transcribe(wav: wav, provider: provider, key: key)
                guard active else { return }
                partial = ""
                if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { resumeListening() } else { onUtterance?(text) }
            } catch {
                guard active else { return }
                message = error.localizedDescription; resumeListening()
            }
        }
    }

    // MARK: Apple speech recognition

    private func startRecognition() {
        guard active, transcriber == .apple, let recognizer else { return }
        task?.cancel(); generation += 1
        let current = generation
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        if recognizer.supportsOnDeviceRecognition { request.requiresOnDeviceRecognition = true }
        request.addsPunctuation = true
        sink.set(request)
        let handler = Self.makeRecognitionHandler { [weak self] text, done in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.recognized(text, done: done, generation: current) } }
        }
        task = recognizer.recognitionTask(with: request, resultHandler: handler)
    }

    private func recognized(_ text: String, done: Bool, generation current: Int) {
        guard active, current == generation else { return }
        let words = text.split(separator: " ").count
        if state == .speaking {
            // Ignore speaker echo unless it clearly looks like you talking over the Bot.
            if VoiceSettings.allowTalkOver, words >= (usingHeadset ? 2 : 3) { interrupt(); partial = text; armSilenceTimer(text) }
            else if done { startRecognition() }
            return
        }
        guard state == .listening else { return }
        if !text.isEmpty { partial = text; armSilenceTimer(text) }
        if done { if text.isEmpty { startRecognition() } else { commit(text) } }
    }

    private func armSilenceTimer(_ text: String) {
        silenceTimer?.invalidate()
        // A finished sentence is a likely stopping point, so commit sooner; otherwise give a short pause.
        let finished = text.trimmingCharacters(in: .whitespaces).last.map { ".?!".contains($0) } ?? false
        silenceTimer = Timer.scheduledTimer(withTimeInterval: finished ? 0.4 : 0.6, repeats: false) { [weak self] _ in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.commit(text) } }
        }
    }

    private func commit(_ text: String) {
        silenceTimer?.invalidate(); silenceTimer = nil
        guard state == .listening || state == .speaking else { return }
        let spoken = text.trimmingCharacters(in: .whitespacesAndNewlines)
        generation += 1; task?.cancel(); task = nil; sink.set(nil)
        guard !spoken.isEmpty else { resumeListening(); return }
        state = .thinking; partial = spoken
        onUtterance?(spoken)
    }

    // MARK: Speaking

    func speak(_ raw: String) async {
        let text = VoiceText.speakable(raw)
        guard active else { return }
        guard !text.isEmpty else { resumeListening(); return }
        beginSpeaking(); enqueue(text); endSpeaking()
    }

    /// Starts a spoken reply that arrives in pieces. Call `enqueue` for each piece and `endSpeaking` at the end.
    func beginSpeaking() {
        guard active else { return }
        state = .speaking; partial = ""; bargeSeconds = 0; preRoll = []
        speechQueue = []; streamFinished = false
        if transcriber == .apple, !muted { startRecognition() }
    }

    func enqueue(_ text: String) {
        guard active, state == .speaking, !text.isEmpty else { return }
        let limit = VoiceSettings.speaker.maxSpeechCharacters
        speechQueue.append(contentsOf: limit.map { VoiceText.split(text, maxLength: $0) } ?? [text])
        if !draining { Task { await drain() } }
    }

    func endSpeaking() {
        streamFinished = true
        if !draining, state == .speaking, active { resumeListening() }
    }

    /// One piece of speech: cloud audio that is already being fetched, or nil to use the on-device voice.
    private struct Fetch {
        let text: String
        let audio: Task<Data, Error>?
        let provider: VoiceProvider
    }

    /// Starts fetching audio for a piece right away, so the next sentence is ready when the current one ends.
    private func fetch(_ text: String) -> Fetch {
        let provider = VoiceSettings.speaker
        let key = VoiceKeys.get(provider)
        guard provider != .apple, provider.supportsSpeech, provider.keyIsOptional || !key.isEmpty else { return Fetch(text: text, audio: nil, provider: provider) }
        return Fetch(text: text, audio: Task { try await VoiceCloud.synthesize(text: text, provider: provider, key: key) }, provider: provider)
    }

    private func drain() async {
        draining = true
        // Up to three pieces are fetched at once, in order, so the next sentence is ready before the current one ends.
        var pipeline: [Fetch] = []
        while state == .speaking, active {
            while pipeline.count < 3, !speechQueue.isEmpty { pipeline.append(fetch(speechQueue.removeFirst())) }
            guard !pipeline.isEmpty else { break }
            await speakPiece(pipeline.removeFirst())
        }
        for item in pipeline { item.audio?.cancel() }
        draining = false
        if state == .speaking, active, streamFinished, speechQueue.isEmpty { resumeListening() }
    }

    private func speakPiece(_ item: Fetch) async {
        guard let audio = item.audio else { await speakWithApple(item.text); return }
        do {
            let data = try await audio.value
            if state == .speaking { await play(data) }
        } catch {
            message = "\(item.provider.title) voice failed (\(error.localizedDescription)); using the built-in voice."
            if state == .speaking { await speakWithApple(item.text) }
        }
    }

    func interrupt() {
        guard state == .speaking else { return }
        speechQueue = []
        stopOutput()
        state = .listening
    }

    private func stopOutput() {
        synthesizer.stopSpeaking(at: .immediate)
        player?.stop(); player = nil
        finishSpeechWait()
    }

    private func finishSpeechWait() {
        let pending = speechDone; speechDone = nil; pending?.resume()
    }

    private func speakWithApple(_ text: String) async {
        let utterance = AVSpeechUtterance(string: text)
        let language = VoiceSettings.locale.identifier.replacingOccurrences(of: "_", with: "-")
        utterance.rate = min(max(AVSpeechUtteranceDefaultSpeechRate * Float(VoiceSettings.speed), AVSpeechUtteranceMinimumSpeechRate), AVSpeechUtteranceMaximumSpeechRate)
        utterance.preUtteranceDelay = 0
        let matching = AVSpeechSynthesisVoice.speechVoices().filter { $0.language.hasPrefix(String(language.prefix(2))) }
        utterance.voice = matching.max { $0.quality.rawValue < $1.quality.rawValue } ?? AVSpeechSynthesisVoice(language: language)
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            speechDone = c
            speechDelegate.finished = { [weak self] in DispatchQueue.main.async { MainActor.assumeIsolated { self?.finishSpeechWait() } } }
            synthesizer.delegate = speechDelegate
            synthesizer.speak(utterance)
        }
    }

    private func play(_ data: Data) async {
        guard let audio = try? AVAudioPlayer(data: data) else { message = "The voice reply couldn’t be played."; return }
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            speechDone = c
            playerDelegate.finished = { [weak self] in DispatchQueue.main.async { MainActor.assumeIsolated { self?.finishSpeechWait() } } }
            audio.delegate = playerDelegate
            audio.enableRate = true; audio.rate = Float(VoiceSettings.speed)
            player = audio
            if !audio.play() { finishSpeechWait() }
        }
        player = nil
    }
}

enum VoiceWAV {
    /// Wraps raw 16-bit mono little-endian PCM (as returned by Gemini and NVIDIA speech) in a WAV header so it can be played.
    static func wrap(pcm: Data, sampleRate: Int) -> Data {
        var data = Data()
        func put32(_ v: UInt32) { var x = v.littleEndian; data.append(Data(bytes: &x, count: 4)) }
        func put16(_ v: UInt16) { var x = v.littleEndian; data.append(Data(bytes: &x, count: 2)) }
        data.append(contentsOf: Array("RIFF".utf8)); put32(UInt32(36 + pcm.count))
        data.append(contentsOf: Array("WAVEfmt ".utf8)); put32(16); put16(1); put16(1)
        put32(UInt32(sampleRate)); put32(UInt32(sampleRate * 2)); put16(2); put16(16)
        data.append(contentsOf: Array("data".utf8)); put32(UInt32(pcm.count))
        data.append(pcm)
        return data
    }

    /// 16-bit mono PCM at 16 kHz, which every transcription provider accepts.
    static func encode(_ samples: [Float], sampleRate: Double) -> Data {
        let target = 16_000.0
        let ratio = max(1, sampleRate / target)
        let outCount = Int(Double(samples.count) / ratio)
        var pcm = [Int16](); pcm.reserveCapacity(outCount)
        for i in 0..<outCount {
            let start = Int(Double(i) * ratio), end = min(samples.count, max(start + 1, Int(Double(i + 1) * ratio)))
            var sum: Float = 0
            for j in start..<end { sum += samples[j] }
            let value = max(-1, min(1, sum / Float(end - start)))
            pcm.append(Int16(value * Float(Int16.max)))
        }
        var data = Data()
        func put32(_ v: UInt32) { var x = v.littleEndian; data.append(Data(bytes: &x, count: 4)) }
        func put16(_ v: UInt16) { var x = v.littleEndian; data.append(Data(bytes: &x, count: 2)) }
        let bytes = UInt32(pcm.count * 2)
        data.append(contentsOf: Array("RIFF".utf8)); put32(36 + bytes)
        data.append(contentsOf: Array("WAVEfmt ".utf8)); put32(16); put16(1); put16(1)
        put32(16_000); put32(32_000); put16(2); put16(16)
        data.append(contentsOf: Array("data".utf8)); put32(bytes)
        pcm.withUnsafeBufferPointer { data.append(Data(buffer: $0)) }
        return data
    }
}

struct VoiceReply { var id: UUID; var text: String; var finished: Bool }

/// Drives the hands-free loop: listen → send to the Bot → wait for the reply → speak it → listen again.
@MainActor
final class VoiceConversation: ObservableObject {
    let session = VoiceSession()
    private var send: ((String) async -> Bool)?
    private var latestReply: (() -> VoiceReply?)?
    private var running = false
    private var waiting: Task<Void, Never>?

    var isRunning: Bool { running }

    private var stopReply: (() -> Void)?

    func start(botVoice: BotVoice? = nil, send: @escaping (String) async -> Bool, latestReply: @escaping () -> VoiceReply?, stopReply: (() -> Void)? = nil) async {
        VoiceSettings.sessionOverride = botVoice.map { VoiceSettings.SessionOverride($0) }
        self.send = send; self.latestReply = latestReply; self.stopReply = stopReply
        session.onUtterance = { [weak self] text in self?.handle(text) }
        running = await session.begin()
    }

    func stop() {
        running = false; waiting?.cancel(); waiting = nil
        session.onUtterance = nil
        session.end()
        VoiceSettings.sessionOverride = nil
    }

    private func handle(_ text: String) {
        let previous = latestReply?()?.id
        waiting?.cancel()
        waiting = Task { [weak self] in
            guard let self, let send = self.send else { return }
            guard await send(text) else {
                session.message = "That message couldn’t be sent. Check the Bot and try again."
                session.resumeListening(); return
            }
            // Speak finished sentences while the reply is still being written.
            var offset = 0, started = false, waited = 0.0
            while running, !Task.isCancelled, waited < 180 {
                try? await Task.sleep(nanoseconds: 40_000_000); waited += 0.04
                guard let reply = latestReply?(), reply.id != previous else { continue }
                if started, session.state != .speaking {
                    // You talked over the Bot: stop generating so your next message can be sent.
                    if !reply.finished { stopReply?() }
                    return
                }
                let piece = VoiceText.nextChunk(reply.text, from: offset, final: reply.finished, eager: !started)
                offset = piece.next
                let spoken = VoiceText.speakable(piece.chunk)
                if !spoken.isEmpty {
                    if !started { session.beginSpeaking(); started = true }
                    session.enqueue(spoken)
                }
                if reply.finished {
                    if started { session.endSpeaking() } else { session.resumeListening() }
                    return
                }
            }
            if running { if started { session.endSpeaking() } else { session.resumeListening() } }
        }
    }
}
