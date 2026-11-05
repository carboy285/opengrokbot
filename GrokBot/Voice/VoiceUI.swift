import SwiftUI

/// Hands-free voice mode: a compact card that floats over the chat, with an orb, a live waveform and four round controls
/// (voice settings, captions, mute, end). It follows the app's theme and the Bot's color. On the Mac it can be dragged anywhere
/// (grab the top of the card) and remembers where you left it; on iPhone it sits just under the agent's name.
struct VoiceModeView: View {
    @ObservedObject var conversation: VoiceConversation
    let botName: String
    let tint: Color
    let ink: Color
    let close: () -> Void
    @State private var showSettings = false
    @State private var showCaptions = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    #if os(macOS)
    @AppStorage("voiceCardX") private var savedX = 0.0
    @AppStorage("voiceCardY") private var savedY = 0.0
    @State private var drag = CGSize.zero
    #endif

    private var session: VoiceSession { conversation.session }
    private static let danger = Color(red: 0.92, green: 0.24, blue: 0.24)

    private var status: String {
        if session.muted { return "Muted" }
        switch session.state {
        case .idle: return "Starting…"
        case .listening: return "Listening…"
        case .thinking: return "Thinking…"
        case .speaking: return "Speaking · tap the orb to interrupt"
        }
    }
    private var caption: String {
        if let message = session.message { return message }
        return session.partial.isEmpty ? status : session.partial
    }
    private var border: Color { session.state == .listening && !session.muted ? tint.opacity(0.55) : Color.primary.opacity(0.12) }

    var body: some View {
        GeometryReader { proxy in
            VStack(spacing: 0) {
                card(in: proxy.size)
                    #if os(macOS)
                    .offset(cardOffset(in: proxy.size))
                    #endif
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .sheet(isPresented: $showSettings) { VoiceSettingsView() }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Voice mode with \(botName)")
    }

    private func card(in size: CGSize) -> some View {
        VStack(spacing: 12) {
            #if os(macOS)
            grip.gesture(dragGesture(in: size))
            #endif
            HStack(spacing: 14) {
                orb
                VoiceWaveform(state: session.state, level: session.level, muted: session.muted, reduceMotion: reduceMotion, color: tint).frame(height: 38)
            }
            #if os(macOS)
            .gesture(dragGesture(in: size))
            #endif
            if showCaptions {
                Text(caption).font(.system(size: 13)).lineLimit(2).multilineTextAlignment(.leading)
                    .foregroundStyle(session.message == nil ? Color.secondary : Color.orange)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityLabel(session.partial.isEmpty ? status : "You said: " + session.partial)
            }
            HStack(spacing: 12) {
                control("gearshape", label: "Voice settings") { showSettings = true }
                Spacer(minLength: 0)
                control("bubble.left", label: showCaptions ? "Hide captions" : "Show captions", highlighted: showCaptions) { showCaptions.toggle() }
                Spacer(minLength: 0)
                control(session.muted ? "mic.slash.fill" : "mic.fill", label: session.muted ? "Unmute microphone" : "Mute microphone", highlighted: session.muted) { session.setMuted(!session.muted) }
                Spacer(minLength: 0)
                control("xmark", label: "End voice mode", danger: true, action: close)
            }
        }
        .padding(16)
        .frame(maxWidth: 440)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).strokeBorder(border, lineWidth: 1))
        .shadow(color: .black.opacity(0.28), radius: 22, y: 10)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.25), value: border)
        .padding(.top, 8).padding(.horizontal, 16)
    }

    private var orb: some View {
        Button { if session.state == .speaking { session.interrupt() } } label: {
            ZStack {
                Circle().fill(LinearGradient(colors: [tint.opacity(0.95), tint.opacity(0.6)], startPoint: .top, endPoint: .bottom)).frame(width: 46, height: 46)
                HStack(spacing: 5) {
                    Capsule().fill(ink).frame(width: 5, height: 15)
                    Capsule().fill(ink).frame(width: 5, height: 15)
                }
            }
            .scaleEffect(reduceMotion ? 1 : 1 + CGFloat(min(session.level, 1)) * 0.12)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: session.level)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(status)
        .accessibilityHint(session.state == .speaking ? "Stops the spoken reply" : "")
    }

    private func control(_ symbol: String, label: String, highlighted: Bool = false, danger: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 16, weight: .medium))
                .foregroundStyle(danger ? Color.white : Color.primary.opacity(0.85))
                .frame(width: 46, height: 46)
                .background(danger ? Self.danger : Color.primary.opacity(highlighted ? 0.18 : 0.08), in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    #if os(macOS)
    /// A handle at the top of the card. Dragging it (or the orb and waveform row) moves the whole card.
    private var grip: some View {
        Capsule().fill(Color.primary.opacity(0.25)).frame(width: 38, height: 4)
            .frame(maxWidth: .infinity, minHeight: 12).contentShape(Rectangle())
            .accessibilityLabel("Drag to move the voice card").accessibilityAddTraits(.isButton)
    }
    private func clamped(_ x: Double, _ y: Double, in size: CGSize) -> CGSize {
        let width = min(440, size.width - 32)
        let maxX = max(0, (size.width - width) / 2 - 8)
        return CGSize(width: min(max(x, -maxX), maxX), height: min(max(y, 0), max(0, size.height - 200)))
    }
    private func cardOffset(in size: CGSize) -> CGSize { clamped(savedX + drag.width, savedY + drag.height, in: size) }
    private func dragGesture(in size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 3, coordinateSpace: .global)
            .onChanged { drag = $0.translation }
            .onEnded { value in
                let end = clamped(savedX + value.translation.width, savedY + value.translation.height, in: size)
                savedX = end.width; savedY = end.height; drag = .zero
            }
    }
    #endif
}

