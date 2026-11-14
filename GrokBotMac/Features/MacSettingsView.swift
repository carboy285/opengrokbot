import AppKit
import SwiftUI

struct MacSettingsView: View {
    @EnvironmentObject private var app: AppModel
    @EnvironmentObject private var desktop: MacAppModel
    @AppStorage("macAppearance") private var appearance = "dark"
    @AppStorage("spellChecking") private var spellChecking = true
    @AppStorage("accentStyle") private var accentStyle = "bot"
    @AppStorage("profileName") private var profileName = "You"
    @AppStorage("keepAwakeForRoutines") private var keepAwakeForRoutines = false
    @State private var reset = false

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 4) {
                ForEach(SettingsTab.allCases) { tab in
                    Button { desktop.settingsTab = tab } label: {
                        HStack(spacing: 13) {
                            Image(systemName: tab.icon).font(.system(size: 17)).frame(width: 22)
                            Text(tab.rawValue).font(.system(size: 17))
                            Spacer()
                        }
                        .padding(.horizontal, 14).padding(.vertical, 12)
                        .background(desktop.settingsTab == tab ? MacTheme.raised : .clear, in: RoundedRectangle(cornerRadius: 11))
                        .contentShape(RoundedRectangle(cornerRadius: 11))
                    }.buttonStyle(.plain).accessibilityAddTraits(desktop.settingsTab == tab ? [.isSelected] : [])
                }
                Spacer()
                Text("OpenGrokBot \(desktop.updates.current)").font(.system(size: 11)).foregroundStyle(MacTheme.secondary)
            }
            .padding(16).padding(.top, 6).frame(width: 238).background(MacTheme.sidebar)
            Rectangle().fill(MacTheme.line).frame(width: 1)
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text(desktop.settingsTab.rawValue).font(.system(size: 24, weight: .medium))
                    Spacer()
                    Button { desktop.panel = nil } label: { Image(systemName: "xmark").font(.system(size: 19)).frame(width: 34, height: 34) }.buttonStyle(.plain).help("Close settings")
                }.padding(.horizontal, 36).padding(.top, 25).padding(.bottom, 25)
                ScrollView {
                    VStack(alignment: .leading, spacing: 28) {
                        switch desktop.settingsTab {
                        case .general: general
                        case .headsUps: MacHeadsUpsSettings()
                        case .computer: computer
                        case .permissions: unavailable(title: "Your CLI keeps its permissions", detail: "Codex runs with read-only workspace access. Other CLIs keep their own configured permissions. This app does not add approval-bypass flags or auto-approve tools.", icon: "shield")
                        case .apiKeys: VStack(alignment: .leading, spacing: 28) { MacAPIKeysView(); MacMediaKeysView() }
                        case .secureLogins: MacSecureLoginsView()
                        case .vault: MacVaultView()
                        case .voice: MacVoiceSettingsPage()
                        case .localModels: MacLocalModelsView()
                        case .usage: MacUsageView()
                        case .updates: updates
                        }
                    }.padding(.horizontal, 36).padding(.bottom, 34).frame(maxWidth: .infinity, alignment: .leading)
                }
            }.background(MacTheme.canvas)
        }
        .confirmationDialog("Reset all Bots and conversations?", isPresented: $reset, titleVisibility: .visible) {
            Button("Reset conversations", role: .destructive) { desktop.stopAll(); app.resetPreview(); desktop.selectedID = app.workspace.bots.first?.id }
        }
    }

    private var general: some View {
        Group {
            HStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Free and open source").font(.system(size: 18, weight: .medium))
                    Text("Use AI CLIs installed on your Mac. There is no OpenGrokBot subscription; model access and usage follow your chosen CLI account or local provider.")
                        .font(.system(size: 15)).lineSpacing(5).foregroundStyle(MacTheme.secondary)
                    MacPillButton(title: "Set up AI CLI", prominent: true) { desktop.panel = .setup }
                        .padding(.top, 8)
                }
                Spacer(minLength: 0)
                HStack(spacing: 15) {
                    Image(systemName: "shippingbox.fill")
                    Image(systemName: "sparkle")
                    MacBotAvatar(size: 35)
                    Text("𝕏").font(.system(size: 36))
                }.font(.system(size: 30)).foregroundStyle(.black).padding(28)
                    .frame(minWidth: 180, maxHeight: .infinity)
                    .background(LinearGradient(colors: [.white, Color(hex: 0xD0D0D0)], startPoint: .topTrailing, endPoint: .bottomLeading), in: RoundedRectangle(cornerRadius: 12))
            }.padding(22).background(MacTheme.canvas, in: RoundedRectangle(cornerRadius: 18))
                .overlay(RoundedRectangle(cornerRadius: 18).stroke(MacTheme.line))
            section("Account") {
                HStack(spacing: 16) {
                    Text(String(profileName.prefix(2)).uppercased()).font(.system(size: 21)).foregroundStyle(MacTheme.secondary)
                        .frame(width: 56, height: 56).background(MacTheme.raised, in: Circle())
                    VStack(alignment: .leading, spacing: 6) {
                        TextField("Display name", text: $profileName).textFieldStyle(.plain).font(.system(size: 17))
                        Text("Display name on this Mac").font(.system(size: 14)).foregroundStyle(MacTheme.secondary)
                    }
                    Spacer()
                    MacPillButton(title: "AI CLI setup") { desktop.panel = .setup }
                }.padding(20)
                Divider()
                CloudSignInView(account:desktop.remote.account).padding(20)
            }
            section("Appearance") {
                VStack(spacing: 0) {
                    settingRow("Theme") {
                        Picker("Theme", selection: $appearance) {
                            Text("Follow System").tag("system")
                            Text("Dark").tag("dark")
                            Text("Light").tag("light")
                        }.labelsHidden().frame(width: 155)
                    }
                    settingRow("Accent") {
                        Picker("Accent", selection: $accentStyle) {
                            Text("Bot color").tag("bot")
                            Text("Neutral").tag("neutral")
                        }.labelsHidden().frame(width: 155)
                    }
                    settingRow("Check Spelling While Typing") { Toggle("Check spelling", isOn: $spellChecking).labelsHidden().toggleStyle(.switch).controlSize(.small) }
                }
            }
            section("Local data") {
                HStack {
                    Text("Bots and conversations").font(.system(size: 15))
                    Spacer()
                    MacPillButton(title: "Reset conversations…") { reset = true }
                }.padding(18)
            }
        }
    }

    private var computer: some View {
        Group {
            unavailable(title: "AI runs from this Mac", detail: "This app launches the installed CLI on this Mac. Each Bot has a separate working folder and saved CLI session. Approved iPhones can control this workspace using the same account.", icon: "desktopcomputer")
            MacRemoteAccessView(remote: desktop.remote)
            Text("Bot browsers run locally, with a separate visible browser and cookie/login profile for each Bot. Open Bot details → Open local browser. No browser provider account is needed.").font(.callout).foregroundStyle(.secondary)
            Button("Permissions: what Bots may do without asking…") { desktop.panel = .permissions }
            if let main = app.workspace.bots.first(where: { $0.isMain == true }) { MacSharedVMSettings(main: main) }
            Button("Computers: look at another or copy Bots between them…") { desktop.copyingBot = nil; desktop.copyNotice = nil; desktop.panel = .computers }
            section("Always on") {
                VStack(alignment: .leading, spacing: 8) {
                    Toggle("Keep this Mac awake while Bots have scheduled routines", isOn: $keepAwakeForRoutines).toggleStyle(.switch)
                    Text("A Bot that is replying always keeps the Mac awake until it finishes. This extends that to scheduled routines and email or calendar triggers. It uses more battery, and closing a laptop lid still puts it to sleep.")
                        .font(.system(size: 12)).lineSpacing(3).foregroundStyle(MacTheme.secondary)
                    if let wake = WakeCommand.next(for: app.workspace.bots.flatMap { $0.schedules ?? [] }) {
                        Divider()
                        Text("A sleeping Mac can’t be woken by an app. To wake it before your next routine (\(wake.date.formatted(date: .abbreviated, time: .shortened))), run this once in Terminal. It asks for your password:").font(.system(size: 12)).foregroundStyle(MacTheme.secondary)
                        Text(wake.command).font(.system(size: 12, design: .monospaced)).textSelection(.enabled)
                        MacPillButton(title: "Copy wake command") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(wake.command, forType: .string) }
                    }
                }.padding(20)
            }
            section("Phone notifications") { MacPushSettings() }
            section("This Mac") {
                VStack(spacing: 0) {
                    settingRow("Time zone") { Text(TimeZone.current.identifier).foregroundStyle(MacTheme.secondary) }
                    settingRow("App storage") { Text("Application Support/OpenGrokBot").font(.system(size: 12)).foregroundStyle(MacTheme.secondary) }
                }
            }
        }
    }

    private var updates: some View { VStack(spacing: 18) { DesktopUpdatesView(updates: desktop.updates, busy: !desktop.runningBots.isEmpty); MacBackupView() } }

    private func unavailable(title: String, detail: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Image(systemName: icon).font(.system(size: 36, weight: .light)).foregroundStyle(MacTheme.secondary)
            Text(title).font(.system(size: 23, weight: .medium))
            Text(detail).font(.system(size: 16)).lineSpacing(5).foregroundStyle(MacTheme.secondary)
            Button("View connection status") { desktop.panel = .setup }.buttonStyle(.link)
        }.padding(28).frame(maxWidth: .infinity, alignment: .leading).background(MacTheme.panel, in: RoundedRectangle(cornerRadius: 18))
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.system(size: 14)).foregroundStyle(MacTheme.secondary).padding(.leading, 16)
            content().frame(maxWidth: .infinity, alignment: .leading).background(MacTheme.panel, in: RoundedRectangle(cornerRadius: 18))
        }
    }

    private func settingRow<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        HStack { Text(title).font(.system(size: 16)); Spacer(); content() }.padding(.horizontal, 20).padding(.vertical, 18)
    }

    private func openDocumentation(_ address: String) { if let url = URL(string: address) { NSWorkspace.shared.open(url) } }
}


