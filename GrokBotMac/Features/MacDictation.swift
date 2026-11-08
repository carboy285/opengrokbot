import AVFoundation
import Speech
import SwiftUI

/// Hold-free dictation for the message box: tap the mic, talk, tap again. Uses Apple's on-device speech
/// recognition when it is available, so nothing is sent anywhere. The words appear in the message box as you speak.
@MainActor
final class MacDictation: ObservableObject {
    @Published private(set) var listening = false
    @Published var note: String?

    private let engine = AVAudioEngine()
    private var task: SFSpeechRecognitionTask?
    private var generation = 0
    private var base = ""
    private var deliver: ((String) -> Void)?

    func toggle(current: String, set: @escaping (String) -> Void) {
        if listening { stop(); return }
        note = nil
        Task { await begin(current: current, set: set) }
    }

    private func begin(current: String, set: @escaping (String) -> Void) async {
        guard await VoiceSession.requestAccess(needsSpeech: true) else {
            note = "Allow Microphone and Speech Recognition for OpenGrokBot in System Settings → Privacy & Security, then try again."
            return
        }
        guard let recognizer = SFSpeechRecognizer(locale: VoiceSettings.locale) ?? SFSpeechRecognizer(locale: Locale(identifier: "en-US")), recognizer.isAvailable else {
            note = "Speech recognition isn't available for this language right now."
            return
        }
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.addsPunctuation = true
        if recognizer.supportsOnDeviceRecognition { request.requiresOnDeviceRecognition = true }
        base = current.trimmingCharacters(in: .whitespacesAndNewlines)
        deliver = set
        generation += 1
        let mine = generation
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0 else { note = "No microphone was found."; return }
        input.removeTap(onBus: 0)
        Self.installTap(on: input, format: format, request: request)
        task = recognizer.recognitionTask(with: request, resultHandler: Self.handler { [weak self] text, done in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.heard(text, done: done, generation: mine) } }
        })
        engine.prepare()
        do { try engine.start(); listening = true } catch {
            note = "Couldn't start the microphone: \(error.localizedDescription)"
            teardown()
        }
    }

    nonisolated private static func installTap(on input: AVAudioInputNode, format: AVAudioFormat, request: SFSpeechAudioBufferRecognitionRequest) {
        let box = RequestBox(request)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in box.request.append(buffer) }
    }

    nonisolated private static func handler(deliver: @escaping @Sendable (String, Bool) -> Void) -> (SFSpeechRecognitionResult?, Error?) -> Void {
        { result, error in deliver(result?.bestTranscription.formattedString ?? "", (result?.isFinal ?? false) || error != nil) }
    }

    private func heard(_ text: String, done: Bool, generation current: Int) {
        guard current == generation else { return }
        if !text.isEmpty { deliver?(base.isEmpty ? text : base + " " + text) }
        if done { stop() }
    }

    func stop() {
        guard listening || task != nil else { return }
        generation += 1
        task?.finish()
        teardown()
    }

    private func teardown() {
        if engine.isRunning { engine.stop() }
        engine.inputNode.removeTap(onBus: 0)
        task = nil
        deliver = nil
        listening = false
    }
}

/// Carries the recognition request to the audio thread. The request is only appended to there, and is thread-safe for that.
private final class RequestBox: @unchecked Sendable {
    let request: SFSpeechAudioBufferRecognitionRequest
    init(_ request: SFSpeechAudioBufferRecognitionRequest) { self.request = request }
}