/// Bars that move with your voice while listening, ripple while the Bot speaks, and breathe while it thinks.
struct VoiceWaveform: View {
    let state: VoiceSession.State
    let level: Float
    let muted: Bool
    let reduceMotion: Bool
    var color: Color = Color(red: 0.43, green: 0.31, blue: 0.95)
    private static let bars = 32

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: reduceMotion)) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            HStack(spacing: 3) {
                ForEach(0..<Self.bars, id: \.self) { index in
                    Capsule().fill(barColor).frame(width: 3, height: height(index, time))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(maxHeight: .infinity)
        }
        .accessibilityHidden(true)
    }

    private var barColor: Color { muted ? Color.secondary.opacity(0.4) : color.opacity(state == .idle ? 0.35 : 0.9) }

    private func height(_ index: Int, _ time: Double) -> CGFloat {
        let low: CGFloat = 4, high: CGFloat = 36
        let phase = Double(index) * 0.55
        let bump = 0.45 + 0.55 * sin(Double.pi * Double(index) / Double(Self.bars - 1))
        let wave = abs(sin(time * 6 + phase))
        switch state {
        case .listening: return muted ? low : low + CGFloat(min(Double(level), 1) * (0.35 + 0.65 * wave)) * (high - low)
        case .speaking: return low + CGFloat(0.55 * (0.4 + 0.6 * abs(sin(time * 5 + phase))) * bump) * (high - low)
        case .thinking: return low + CGFloat(0.5 + 0.5 * sin(time * 3 + phase)) * 6
        case .idle: return low
        }
    }
}

