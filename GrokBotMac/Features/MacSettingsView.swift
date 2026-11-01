import AppKit
import SwiftUI

struct MacSettingsView: View {
    @EnvironmentObject private var app: AppModel
    @EnvironmentObject private var desktop: MacAppModel
    @AppStorage("macAppearance") private var appearance = "dark"
    @AppStorage("spellChecking") private var spellChecking = true
    @AppStorage("profileName") private var profileName = "You"
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
                        case .vault: MacVaultView()
                        case .usage: unavailable(title: "AI usage belongs to your CLI account", detail: "OpenGrokBot has no subscription or inference fees of its own. Your chosen CLI provider may have usage limits or charges. No account usage percentage is guessed here.", icon: "chart.bar")
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
                    settingRow("Accent") { Text("Bot color").foregroundStyle(MacTheme.secondary) }
                    settingRow("Language") { Text("English").foregroundStyle(MacTheme.secondary) }
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
            Button("View another computer on this account") { desktop.panel = nil; desktop.showMirror = true }
            section("This Mac") {
                VStack(spacing: 0) {
                    settingRow("Time zone") { Text(TimeZone.current.identifier).foregroundStyle(MacTheme.secondary) }
                    settingRow("App storage") { Text("Application Support/OpenGrokBot").font(.system(size: 12)).foregroundStyle(MacTheme.secondary) }
                }
            }
        }
    }

    private var updates: some View { DesktopUpdatesView(updates: desktop.updates) }

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
