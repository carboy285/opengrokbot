import SwiftUI

/// One place to see what Bots may do without asking. Anything that deletes, sends, or signs in always asks and can't be switched off here.
struct MacPermissionsView: View {
    @EnvironmentObject private var desktop: MacAppModel
    @ObservedObject private var apple = AppleConnections.shared

    private let alwaysAsk: [(symbol: String, title: String, detail: String)] = [
        ("trash", "Deleting anything", "Calendar events, reminders, contacts, notes and mail always show what will go and wait for you."),
        ("paperplane", "Sending email or messages", "Drafts and replies are shown first. Nothing is sent until you approve."),
        ("lock.shield", "Saved logins and passwords", "Signing in with a saved login or password manager entry always asks, and can require Touch ID. These are never allowed automatically."),
        ("moon.zzz", "Unattended routines", "A routine that runs while you're away skips anything that needs approval instead of guessing.")
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 12) {
                Button { desktop.panel = .settings } label: { Image(systemName: "chevron.left").frame(width: 38, height: 38) }
                    .buttonStyle(.plain).accessibilityLabel("Back to Settings")
                Text("Permissions").font(.system(size: 25, weight: .medium))
                Spacer()
                Button { desktop.panel = nil } label: { Image(systemName: "xmark").frame(width: 38, height: 38) }
                    .buttonStyle(.plain).accessibilityLabel("Close Permissions")
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Choose where a Bot can add or change things without asking each time. Turn the app on first under Apple Connections.")
                        .font(.system(size: 14)).lineSpacing(4).foregroundStyle(MacTheme.secondary)
                    ForEach(Array(AppleConnections.autoApprovable).sorted { $0.title < $1.title }) { service in
                        HStack(spacing: 14) {
                            Image(systemName: service.symbol).font(.system(size: 17)).frame(width: 40, height: 40)
                                .background(MacTheme.panel, in: RoundedRectangle(cornerRadius: 10))
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Adding and changing in \(service.title)").font(.system(size: 15, weight: .medium))
                                if !apple.isEnabled(service) { Text("Not connected").font(.system(size: 12)).foregroundStyle(MacTheme.secondary) }
                            }
                            Spacer()
                            Picker("", selection: Binding(get: { apple.autoApproves(service) }, set: { apple.setAutoApproves(service, $0) })) {
                                Text("Always ask").tag(false)
                                Text("Allow without asking").tag(true)
                            }.labelsHidden().frame(width: 190)
                                .accessibilityLabel("Permission for \(service.title)")
                        }.padding(16).background(MacTheme.raised, in: RoundedRectangle(cornerRadius: 16))
                    }
                    Text("Always asks").font(.system(size: 13, weight: .semibold)).foregroundStyle(MacTheme.secondary).padding(.top, 8).padding(.horizontal, 4)
                    ForEach(alwaysAsk, id: \.title) { rule in
                        HStack(alignment: .top, spacing: 14) {
                            Image(systemName: rule.symbol).font(.system(size: 17)).frame(width: 40, height: 40)
                                .background(MacTheme.panel, in: RoundedRectangle(cornerRadius: 10))
                            VStack(alignment: .leading, spacing: 3) {
                                Text(rule.title).font(.system(size: 15, weight: .medium))
                                Text(rule.detail).font(.system(size: 13)).lineSpacing(3).foregroundStyle(MacTheme.secondary)
                            }
                            Spacer()
                            Image(systemName: "lock.fill").foregroundStyle(MacTheme.secondary).accessibilityLabel("Always asks")
                        }.padding(16).background(MacTheme.raised, in: RoundedRectangle(cornerRadius: 16))
                    }
                }.frame(maxWidth: 780, alignment: .leading).padding(.vertical, 6).frame(maxWidth: .infinity)
            }
        }.padding(36)
    }
}

/// Voice settings shown inside Bot details. These apply to every Bot, because the voice is chosen for the app, not per Bot.
struct MacVoiceCard: View {
    @State private var speaker = VoiceSettings.speaker
    @State private var speed = VoiceSettings.speed
    @State private var language = VoiceSettings.language

    var body: some View {
        InspectorCard(title: "Voice chat", footer: "Applies to every Bot. Keys and more options are in the voice screen's settings (the gear). Apple's voice runs on this Mac with no key.") {
            Picker("Voice", selection: $speaker) { ForEach(VoiceProvider.speakers) { Text($0.title).tag($0) } }
                .onChange(of: speaker) { _, value in VoiceSettings.speaker = value }
            HStack {
                Text("Speed")
                Slider(value: $speed, in: 0.75...1.5, step: 0.05).onChange(of: speed) { _, value in VoiceSettings.speed = value }
                Text(String(format: "%.2g×", speed)).monospacedDigit().foregroundStyle(MacTheme.secondary).frame(width: 44, alignment: .trailing)
            }
            Picker("Language", selection: $language) { ForEach(VoiceSettings.languages, id: \.code) { Text($0.name).tag($0.code) } }
                .onChange(of: language) { _, value in VoiceSettings.language = value }
        }
    }
}