/// Optional API keys for the provider CLIs. Subscriptions need no key: sign in through the CLI instead.
private struct MacAPIKeysView: View {
    private static let providers = CLIProvider.allCases.filter { ProviderAPIKeys.info(for: $0) != nil }
    @State private var drafts: [CLIProvider:String] = [:]
    @State private var saved: [CLIProvider:String] = [:]
    @State private var feedback: [CLIProvider:String] = [:]

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Use your own API keys").font(.system(size: 18, weight: .medium))
                Text("A ChatGPT, Claude or Grok subscription works without a key: sign in through that provider’s CLI in Setup. Add an API key here only if you want a Bot to use pay-per-token API access instead. A saved key replaces the CLI’s own sign-in for that provider until you remove it.")
                    .font(.system(size: 15)).lineSpacing(5).foregroundStyle(MacTheme.secondary)
                Text("Keys are stored only in this Mac’s Keychain and handed to the CLI through its environment. They are never shown to Bots, written to files, or synced.")
                    .font(.system(size: 13)).lineSpacing(4).foregroundStyle(MacTheme.secondary)
            }.padding(22).frame(maxWidth: .infinity, alignment: .leading).background(MacTheme.panel, in: RoundedRectangle(cornerRadius: 18))
            ForEach(Self.providers) { provider in card(provider) }
            Text("OpenCode manages its own provider keys: run opencode auth login in Terminal.").font(.system(size: 13)).foregroundStyle(MacTheme.secondary)
        }.onAppear(perform: load)
    }

    private func card(_ provider: CLIProvider) -> some View {
        let info = ProviderAPIKeys.info(for: provider)!
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(provider.name).font(.system(size: 17, weight: .medium))
                Spacer()
                if let mask = saved[provider] { Label("Using API key \(mask)", systemImage: "checkmark.seal.fill").font(.system(size: 13)).foregroundStyle(.green) }
                else { Text("Using CLI sign-in").font(.system(size: 13)).foregroundStyle(MacTheme.secondary) }
            }
            HStack {
                SecureField(info.example, text: Binding(get: { drafts[provider] ?? "" }, set: { drafts[provider] = $0 })).textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("api-key-\(provider.rawValue)")
                MacPillButton(title: saved[provider] == nil ? "Save to Keychain" : "Replace key", prominent: true) { save(provider) }
                    .disabled((drafts[provider] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                if saved[provider] != nil { MacPillButton(title: "Remove") { remove(provider) } }
            }
            Text(info.billing).font(.system(size: 12)).lineSpacing(3).foregroundStyle(MacTheme.secondary)
            HStack {
                Link("Get a key ↗", destination: info.console).font(.system(size: 12))
                Text("Sets \(info.variables.joined(separator: ", ")) for \(provider.name) only.").font(.system(size: 12)).foregroundStyle(MacTheme.secondary)
            }
            if let message = feedback[provider] { Text(message).font(.system(size: 13)).foregroundStyle(MacTheme.secondary) }
        }.padding(20).frame(maxWidth: .infinity, alignment: .leading).background(MacTheme.panel, in: RoundedRectangle(cornerRadius: 18))
    }

    private func load() { for provider in Self.providers { saved[provider] = ProviderAPIKeys.get(provider).map(ProviderAPIKeys.masked) } }

    private func save(_ provider: CLIProvider) {
        let draft = drafts[provider] ?? ""
        do {
            guard try ProviderAPIKeys.save(draft, for: provider) else { feedback[provider] = "That does not look like an API key. Paste only the key, with no spaces or line breaks."; return }
            drafts[provider] = ""; feedback[provider] = "Saved. New messages from Bots using \(provider.name) will use this key."
        } catch { feedback[provider] = "The Keychain could not save this key. Unlock your Mac and try again." }
        load()
    }

    private func remove(_ provider: CLIProvider) {
        do { try ProviderAPIKeys.remove(provider); feedback[provider] = "Removed. \(provider.name) will use its own sign-in again." }
        catch { feedback[provider] = "The Keychain could not remove this key. Unlock your Mac and try again." }
        load()
    }
}


