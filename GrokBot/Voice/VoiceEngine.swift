import AVFoundation
import Foundation
import Speech
import SwiftUI

// Hands-free voice mode shared by the iPhone and Mac apps.
// Default engine: Apple on-device speech recognition + AVSpeechSynthesizer (no keys).
// Optional cloud engines (Groq / OpenAI / ElevenLabs) use keys stored in the Keychain.

enum VoiceProvider: String, CaseIterable, Identifiable, Sendable {
    case apple, groq, openAI, elevenLabs
    var id: String { rawValue }
    var title: String {
        switch self {
        case .apple: "Apple (free, on-device)"
        case .groq: "Groq"
        case .openAI: "OpenAI"
        case .elevenLabs: "ElevenLabs"
        }
    }
    var supportsTranscription: Bool { true }
    var supportsSpeech: Bool { self != .groq }
    var needsKey: Bool { self != .apple }
    static var transcribers: [VoiceProvider] { allCases.filter(\.supportsTranscription) }
    static var speakers: [VoiceProvider] { allCases.filter(\.supportsSpeech) }
}

enum VoiceSettings {
    static var transcriber: VoiceProvider {
        get { VoiceProvider(rawValue: UserDefaults.standard.string(forKey: "voiceTranscriber") ?? "") ?? .apple }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "voiceTranscriber") }
    }
    static var speaker: VoiceProvider {
        get { VoiceProvider(rawValue: UserDefaults.standard.string(forKey: "voiceSpeaker") ?? "") ?? .apple }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "voiceSpeaker") }
    }
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
            recognizer = SFSpeechRecognizer(locale: Locale.current) ?? SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
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
        partial = ""; level = 0; utterance = []; preRoll = []; inSpeech = false
        state = .idle
    }

    func resumeListening() {
        guard active else { return }
        partial = ""; utterance = []; inSpeech = false; bargeSeconds = 0
        state = .listening
        if transcriber == .apple { startRecognition() }
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
        guard transcriber != .apple, state == .listening || state == .speaking else { return }
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
                if Date().timeIntervalSince(lastVoice) > 1.0 { finishCloudUtterance() }
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
        silenceTimer = Timer.scheduledTimer(withTimeInterval: 1.3, repeats: false) { [weak self] _ in
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
        state = .speaking; partial = ""; bargeSeconds = 0; preRoll = []
        if transcriber == .apple { startRecognition() }
        let provider = VoiceSettings.speaker
        if provider != .apple, provider.supportsSpeech, !VoiceKeys.get(provider).isEmpty {
            do {
                let data = try await VoiceCloud.synthesize(text: text, provider: provider, key: VoiceKeys.get(provider))
                if state == .speaking { await play(data) }
            } catch {
                message = "\(provider.title) voice failed (\(error.localizedDescription)); using the built-in voice."
                if state == .speaking { await speakWithApple(text) }
            }
        } else {
            await speakWithApple(text)
        }
        if state == .speaking, active { resumeListening() }
    }

    func interrupt() {
        guard state == .speaking else { return }
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
        let language = Locale.current.identifier.replacingOccurrences(of: "_", with: "-")
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
            player = audio
            if !audio.play() { finishSpeechWait() }
        }
        player = nil
    }
}

enum VoiceWAV {
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

    func start(send: @escaping (String) async -> Bool, latestReply: @escaping () -> VoiceReply?) async {
        self.send = send; self.latestReply = latestReply
        session.onUtterance = { [weak self] text in self?.handle(text) }
        running = await session.begin()
    }

    func stop() {
        running = false; waiting?.cancel(); waiting = nil
        session.onUtterance = nil
        session.end()
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
            var waited = 0.0
            while running, !Task.isCancelled, waited < 180 {
                try? await Task.sleep(nanoseconds: 300_000_000); waited += 0.3
                if let reply = latestReply?(), reply.id != previous, reply.finished {
                    if reply.text.isEmpty { session.resumeListening() } else { await session.speak(reply.text) }
                    return
                }
            }
            if running { session.resumeListening() }
        }
    }
}
