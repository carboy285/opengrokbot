import AppKit
import SwiftUI

struct MacSettingsView: View {
    @EnvironmentObject private var app: AppModel
    @EnvironmentObject private var desktop: MacAppModel
    @AppStorage("macAppearance") private var appearance = "dark"
    @AppStorage("spellChecking") private var spellChecking = true
    @AppStorage("profileName") private var profileName = "Local preview"
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
                Text("OpenGrokBot 0.2.0").font(.system(size: 11)).foregroundStyle(MacTheme.secondary)
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
                        case .permissions: unavailable(title: "Permissions belong to your connected Bot", detail: "Auto-review and approval rules are managed by Grok Bot. No rules are read or changed in offline preview.", icon: "shield")
                        case .vault: MacVaultView()
                        case .usage: unavailable(title: "No usage to report", detail: "This app has made no model or service requests. Your Grok Bot subscription usage will be available after a verified connection.", icon: "chart.bar")
                        case .updates: updates
                        }
                    }.padding(.horizontal, 36).padding(.bottom, 34).frame(maxWidth: .infinity, alignment: .leading)
                }
            }.background(MacTheme.canvas)
        }
        .confirmationDialog("Replace all local preview Bots and notes?", isPresented: $reset, titleVisibility: .visible) {
            Button("Reset preview", role: .destructive) { app.resetPreview(); desktop.selectedID = app.workspace.bots.first?.id }
        }
    }

    private var general: some View {
        Group {
            HStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("One place for your AI teammates").font(.system(size: 18, weight: .medium))
                    Text("Grok Bot’s official plans bring your Bots and their tools together. Learn what’s included in the service.")
                        .font(.system(size: 15)).lineSpacing(5).foregroundStyle(MacTheme.secondary)
                    MacPillButton(title: "View official plans", prominent: true) { openDocumentation("https://docs.x.ai/grok-bot/get-started") }
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
                    Text("LP").font(.system(size: 21)).foregroundStyle(MacTheme.secondary)
                        .frame(width: 56, height: 56).background(MacTheme.raised, in: Circle())
                    VStack(alignment: .leading, spacing: 6) {
                        TextField("Display name", text: $profileName).textFieldStyle(.plain).font(.system(size: 17))
                        Text("Local workspace · Not signed in").font(.system(size: 14)).foregroundStyle(MacTheme.secondary)
                    }
                    Spacer()
                    MacPillButton(title: "Connection status") { desktop.panel = .integration }
                }.padding(20)
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
                    Text("Preview Bots and notes").font(.system(size: 15))
                    Spacer()
                    MacPillButton(title: "Reset preview…") { reset = true }
                }.padding(18)
            }
        }
    }

    private var computer: some View {
        Group {
            unavailable(title: "Your Bot’s computer", detail: "Grok Bot works on a hosted computer. This independent app has not established access to that computer, so screen viewing, terminal control, and resets are unavailable.", icon: "desktopcomputer")
            section("This Mac") {
                VStack(spacing: 0) {
                    settingRow("Time zone") { Text(TimeZone.current.identifier).foregroundStyle(MacTheme.secondary) }
                    settingRow("App storage") { Text("Application Support/OpenGrokBot").font(.system(size: 12)).foregroundStyle(MacTheme.secondary) }
                }
            }
        }
    }

    private var updates: some View {
        VStack(alignment: .leading, spacing: 20) {
            unavailable(title: "OpenGrokBot 0.2.0", detail: "Install a new build from this project’s release artifacts. This build does not modify or update the official Grok Bot application.", icon: "arrow.down.circle")
            MacPillButton(title: "Open project") { openDocumentation("https://github.com/carboy285/opengrokbot") }
        }
    }

    private func unavailable(title: String, detail: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Image(systemName: icon).font(.system(size: 36, weight: .light)).foregroundStyle(MacTheme.secondary)
            Text(title).font(.system(size: 23, weight: .medium))
            Text(detail).font(.system(size: 16)).lineSpacing(5).foregroundStyle(MacTheme.secondary)
            Button("View connection status") { desktop.panel = .integration }.buttonStyle(.link)
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
