import SwiftUI

/// Hands-free voice mode. 0.9.3: three layouts you can switch between at any time: a compact card over the chat (draggable
/// on the Mac), the whole window with a big orb and large captions, or a small pill while you look at other Bots.
/// Voice keeps running in all three, and when you open another Bot.
struct VoiceModeView: View {
    @ObservedObject var conversation: VoiceConversation
    let botName: String
    let tint: Color
    let ink: Color
    /// The Bot's face, shown in the header and the pill.
    var face: AnyView = AnyView(EmptyView())
    @Binding var layout: VoiceLayout
    /// Opens the Bot this voice chat belongs to (voice keeps running while you look at other Bots).
    var openBot: (() -> Void)? = nil
    let close: () -> Void
    @State private var showSettings = false
    @State private var showCaptions = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    #if os(macOS)
    @AppStorage("voiceCardX") private var savedX = 0.0
    @AppStorage("voiceCardY") private var savedY = 0.0
    @State private var drag = CGSize.zero
    #endif

    init(conversation: VoiceConversation, botName: String, tint: Color, ink: Color, face: AnyView = AnyView(EmptyView()),
         layout: Binding<VoiceLayout>, openBot: (() -> Void)? = nil, close: @escaping () -> Void) {
        self._conversation = ObservedObject(wrappedValue: conversation); self.botName = botName; self.tint = tint; self.ink = ink; self.face = face
        self._layout = layout; self.openBot = openBot; self.close = close
    }

    private var session: VoiceSession { conversation.session }
    private static let danger = Color(red: 0.92, green: 0.24, blue: 0.24)

    private var status: String {
        if session.muted { return "Muted" }
        switch session.state {
        case .idle: return "Starting…"
        case .listening: return session.holding ? "Listening — let go to send" : "Listening…"
        case .thinking: return "Thinking…"
        case .speaking: return session.speakingText.isEmpty ? "Thinking…" : "Speaking"
        }
    }
    private var youText: String { session.state == .listening && !session.partial.isEmpty ? session.partial : session.heard }
    private var border: Color { session.state == .listening && !session.muted ? tint.opacity(0.55) : Color.primary.opacity(0.12) }

    var body: some View {
        GeometryReader { proxy in
            Group {
                switch layout {
                case .card:
                    VStack(spacing: 0) {
                        card(in: proxy.size)
                            #if os(macOS)
                            .offset(cardOffset(in: proxy.size))
                            #endif
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    #if os(iOS)
                    .padding(.top, 60) // below the chat's header
                    #endif
                case .full:
                    full
                case .mini:
                    VStack {
                        Spacer(minLength: 0)
                        HStack { Spacer(minLength: 0); pill }
                    }
                    .padding(.trailing, 20).padding(.bottom, 92)
                }
            }
        }
        .animation(reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.9), value: layout)
        .sheet(isPresented: $showSettings) { VoiceSettingsView() }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Voice mode with \(botName)")
    }

    // MARK: Pieces