/// What the app has run: messages, estimated tokens and whether an API key or a sign-in was used. Estimates from text length, not billing data.
private struct MacUsageView: View {
    @ObservedObject private var ledger = UsageLedger.shared
    @State private var days = 7
    private var since: Date { days == 0 ? Calendar.current.startOfDay(for: Date()) : Date().addingTimeInterval(-Double(days) * 86_400) }

    var body: some View {
        let providers = UsageLedger.summarize(ledger.records, since: since, key: \.provider)
        let bots = UsageLedger.summarize(ledger.records, since: since, key: \.botName)
        let total = providers.reduce(0) { $0 + $1.messages }
        VStack(alignment: .leading, spacing: 18) {
            Picker("Period", selection: $days) { Text("Today").tag(0); Text("7 days").tag(7); Text("30 days").tag(30) }.pickerStyle(.segmented).frame(width: 300)
            HStack(spacing: 14) {
                stat("\(total)", "messages answered")
                stat(format(providers.reduce(0) { $0 + $1.tokensIn }), "≈ tokens sent")
                stat(format(providers.reduce(0) { $0 + $1.tokensOut }), "≈ tokens received")
                stat("\(providers.reduce(0) { $0 + $1.apiMessages })", "used an API key")
            }
            table("By provider", providers)
            table("By Bot", bots)
            VStack(alignment: .leading, spacing: 8) {
                Text("Token counts are estimated from text length on this Mac. They are not billing data. Messages that used a subscription sign-in count against that plan’s limits; messages that used an API key are billed per token by the provider.")
                    .font(.system(size: 12)).lineSpacing(3).foregroundStyle(MacTheme.secondary)
                HStack(spacing: 16) {
                    Link("OpenAI usage ↗", destination: URL(string: "https://platform.openai.com/usage")!)
                    Link("Anthropic usage ↗", destination: URL(string: "https://console.anthropic.com/settings/usage")!)
                    Link("xAI console ↗", destination: URL(string: "https://console.x.ai")!)
                    Spacer()
                    Button("Clear history") { ledger.clear() }.disabled(ledger.records.isEmpty)
                }.font(.system(size: 12))
            }
        }
    }