struct VoiceSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var transcriber = VoiceSettings.transcriber
    @State private var speaker = VoiceSettings.speaker
    @State private var talkOver = VoiceSettings.allowTalkOver
    @State private var voiceID = VoiceSettings.elevenLabsVoiceID
    @State private var groqVoice = VoiceSettings.groqVoice
    @State private var nimURL = VoiceSettings.nimBaseURL
    @State private var nimVoice = VoiceSettings.nimVoice
    @State private var geminiModel = VoiceSettings.geminiModel
    @State private var geminiVoice = VoiceSettings.geminiVoice
    @State private var geminiBase = VoiceSettings.geminiBaseURL
    @State private var cloudServer = VoiceSettings.nvidiaCloudServer
    @State private var cloudFunction = VoiceSettings.nvidiaCloudFunctionID
    @State private var cloudVoice = VoiceSettings.nvidiaCloudVoice
    @State private var keys: [VoiceProvider: String] = Dictionary(uniqueKeysWithValues: VoiceProvider.allCases.map { ($0, VoiceKeys.get($0)) })

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Listening", selection: $transcriber) { ForEach(VoiceProvider.transcribers) { Text($0.title).tag($0) } }
                    Picker("Speaking", selection: $speaker) { ForEach(VoiceProvider.speakers) { Text($0.title).tag($0) } }
                    Toggle("Allow talking over replies", isOn: $talkOver)
                } footer: {
                    Text("Apple voices run on your device with no key. Cloud providers send audio or reply text to that provider and use your own account and free-tier quota. Groq and ElevenLabs voices are usually the quickest to start speaking. Without headphones, talking over a reply may pick up the Bot’s own voice.")
                }
                Section("API keys (stored in the Keychain)") {
                    ForEach(VoiceProvider.allCases.filter(\.needsKey)) { provider in
                        SecureField(provider.title + " key", text: Binding(get: { keys[provider] ?? "" }, set: { keys[provider] = $0; VoiceKeys.set($0, for: provider) }))
                            .autocorrectionDisabledCompat()
                    }
                    TextField("ElevenLabs voice ID", text: $voiceID).autocorrectionDisabledCompat()
                    Picker("Groq voice", selection: $groqVoice) { ForEach(VoiceSettings.groqVoices, id: \.self) { Text($0.capitalized).tag($0) } }
                }
                Section {
                    TextField("Model, for example gemini-2.5-flash-preview-tts", text: $geminiModel).autocorrectionDisabledCompat()
                    Picker("Voice", selection: $geminiVoice) { ForEach(VoiceSettings.geminiVoices, id: \.self) { Text($0).tag($0) } }
                    TextField("Base URL", text: $geminiBase).autocorrectionDisabledCompat()
                } header: { Text("Google AI Studio speaking (Gemini)") } footer: {
                    Text("Get a key at aistudio.google.com and paste it above under Google AI Studio key. Choose Google AI Studio (Gemini) under Speaking. Google changes its speech model names often: if speech fails, check the current speech model name in AI Studio.")
                }
                Section {
                    TextField("Server, for example grpc.nvcf.nvidia.com:443", text: $cloudServer).autocorrectionDisabledCompat()
                    TextField("Function (model) ID", text: $cloudFunction).autocorrectionDisabledCompat()
                    TextField("Voice", text: $cloudVoice).autocorrectionDisabledCompat()
                } header: { Text("NVIDIA Cloud speaking (hosted Magpie)") } footer: {
                    Text("Paste your NVIDIA API key (starts with nvapi-) above under NVIDIA Cloud key. The function ID comes from the model’s page on build.nvidia.com (the default is Magpie TTS Multilingual). This uses NVIDIA’s gRPC speech service and has not been tested against it, so if it fails the app falls back to the built-in voice and shows why.")
                }
                Section {
                    TextField("Address, for example http://localhost:9000", text: $nimURL).autocorrectionDisabledCompat()
                    TextField("Voice", text: $nimVoice).autocorrectionDisabledCompat()
                    SecureField("Key (only if your server needs one)", text: Binding(get: { keys[.nvidiaNIM] ?? "" }, set: { keys[.nvidiaNIM] = $0; VoiceKeys.set($0, for: .nvidiaNIM) }))
                        .autocorrectionDisabledCompat()
                } header: { Text("NVIDIA NIM speaking") } footer: {
                    Text("Speaks with a Magpie TTS NIM that you run yourself (a Docker container on an NVIDIA GPU, usually at port 9000). NVIDIA’s hosted cloud endpoint uses gRPC and is not supported here. Choose NVIDIA NIM under Speaking to use it.")
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Voice settings")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { save(); dismiss() } } }
        }
        .frame(minWidth: 380, minHeight: 640)
        .onDisappear { save() }
    }

    private func save() {
        VoiceSettings.transcriber = transcriber; VoiceSettings.speaker = speaker
        VoiceSettings.allowTalkOver = talkOver; VoiceSettings.elevenLabsVoiceID = voiceID
        VoiceSettings.groqVoice = groqVoice; VoiceSettings.nimBaseURL = nimURL; VoiceSettings.nimVoice = nimVoice
        VoiceSettings.geminiModel = geminiModel; VoiceSettings.geminiVoice = geminiVoice; VoiceSettings.geminiBaseURL = geminiBase
        VoiceSettings.nvidiaCloudServer = cloudServer; VoiceSettings.nvidiaCloudFunctionID = cloudFunction; VoiceSettings.nvidiaCloudVoice = cloudVoice
    }
}

private extension View {
    func autocorrectionDisabledCompat() -> some View { self.autocorrectionDisabled(true) }
}