    private var header: some View {
        HStack(spacing: 8) {
            Button { openBot?() } label: {
                HStack(spacing: 8) {
                    face.frame(width: layout == .full ? 30 : 24, height: layout == .full ? 30 : 24)
                    Text(botName).font(.system(size: layout == .full ? 15 : 13, weight: .semibold)).lineLimit(1)
                    Text(status).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain).help("Open \(botName)")
            Spacer(minLength: 0)
            small(layout == .full ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right", label: layout == .full ? "Small card" : "Full screen") {
                layout = layout == .full ? .card : .full
                VoiceSettings.layout = layout
            }
            small("minus", label: "Minimize") { layout = .mini }
        }
    }

    private func card(in size: CGSize) -> some View {
        VStack(spacing: 12) {
            #if os(macOS)
            grip.gesture(dragGesture(in: size))
            header.gesture(dragGesture(in: size))
            #else
            header
            #endif
            HStack(spacing: 14) {
                orb(diameter: 46)
                VoiceWaveform(state: session.state, level: session.level, muted: session.muted, reduceMotion: reduceMotion, color: tint).frame(height: 38)
            }
            if showCaptions { captions(large: false) }
            controls(size: 46)
        }
        .padding(16)
        .frame(maxWidth: 440)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).strokeBorder(border, lineWidth: 1))
        .shadow(color: .black.opacity(0.28), radius: 22, y: 10)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.25), value: border)
        .padding(.top, 8).padding(.horizontal, 16)
    }

    /// The whole window: a big orb, large captions and the controls along the bottom.
    private var full: some View {
        VStack(spacing: 0) {
            header.frame(maxWidth: 900).padding(.horizontal, 28).padding(.top, 18)
            Spacer(minLength: 20)
            orb(diameter: 180)
            VoiceWaveform(state: session.state, level: session.level, muted: session.muted, reduceMotion: reduceMotion, color: tint)
                .frame(width: 300, height: 48).padding(.top, 30)
            Spacer(minLength: 20)
            if showCaptions { captions(large: true).frame(maxWidth: 760).padding(.horizontal, 28) }
            controls(size: 56).frame(maxWidth: 520).padding(.horizontal, 28).padding(.top, 18).padding(.bottom, 28)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.ultraThickMaterial)
        .transition(.opacity)
    }

    /// Small and out of the way: voice keeps listening and speaking.
    private var pill: some View {
        HStack(spacing: 6) {
            Button { openBot?() } label: {
                HStack(spacing: 8) {
                    face.frame(width: 26, height: 26)
                    Text(botName).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                    VoiceWaveform(state: session.state, level: session.level, muted: session.muted, reduceMotion: reduceMotion, color: tint, bars: 5)
                        .frame(width: 26, height: 16)
                    Text(session.muted ? "Muted" : session.state == .speaking && !session.speakingText.isEmpty ? "Speaking" : session.state == .listening ? "Listening" : "Thinking")
                        .font(.system(size: 12)).foregroundStyle(.secondary).frame(minWidth: 58, alignment: .leading)
                }
                .padding(.leading, 4).contentShape(Rectangle())
            }
            .buttonStyle(.plain).help("Open \(botName)")
            small("arrow.up.left.and.arrow.down.right", label: "Expand voice mode") { layout = VoiceSettings.layout }
            Button(action: close) {
                Image(systemName: "xmark").font(.system(size: 11, weight: .bold)).foregroundStyle(.white)
                    .frame(width: 28, height: 28).background(Self.danger, in: Circle())
            }
            .buttonStyle(.plain).accessibilityLabel("End voice mode")
        }
        .padding(5)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(Color.primary.opacity(0.1), lineWidth: 1))
        .shadow(color: .black.opacity(0.3), radius: 16, y: 6)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private func captions(large: Bool) -> some View {
        VStack(alignment: large ? .center : .leading, spacing: large ? 10 : 4) {
            if !youText.isEmpty {
                Text(youText).font(.system(size: large ? 17 : 13)).foregroundStyle(.secondary)
                    .lineLimit(large ? 3 : 2).multilineTextAlignment(large ? .center : .leading)
                    .accessibilityLabel("You said: " + youText)
            }
            if !session.speakingText.isEmpty {
                Text(session.speakingText).font(.system(size: large ? 24 : 13, weight: large ? .medium : .regular))
                    .lineLimit(large ? 4 : 2).multilineTextAlignment(large ? .center : .leading)
            }
            Text(session.message ?? status).font(.system(size: large ? 14 : 12))
                .foregroundStyle(session.message == nil ? Color.secondary : Color.orange)
                .lineLimit(2).multilineTextAlignment(large ? .center : .leading)
        }
        .frame(maxWidth: .infinity, alignment: large ? .center : .leading)
        .frame(minHeight: large ? 120 : nil, alignment: .bottom)
    }

    private func controls(size: CGFloat) -> some View {
        HStack(spacing: 12) {
            control("gearshape", label: "Voice settings", size: size) { showSettings = true }
            control("bubble.left", label: showCaptions ? "Hide captions" : "Show captions", highlighted: showCaptions, size: size) { showCaptions.toggle() }
            Spacer(minLength: 0)
            Text("Hold the orb to keep talking").font(.system(size: 11)).foregroundStyle(.tertiary).lineLimit(1).minimumScaleFactor(0.8)
            Spacer(minLength: 0)
            control(session.muted ? "mic.slash.fill" : "mic.fill", label: session.muted ? "Unmute microphone" : "Mute microphone", highlighted: session.muted, size: size) { session.setMuted(!session.muted) }
            control("xmark", label: "End voice mode", danger: true, size: size, action: close)
        }
    }

    /// Press and hold to keep talking (it sends when you let go). A press while the Bot speaks interrupts it.
    private func orb(diameter: CGFloat) -> some View {
        ZStack {
            Circle().fill(LinearGradient(colors: [tint.opacity(0.95), tint.opacity(0.6)], startPoint: .top, endPoint: .bottom))
                .frame(width: diameter, height: diameter)
                .shadow(color: tint.opacity(diameter > 100 ? 0.45 : 0), radius: diameter > 100 ? 30 + CGFloat(min(session.level, 1)) * 40 : 0)
            HStack(spacing: diameter * 0.11) {
                Capsule().fill(ink).frame(width: diameter * 0.11, height: diameter * 0.32)
                Capsule().fill(ink).frame(width: diameter * 0.11, height: diameter * 0.32)
            }
            if session.holding { Circle().strokeBorder(tint.opacity(0.6), lineWidth: 4).frame(width: diameter + 10, height: diameter + 10) }
        }
        .scaleEffect(reduceMotion ? 1 : 1 + CGFloat(min(session.level, 1)) * 0.12)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: session.level)
        .contentShape(Circle())
        .onLongPressGesture(minimumDuration: 30, perform: {}, onPressingChanged: { pressing in session.hold(pressing) })
        .accessibilityElement()
        .accessibilityLabel(status)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Press and hold to keep talking. While the Bot speaks, press to interrupt.")
        .accessibilityAction { if session.state == .speaking { session.interrupt() } }
    }

    private func small(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
                .frame(width: 28, height: 28).background(Color.primary.opacity(0.06), in: Circle()).contentShape(Circle())
        }
        .buttonStyle(.plain).accessibilityLabel(label).help(label)
    }

    private func control(_ symbol: String, label: String, highlighted: Bool = false, danger: Bool = false, size: CGFloat = 46, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: size * 0.35, weight: .medium))
                .foregroundStyle(danger ? Color.white : Color.primary.opacity(0.85))
                .frame(width: size, height: size)
                .background(danger ? Self.danger : Color.primary.opacity(highlighted ? 0.18 : 0.08), in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    #if os(macOS)
    /// A handle at the top of the card. Dragging it (or the header) moves the whole card.
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
    var bars = 32

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: reduceMotion)) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            HStack(spacing: bars < 10 ? 2 : 3) {
                ForEach(0..<bars, id: \.self) { index in
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
        let bump = 0.45 + 0.55 * sin(Double.pi * Double(index) / Double(max(bars - 1, 1)))
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
    @State private var speaker = VoiceSettings.storedSpeaker
    @State private var talkOver = VoiceSettings.allowTalkOver
    @State private var speed = VoiceSettings.storedSpeed
    @State private var language = VoiceSettings.storedLanguage
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
    @State private var patience = VoiceSettings.patience
    @State private var acknowledge = VoiceSettings.acknowledge
    @State private var narrate = VoiceSettings.narrate
    @State private var accurate = VoiceSettings.accurateRecognition
    @State private var fastModel = VoiceSettings.fastModel
    @State private var layout = VoiceSettings.layout

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Listening", selection: $transcriber) { ForEach(VoiceProvider.transcribers) { Text($0.title).tag($0) } }
                    Picker("Speaking", selection: $speaker) { ForEach(VoiceProvider.speakers) { Text($0.title).tag($0) } }
                    Toggle("Allow talking over replies", isOn: $talkOver)
                    Picker("Language", selection: $language) { ForEach(VoiceSettings.languages, id: \.code) { Text($0.name).tag($0.code) } }
                    HStack {
                        Text("Speaking speed")
                        Slider(value: $speed, in: 0.75...1.5, step: 0.05)
                        Text(String(format: "%.2g×", speed)).monospacedDigit().foregroundStyle(.secondary).frame(width: 44, alignment: .trailing)
                    }
                } footer: {
                    Text(LocalVoice.supported ? "“On this Mac” runs free open-source models (Whisper listens, Kokoro speaks) on your Mac: nothing leaves it. Apple voices also run on your device with no key." : "Apple voices run on your device with no key.")
                }
                #if os(macOS)
                MacLocalVoiceSection()
                #endif
                Section {
                    Picker("Wait before sending", selection: $patience) {
                        Text("Quick — answers fast").tag("quick"); Text("Normal").tag("normal"); Text("Relaxed — time to think").tag("relaxed")
                    }
                    Toggle("Say “one sec” while thinking", isOn: $acknowledge)
                    Toggle("Say what the Bot is doing", isOn: $narrate)
                    Toggle("More accurate recognition (uses Apple’s servers)", isOn: $accurate)
                    Picker("Opens as", selection: $layout) { Text("Small card").tag(VoiceLayout.card); Text("Full screen").tag(VoiceLayout.full) }
                } header: { Text("Conversation") } footer: {
                    Text("Voice mode waits longer when you trail off (“and…”, “um”). Press and hold the orb to keep talking as long as you like; it sends when you let go.")
                }
                Section {
                    Toggle("Use a quick model in voice mode", isOn: $fastModel)
                } header: { Text("Faster answers") } footer: {
                    Text("In voice mode Bots answer in a short, spoken style. With this on, Claude Code uses Haiku, Gemini CLI uses Gemini Flash and Codex thinks less. Ollama and LM Studio already run on your computer.")
                }
                Section {
                    EmptyView()
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
        VoiceSettings.speed = speed; VoiceSettings.language = language
        VoiceSettings.allowTalkOver = talkOver; VoiceSettings.elevenLabsVoiceID = voiceID
        VoiceSettings.groqVoice = groqVoice; VoiceSettings.nimBaseURL = nimURL; VoiceSettings.nimVoice = nimVoice
        VoiceSettings.geminiModel = geminiModel; VoiceSettings.geminiVoice = geminiVoice; VoiceSettings.geminiBaseURL = geminiBase
        VoiceSettings.nvidiaCloudServer = cloudServer; VoiceSettings.nvidiaCloudFunctionID = cloudFunction; VoiceSettings.nvidiaCloudVoice = cloudVoice
        VoiceSettings.patience = patience; VoiceSettings.acknowledge = acknowledge; VoiceSettings.narrate = narrate
        VoiceSettings.accurateRecognition = accurate; VoiceSettings.fastModel = fastModel; VoiceSettings.layout = layout
    }
}

private extension View {
    func autocorrectionDisabledCompat() -> some View { self.autocorrectionDisabled(true) }
}