    private func format(_ value: Int) -> String { value >= 1_000_000 ? String(format: "%.1fM", Double(value) / 1_000_000) : value >= 1000 ? String(format: "%.1fk", Double(value) / 1000) : "\(value)" }

    private func stat(_ value: String, _ caption: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value).font(.system(size: 24, weight: .medium))
            Text(caption).font(.system(size: 12)).foregroundStyle(MacTheme.secondary)
        }.padding(16).frame(maxWidth: .infinity, alignment: .leading).background(MacTheme.panel, in: RoundedRectangle(cornerRadius: 14))
    }

    private func table(_ title: String, _ rows: [UsageRow]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.system(size: 14)).foregroundStyle(MacTheme.secondary).padding(.leading, 16)
            VStack(spacing: 0) {
                if rows.isEmpty { Text("Nothing yet in this period.").font(.system(size: 14)).foregroundStyle(MacTheme.secondary).padding(18).frame(maxWidth: .infinity, alignment: .leading) }
                ForEach(rows) { row in
                    HStack {
                        Text(row.id).font(.system(size: 15)).lineLimit(1)
                        Spacer()
                        Text("\(row.messages) msg · ≈\(format(row.tokensIn + row.tokensOut)) tokens\(row.apiMessages > 0 ? " · \(row.apiMessages) via API key" : "")").font(.system(size: 12)).foregroundStyle(MacTheme.secondary)
                    }.padding(.horizontal, 18).padding(.vertical, 13)
                    if row.id != rows.last?.id { Divider() }
                }
            }.background(MacTheme.panel, in: RoundedRectangle(cornerRadius: 16))
        }
    }
}


