import SwiftUI

/// Full-screen hands-free voice mode: a colored orb that reacts to your voice, plus status and live captions.
struct VoiceModeView: View {
    @ObservedObject var conversation: VoiceConversation
    let botName: String
    let tint: Color
    let ink: Color
    let close: () -> Void
    @State private var showSettings = false

    private var session: VoiceSession { conversation.session }
    private var status: String {
        switch session.state {
        case .idle: "Starting…"
        case .listening: "Listening…"
        case .thinking: "Thinking…"
        case .speaking: "Speaking · tap to interrupt"
        }
    }

    var body: some View {
        VStack(spacing: 22) {
            HStack {
                Button { showSettings = true } label: { Image(systemName: "gearshape").font(.system(size: 18, weight: .medium)).frame(width: 44, height: 44) }
                    .buttonStyle(.plain).accessibilityLabel("Voice settings")
                Spacer()
                Text(botName).font(.headline)
                Spacer()
                Color.clear.frame(width: 44, height: 44)
            }
            Spacer(minLength: 0)
            Button { if session.state == .speaking { session.interrupt() } } label: {
                ZStack {
                    Circle().fill(tint.opacity(0.18)).frame(width: 190, height: 190)
                        .scaleEffect(1 + CGFloat(min(session.level, 1)) * 0.35)
                    Circle().fill(tint).frame(width: 130, height: 130)
                        .scaleEffect(session.state == .thinking ? 0.92 : 1 + CGFloat(min(session.level, 1)) * 0.12)
                    Image(systemName: session.state == .speaking ? "waveform" : session.state == .thinking ? "ellipsis" : "mic.fill")
                        .font(.system(size: 36, weight: .medium)).foregroundStyle(ink)
                }.animation(.easeOut(duration: 0.12), value: session.level)
            }.buttonStyle(.plain).accessibilityLabel(status)
            Text(status).font(.title3.weight(.medium))
            Text(session.partial.isEmpty ? " " : session.partial)
                .font(.body).foregroundStyle(.secondary).multilineTextAlignment(.center).lineLimit(4)
                .padding(.horizontal, 28).frame(minHeight: 90, alignment: .top)
            if let message = session.message {
                Text(message).font(.footnote).foregroundStyle(.orange).multilineTextAlignment(.center).padding(.horizontal, 28)
            }
            Spacer(minLength: 0)
            Button(action: close) {
                Label("End voice mode", systemImage: "xmark")
                    .font(.system(size: 16, weight: .semibold)).foregroundStyle(ink)
                    .padding(.horizontal, 22).frame(height: 46).background(tint, in: Capsule())
            }.buttonStyle(.plain)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.regularMaterial)
        .sheet(isPresented: $showSettings) { VoiceSettingsView() }
    }
}

struct VoiceSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var transcriber = VoiceSettings.transcriber
    @State private var speaker = VoiceSettings.speaker
    @State private var talkOver = VoiceSettings.allowTalkOver
    @State private var voiceID = VoiceSettings.elevenLabsVoiceID
    @State private var keys: [VoiceProvider: String] = Dictionary(uniqueKeysWithValues: VoiceProvider.allCases.map { ($0, VoiceKeys.get($0)) })

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Listening", selection: $transcriber) { ForEach(VoiceProvider.transcribers) { Text($0.title).tag($0) } }
                    Picker("Speaking", selection: $speaker) { ForEach(VoiceProvider.speakers) { Text($0.title).tag($0) } }
                    Toggle("Allow talking over replies", isOn: $talkOver)
                } footer: {
                    Text("Apple voices run on your device with no key. Cloud providers send audio or reply text to that provider and use your own account and free-tier quota. Without headphones, talking over a reply may need a louder voice.")
                }
                Section("API keys (stored in the Keychain)") {
                    ForEach(VoiceProvider.allCases.filter(\.needsKey)) { provider in
                        SecureField(provider.title + " key", text: Binding(get: { keys[provider] ?? "" }, set: { keys[provider] = $0; VoiceKeys.set($0, for: provider) }))
                            .autocorrectionDisabledCompat()
                    }
                    TextField("ElevenLabs voice ID", text: $voiceID).autocorrectionDisabledCompat()
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Voice settings")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { save(); dismiss() } } }
        }
        .frame(minWidth: 380, minHeight: 440)
        .onDisappear { save() }
    }

    private func save() {
        VoiceSettings.transcriber = transcriber; VoiceSettings.speaker = speaker
        VoiceSettings.allowTalkOver = talkOver; VoiceSettings.elevenLabsVoiceID = voiceID
    }
}

private extension View {
    func autocorrectionDisabledCompat() -> some View { self.autocorrectionDisabled(true) }
}
