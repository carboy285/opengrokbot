import SwiftUI

/// One place to see what Bots may do without asking. Anything that deletes, sends, or signs in always asks and can't be switched off here.
struct MacPermissionsView: View {
    @EnvironmentObject private var desktop: MacAppModel
    @ObservedObject private var apple = AppleConnections.shared
    @ObservedObject private var rules = ApprovalRules.shared
    @State private var addingKind: ApprovalRule.Kind?
    @State private var newTool = ApprovalRules.tools[0].id
    @State private var newPattern = ""

    @ViewBuilder private func ruleList(_ kind: ApprovalRule.Kind, title: String, empty: String) -> some View {
        let list = rules.rules.filter { $0.kind == kind }
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(MacTheme.secondary).padding(.horizontal, 4)
                Spacer()
                Button("Add rule") { newTool = kind == .allow ? ApprovalRules.tools[0].id : newTool; newPattern = ""; addingKind = kind }
                    .buttonStyle(.plain).font(.system(size: 13, weight: .medium)).padding(.horizontal, 12).padding(.vertical, 5)
                    .background(MacTheme.panel, in: Capsule())
                    .accessibilityLabel("Add rule to \(title)")
            }
            if list.isEmpty { Text(empty).font(.system(size: 12)).foregroundStyle(MacTheme.secondary).padding(.horizontal, 4) }
            ForEach(list) { rule in
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(ApprovalRules.title(for: rule.tool)).font(.system(size: 14, weight: .medium))
                        Text(rule.pattern.isEmpty ? "Anywhere" : "Only when it mentions “\(rule.pattern)”").font(.system(size: 12)).foregroundStyle(MacTheme.secondary)
                    }
                    Spacer()
                    Button { rules.remove(rule.id) } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(MacTheme.secondary) }
                        .buttonStyle(.plain).accessibilityLabel("Remove rule")
                }.padding(14).background(MacTheme.raised, in: RoundedRectangle(cornerRadius: 14))
            }
            if addingKind == kind {
                VStack(alignment: .leading, spacing: 10) {
                    Picker("Action", selection: $newTool) {
                        ForEach(ApprovalRules.tools.filter { kind == .ask || !ApprovalRules.askOnlyTools.contains($0.id) }, id: \.id) { Text($0.title).tag($0.id) }
                    }
                    TextField("Only when it mentions… (optional: a website, list or name)", text: $newPattern).textFieldStyle(.roundedBorder)
                    HStack {
                        Button("Add") { _ = rules.add(kind: kind, tool: newTool, pattern: newPattern); addingKind = nil }.buttonStyle(.borderedProminent)
                        Button("Cancel") { addingKind = nil }
                    }
                }.padding(14).background(MacTheme.raised, in: RoundedRectangle(cornerRadius: 14))
            }
        }.padding(.top, 6)
    }

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
                    VStack(alignment: .leading, spacing: 4) {
                        Toggle("Use my rules", isOn: Binding(get: { rules.enabled }, set: { rules.setEnabled($0) })).toggleStyle(.switch)
                            .font(.system(size: 15, weight: .medium))
                        Text("Checked before any approval dialog. “Always ask” beats “Allow without asking”. Turn this off to use only the per-app choices below.")
                            .font(.system(size: 12)).foregroundStyle(MacTheme.secondary)
                    }.padding(16).frame(maxWidth: .infinity, alignment: .leading).background(MacTheme.raised, in: RoundedRectangle(cornerRadius: 16))
                    ruleList(.ask, title: "Always ask", empty: "No rules. Add one to make a Bot ask every time, for example on a website.")
                    ruleList(.allow, title: "Allow without asking", empty: "No rules. Add one to skip the dialog for a kind of change.")
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

/// This Bot's own voice choices, shown in Bot details. "App default" follows Settings → Voice.
struct MacVoiceCard: View {
    let bot: Bot
    @EnvironmentObject private var app: AppModel

    private var current: BotVoice { bot.voice ?? BotVoice() }
    private func update(_ change: (inout BotVoice) -> Void) {
        var next = current; change(&next); app.setVoice(next, for: bot.id)
    }

    var body: some View {
        InspectorCard(title: "Voice chat", footer: "Only for this Bot. Anything left on App default follows the voice settings (the gear on the voice screen). Apple's voice runs on this Mac with no key.") {
            Picker("Voice", selection: Binding(get: { current.speaker ?? "" }, set: { value in update { $0.speaker = value.isEmpty ? nil : value } })) {
                Text("App default").tag("")
                ForEach(VoiceProvider.speakers) { Text($0.title).tag($0.rawValue) }
            }
            HStack {
                Text("Speed")
                Slider(value: Binding(get: { current.speed ?? VoiceSettings.storedSpeed }, set: { value in update { $0.speed = value } }), in: 0.75...1.5, step: 0.05)
                Text(String(format: "%.2g×", current.speed ?? VoiceSettings.storedSpeed)).monospacedDigit().foregroundStyle(MacTheme.secondary).frame(width: 44, alignment: .trailing)
            }
            Picker("Language", selection: Binding(get: { current.language ?? "" }, set: { value in update { $0.language = value.isEmpty ? nil : value } })) {
                Text("App default").tag("")
                ForEach(VoiceSettings.languages, id: \.code) { Text($0.name).tag($0.code) }
            }
            if bot.voice != nil { Button("Use app defaults") { app.setVoice(nil, for: bot.id) }.buttonStyle(InspectorButtonStyle(compact: true)) }
        }
    }
}