/// Settings → Heads-ups (0.9.6): what Grok Bot may tell you about without being asked.
struct MacHeadsUpsSettings: View {
    @EnvironmentObject private var desktop: MacAppModel
    @ObservedObject private var apple = AppleConnections.shared
    @AppStorage(HeadsUpSettings.enabledKey) private var enabled = false
    @AppStorage(HeadsUpSettings.emailKey) private var email = true
    @AppStorage(HeadsUpSettings.meetingsKey) private var meetings = true
    @AppStorage(HeadsUpSettings.leadKey) private var lead = 10
    @AppStorage(HeadsUpSettings.conflictsKey) private var conflicts = true
    @AppStorage(HeadsUpSettings.briefKey) private var brief = true
    @AppStorage(HeadsUpSettings.briefMinutesKey) private var briefMinutes = 8 * 60
    @AppStorage(HeadsUpSettings.quietKey) private var quiet = true
    @AppStorage(HeadsUpSettings.quietStartKey) private var quietStart = 22 * 60
    @AppStorage(HeadsUpSettings.quietEndKey) private var quietEnd = 7 * 60
    @AppStorage(HeadsUpSettings.remindersKey) private var reminders = true
    @AppStorage(HeadsUpSettings.deliveriesKey) private var deliveries = true
    @State private var muted = HeadsUpSettings.muted

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Let Grok Bot reach out first").font(.system(size: 18, weight: .medium))
                Text("Grok Bot keeps an eye on Mail and Calendar on this Mac and messages you when something needs you, so you don’t have to keep checking.")
                    .font(.system(size: 15)).lineSpacing(5).foregroundStyle(MacTheme.secondary).fixedSize(horizontal: false, vertical: true)
            }
            card {
                row("Heads-ups", detail: enabled ? "On · checks about every three minutes while OpenGrokBot is open" : "Off") {
                    Toggle("Heads-ups", isOn: $enabled).labelsHidden().toggleStyle(.switch)
                }
                if enabled {
                    divider
                    access("Mail", on: apple.canRead(.mail))
                    access("Calendar", on: apple.canRead(.calendar))
                    if !apple.canRead(.mail) || !apple.canRead(.calendar) {
                        HStack {
                            Text("Turn on Mail and Calendar under This Mac. Heads-ups use whichever ones are on.").font(.system(size: 13)).foregroundStyle(MacTheme.secondary)
                            Spacer()
                            MacPillButton(title: "Open This Mac", prominent: false) { desktop.panel = .apple }
                        }.padding(.horizontal, 20).padding(.bottom, 16)
                    }
                }
            }
            section("Tell me about") {
                row("New email from people", detail: "Newsletters and automated senders stay quiet.") { toggle($email, "New email from people") }
                divider
                row("Upcoming meetings", detail: "A reminder with the join link.") {
                    HStack(spacing: 12) {
                        Picker("Minutes before a meeting", selection: $lead) { ForEach([5, 10, 15, 30], id: \.self) { Text("\($0) min before").tag($0) } }
                            .labelsHidden().frame(width: 130).disabled(!enabled || !meetings)
                        toggle($meetings, "Upcoming meetings")
                    }
                }
                divider
                row("Double-bookings", detail: "When two events overlap.") { toggle($conflicts, "Double-bookings") }
                divider
                row("Morning brief", detail: "Your day at a glance.") {
                    HStack(spacing: 12) {
                        DatePicker("Morning brief time", selection: time($briefMinutes), displayedComponents: .hourAndMinute).labelsHidden().disabled(!enabled || !brief)
                        toggle($brief, "Morning brief")
                    }
                }
                divider
                row("Reminders due today", detail: "From Reminders on this Mac.") { toggle($reminders, "Reminders due today") }
                divider
                row("Deliveries", detail: "Packages out for delivery or delivered today.") { toggle($deliveries, "Deliveries") }
            }
            if !muted.isEmpty {
                section("Muted senders") {
                    ForEach(muted, id: \.self) { address in
                        HStack {
                            Text(address).font(.system(size: 15))
                            Spacer()
                            MacPillButton(title: "Unmute", prominent: false) { desktop.headsUps.mute(address, false); muted = HeadsUpSettings.muted }
                        }.padding(.horizontal, 20).padding(.vertical, 10)
                    }
                }
            }
            section("When") {
                row("Quiet hours", detail: "Heads-ups still land in the chat, without a sound.") {
                    HStack(spacing: 8) {
                        DatePicker("Quiet hours start", selection: time($quietStart), displayedComponents: .hourAndMinute).labelsHidden()
                        Text("to").foregroundStyle(MacTheme.secondary)
                        DatePicker("Quiet hours end", selection: time($quietEnd), displayedComponents: .hourAndMinute).labelsHidden()
                        toggle($quiet, "Quiet hours")
                    }.disabled(!enabled)
                }
            }
            Text("Heads-ups read Mail and Calendar on this Mac and only post messages. They never reply, send, accept or change anything. Ask Grok Bot directly when you want it to act. Phone alerts follow Settings → Computer → Phone notifications.")
                .font(.system(size: 12)).lineSpacing(3).foregroundStyle(MacTheme.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .animation(.spring(response: 0.35, dampingFraction: 1), value: enabled)
        .onAppear { muted = HeadsUpSettings.muted }
    }

    private var divider: some View { Rectangle().fill(MacTheme.line).frame(height: 1).padding(.leading, 20) }

    private func toggle(_ value: Binding<Bool>, _ label: String) -> some View {
        Toggle(label, isOn: value).labelsHidden().toggleStyle(.switch).disabled(!enabled)
    }

    private func time(_ minutes: Binding<Int>) -> Binding<Date> {
        Binding(get: { Calendar.current.date(bySettingHour: minutes.wrappedValue / 60, minute: minutes.wrappedValue % 60, second: 0, of: Date()) ?? Date() },
                set: { minutes.wrappedValue = HeadsUpRules.minuteOfDay($0) })
    }

    private func access(_ name: String, on: Bool) -> some View {
        HStack(spacing: 10) {
            Circle().fill(on ? Color.green : MacTheme.tertiary).frame(width: 8, height: 8)
            Text(name).font(.system(size: 15))
            Spacer()
            Text(on ? "On" : "Off").font(.system(size: 13)).foregroundStyle(MacTheme.secondary)
        }.padding(.horizontal, 20).padding(.vertical, 10)
    }

    private func card<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) { content() }.frame(maxWidth: .infinity, alignment: .leading).background(MacTheme.panel, in: RoundedRectangle(cornerRadius: 18))
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.system(size: 14)).foregroundStyle(MacTheme.secondary).padding(.leading, 16)
            card(content: content)
        }
    }

    private func row<Content: View>(_ title: String, detail: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 16))
                Text(detail).font(.system(size: 13)).foregroundStyle(MacTheme.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            content()
        }.padding(.horizontal, 20).padding(.vertical, 14)
    }
}

