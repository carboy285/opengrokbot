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
                        case .computer: computer
                        case .permissions: unavailable(title: "Your CLI keeps its permissions", detail: "Codex runs with read-only workspace access. Other CLIs keep their own configured permissions. This app does not add approval-bypass flags or auto-approve tools.", icon: "shield")
                        case .apiKeys: MacAPIKeysView()
                        case .secureLogins: MacSecureLoginsView()
                        case .vault: MacVaultView()
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