/// The small label over a heads-up in the chat: what it is about and when it came in.
struct MacHeadsUpTag: View {
    let tag: HeadsUpTag
    let date: Date

    private var symbol: String {
        switch tag.kind {
        case "email": return "envelope.fill"
        case "meeting": return "calendar"
        case "conflict": return "exclamationmark.triangle.fill"
        case "brief": return "sun.max.fill"
        case "moved": return "arrow.triangle.2.circlepath"
        case "delivery": return "shippingbox.fill"
        case "nudge": return "arrowshape.turn.up.left.fill"
        case "reminder": return "checklist"
        default: return "sparkles"
        }
    }
    private var label: String {
        switch tag.kind {
        case "email": return "Inbox"
        case "meeting": return "Up next"
        case "conflict": return "Calendar"
        case "brief": return "Morning brief"
        case "moved": return "Moved"
        case "delivery": return "Delivery"
        case "nudge": return "Waiting on you"
        case "reminder": return "Reminder"
        default: return "Heads-up"
        }
    }
    private var tint: Color {
        switch tag.kind {
        case "email": return MacTheme.unread
        case "meeting": return Color.green
        case "conflict": return MacTheme.attention
        case "brief": return Color.orange
        case "moved": return Color.indigo
        case "delivery": return Color.brown
        case "nudge": return Color.cyan
        case "reminder": return Color.pink
        default: return MacTheme.secondary
        }
    }

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: symbol).font(.system(size: 10, weight: .bold)).foregroundStyle(.white)
                .frame(width: 20, height: 20).background(tint, in: Circle())
            Text(label).font(.system(size: 12, weight: .semibold))
            Text("· " + date.formatted(date: .omitted, time: .shortened)).font(.system(size: 12))
        }
        .foregroundStyle(MacTheme.secondary).padding(.leading, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Heads-up, \(label), \(date.formatted(date: .omitted, time: .shortened))")
    }
}


/// What you can do with a heads-up, right under it (0.9.7). Drafting fills in the message box; nothing is sent until you send it.
struct MacHeadsUpActions: View {
    let entry: Entry
    let tag: HeadsUpTag
    @EnvironmentObject private var app: AppModel
    @EnvironmentObject private var desktop: MacAppModel

    private var senders: [HeadsUpSender] { tag.senders ?? [] }
    private var joinURL: URL? {
        guard let link = tag.link, ["meeting", "moved"].contains(tag.kind), let url = URL(string: link), url.scheme == "https" else { return nil }
        return url
    }

    var body: some View {
        HStack(spacing: 6) {
            if let url = joinURL { MacPillButton(title: "Join", prominent: true) { NSWorkspace.shared.open(url) } }
            if senders.count == 1 {
                pill("Draft a reply") { draft(senders[0]) }
            } else if senders.count > 1 {
                Menu("Draft a reply…") {
                    ForEach(Array(senders.enumerated()), id: \.offset) { item in Button("Reply to \(name(item.element))") { draft(item.element) } }
                }.menuStyle(.button).buttonStyle(.borderless).fixedSize()
            }
            if tag.kind == "conflict" { pill("Help me choose") { prefill("Help me decide what to do about this overlap: " + (entry.text.components(separatedBy: "\n").first ?? entry.text)) } }
            if tag.kind == "brief" { pill("Plan my day") { prefill("Help me plan the rest of today around my calendar.") } }
            Menu("Snooze") {
                Button("For 1 hour") { desktop.headsUps.snooze(entry, minutes: 60, app: app) }
                Button("For 3 hours") { desktop.headsUps.snooze(entry, minutes: 180, app: app) }
            }.menuStyle(.button).buttonStyle(.borderless).fixedSize()
            if senders.contains(where: { !$0.address.isEmpty }) {
                Menu {
                    ForEach(Array(senders.filter { !$0.address.isEmpty }.enumerated()), id: \.offset) { item in
                        Button("Stop heads-ups from \(name(item.element))") { desktop.headsUps.mute(item.element.address) }
                    }
                } label: { Image(systemName: "ellipsis") }
                .menuStyle(.button).buttonStyle(.borderless).fixedSize().help("More actions")
            }
            Button("Done") { app.collapseHeadsUp(entry.id, text: "Dismissed · \(tag.title ?? "Heads-up")") }
                .buttonStyle(.plain).font(.system(size: 13)).foregroundStyle(MacTheme.secondary).help("Collapse this heads-up to one line")
        }
        .font(.system(size: 13))
    }

    private func name(_ sender: HeadsUpSender) -> String { sender.name.isEmpty ? sender.address : sender.name }
    private func pill(_ title: String, action: @escaping () -> Void) -> some View { MacPillButton(title: title, prominent: false, action: action) }
    private func prefill(_ text: String) { desktop.drafts[entry.botID] = text }
    private func draft(_ sender: HeadsUpSender) {
        prefill("Draft a reply to \(name(sender))" + (sender.subject.map { " about “\($0)”" } ?? "") + ". Show it to me before sending.")
    }
}

/// Today (0.9.7): the next meeting with a countdown and Join, and what else is waiting, over the top of Grok Bot's chat.
struct MacTodayCard: View {
    @ObservedObject var headsUps: MacHeadsUps

    var body: some View {
        if let today = headsUps.today {
            TimelineView(.periodic(from: .now, by: 30)) { context in
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 10) {
                        Text(today.next == nil ? "TODAY" : "NEXT").font(.system(size: 11, weight: .semibold)).tracking(0.6).foregroundStyle(MacTheme.secondary)
                        if let next = today.next {
                            Text(next.title).font(.system(size: 15, weight: .semibold)).lineLimit(1)
                            Text(relative(next.start, now: context.date)).font(.system(size: 13)).monospacedDigit().foregroundStyle(MacTheme.secondary)
                            Spacer(minLength: 8)
                            if let link = next.link, let url = URL(string: link), url.scheme == "https" {
                                MacPillButton(title: "Join", prominent: true) { NSWorkspace.shared.open(url) }
                            }
                        } else {
                            Text("No more meetings today").font(.system(size: 15, weight: .semibold))
                            Spacer()
                        }
                    }
                    let facts = facts(today)
                    if !facts.isEmpty { Text(facts.joined(separator: "   ·   ")).font(.system(size: 12)).foregroundStyle(MacTheme.secondary) }
                }
                .padding(.horizontal, 16).padding(.vertical, 12)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(MacTheme.line))
                .accessibilityElement(children: .contain).accessibilityLabel("Today")
            }
        }
    }

    private func relative(_ start: Date, now: Date) -> String {
        let minutes = Int((start.timeIntervalSince(now) / 60).rounded())
        return minutes <= 0 ? "now" : minutes < 60 ? "in \(minutes) min" : "at \(HeadsUpRules.time(start))"
    }
    private func facts(_ today: HeadsUpToday) -> [String] {
        var list: [String] = []
        if today.remaining > 1 { list.append("\(today.remaining) meetings left") }
        if let waiting = today.waiting { list.append(waiting == 0 ? "Inbox clear" : "\(waiting) email\(waiting == 1 ? "" : "s") waiting on you") }
        if today.overlaps > 0 { list.append("⚠︎ \(today.overlaps) overlap\(today.overlaps == 1 ? "" : "s")") }
        return list
    }
}


/// Settings → API Keys → Image & video (0.9.7). Keys stay in the Keychain; the app calls the provider, never the Bot.
struct MacMediaKeysView: View {
    @State private var drafts: [MediaProvider: String] = [:]
    @State private var saved: Set<MediaProvider> = Set(MediaKeys.ready)
    @State private var feedback: String?
    @AppStorage("media.default.image") private var imageDefault = ""
    @AppStorage("media.default.video") private var videoDefault = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Image & video").font(.system(size: 18, weight: .medium))
            Text("Add a key and any Bot can make pictures or videos when you ask. The app calls the provider with your key, saves the result in that Bot’s folder and shows it in the chat. Each provider bills its own account.")
                .font(.system(size: 14)).lineSpacing(4).foregroundStyle(MacTheme.secondary).fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 0) {
                ForEach(MediaProvider.allCases) { provider in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(provider.name).font(.system(size: 15, weight: .medium))
                            Spacer()
                            Text(saved.contains(provider) ? "Key saved" : "No key").font(.system(size: 12)).foregroundStyle(MacTheme.secondary)
                        }
                        HStack(spacing: 8) {
                            SecureField(saved.contains(provider) ? "Saved — paste a new key to replace" : "Paste API key", text: Binding(get: { drafts[provider] ?? "" }, set: { drafts[provider] = $0 }))
                                .textFieldStyle(.roundedBorder).accessibilityLabel("\(provider.name) API key")
                            MacPillButton(title: "Save", prominent: false) { save(provider) }
                            if saved.contains(provider) { MacPillButton(title: "Remove", prominent: false) { remove(provider) } }
                            Link("Get a key ↗", destination: provider.keyHelp).font(.system(size: 12))
                        }
                        HStack(spacing: 12) {
                            ForEach(provider.kinds, id: \.self) { kind in
                                HStack(spacing: 6) {
                                    Text(kind == "video" ? "Video model" : "Image model").font(.system(size: 12)).foregroundStyle(MacTheme.secondary)
                                    TextField(provider.defaultModel(kind), text: modelBinding(provider, kind)).textFieldStyle(.roundedBorder).frame(width: 230)
                                }
                            }
                        }
                    }.padding(.horizontal, 20).padding(.vertical, 14)
                    if provider != MediaProvider.allCases.last { Rectangle().fill(MacTheme.line).frame(height: 1).padding(.leading, 20) }
                }
            }.background(MacTheme.panel, in: RoundedRectangle(cornerRadius: 18))
            HStack(spacing: 20) {
                defaultPicker("Default for images", kind: "image", selection: $imageDefault)
                defaultPicker("Default for videos", kind: "video", selection: $videoDefault)
            }
            if let feedback { Text(feedback).font(.system(size: 12)).foregroundStyle(MacTheme.secondary) }
        }
    }

    private func modelBinding(_ provider: MediaProvider, _ kind: String) -> Binding<String> {
        let key = "media.model.\(provider.rawValue).\(kind)"
        return Binding(get: { UserDefaults.standard.string(forKey: key) ?? "" }, set: { value in
            let clean = value.trimmingCharacters(in: .whitespaces)
            if clean.isEmpty || MediaGenerator.validModel(clean) { UserDefaults.standard.set(clean, forKey: key); feedback = nil }
            else { feedback = "Write models like flux-pro-1.1 or owner/name." }
        })
    }

    private func defaultPicker(_ title: String, kind: String, selection: Binding<String>) -> some View {
        Picker(title, selection: selection) {
            Text("First one with a key").tag("")
            ForEach(MediaProvider.allCases.filter { $0.kinds.contains(kind) }) { provider in Text(provider.shortName).tag(provider.rawValue) }
        }.frame(maxWidth: 320)
    }

    private func save(_ provider: MediaProvider) {
        let text = drafts[provider] ?? ""
        do {
            if try MediaKeys.save(text, for: provider) { saved.insert(provider); drafts[provider] = ""; feedback = "\(provider.shortName) key saved." }
            else { feedback = "That does not look like an API key. Paste only the key, with no spaces or line breaks." }
        } catch { feedback = "The key could not be saved in the Keychain." }
    }

    private func remove(_ provider: MediaProvider) {
        do { try MediaKeys.remove(provider); saved.remove(provider); feedback = "\(provider.shortName) key removed." } catch { feedback = "The key could not be removed." }
    }
}
