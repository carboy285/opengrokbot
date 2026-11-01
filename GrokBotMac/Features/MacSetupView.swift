import AppKit
import SwiftUI

struct MacSetupView: View {
    @EnvironmentObject private var desktop: MacAppModel
    @State private var step = 0
    @State private var provider = CLIProvider.codex
    private var installation: InstalledCLI? { desktop.installedCLIs.first { $0.provider == provider } }

    var body: some View {
        VStack(spacing: 22) {
            HStack {
                Text("Set up Grok Bot").font(.system(size: 21, weight: .medium))
                Spacer()
                Text("\(step + 1) of 6").font(.system(size: 13)).foregroundStyle(MacTheme.secondary)
                Button { desktop.panel = nil } label: { Image(systemName: "xmark").frame(width: 34, height: 34) }.buttonStyle(.plain).accessibilityLabel("Close setup")
            }
            HStack(spacing: 7) {
                ForEach(0..<6) { index in Capsule().fill(index <= step ? Color.primary : MacTheme.raised).frame(height: 3) }
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 23) {
                    switch step {
                    case 0: welcome
                    case 1: choose
                    case 2: install
                    case 3: signIn
                    case 4: MacComposioSetupView(service: desktop.composio)
                    default: ready
                    }
                }.frame(maxWidth: 650, alignment: .leading).padding(.vertical, 20).frame(maxWidth: .infinity)
            }
            HStack(spacing: 15) {
                if step > 0 { MacPillButton(title: "Back") { step -= 1 } }
                else { Button("Finish later") { desktop.panel = nil }.buttonStyle(.link) }
                Spacer()
                if step < 5 {
                    MacPillButton(title: step == 4 ? "Continue to chat" : "Continue", prominent: true) {
                        if let installation { desktop.chooseCLI(installation.id) }
                        step += 1
                    }.disabled((step == 2 && installation == nil) || (step == 3 && (!desktop.loginVerified || installation == nil)))
                } else {
                    MacPillButton(title: "Start chatting", prominent: true) { desktop.completeSetup() }.disabled(installation == nil)
                }
            }
        }
        .padding(32)
        .onAppear { desktop.refreshCLIs(); if let requested = desktop.setupProvider { provider = requested; desktop.setupProvider = nil } else if let current = desktop.selectedCLI { provider = current.provider } }
        .onChange(of: provider) { _, _ in desktop.loginVerified = false; desktop.setupFeedback = nil; if let installation { desktop.chooseCLI(installation.id) } }
        .onChange(of: desktop.installedCLIs) { _, _ in if let installation { desktop.chooseCLI(installation.id) } }
    }

    private var welcome: some View {
        Group {
            MacBotAvatar(size: 92, starred: true).padding(.bottom, 12)
            Text("A free app for your AI CLIs").font(.system(size: 33, weight: .semibold)).tracking(-0.8)
            Text("Start with one assistant named Grok Bot. Connect a CLI installed on this Mac, sign in with that CLI, and send your first message.")
                .font(.system(size: 18)).lineSpacing(6)
            info("No app subscription", "OpenGrokBot is free and open source. AI usage follows your chosen CLI account, provider limits, or local model setup. Free AI access is not guaranteed by this app.", icon: "heart")
            info("Your existing setup", "The CLI keeps its own credentials and model configuration. This app does not ask you to paste account secrets into source code.", icon: "terminal")
        }
    }

    private var choose: some View {
        Group {
            Text("Choose an AI CLI").font(.system(size: 29, weight: .medium))
            Text("We look for installed CLIs on this Mac. You can switch providers later without mixing their saved conversations.").foregroundStyle(MacTheme.secondary)
            ForEach(CLIProvider.allCases) { candidate in
                let found = desktop.installedCLIs.first { $0.provider == candidate }
                Button { provider = candidate } label: {
                    HStack(spacing: 14) {
                        Image(systemName: "terminal").font(.system(size: 21)).frame(width: 31)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(candidate.name).font(.system(size: 17, weight: .medium))
                            Text(found?.version ?? "Not installed").font(.system(size: 12)).foregroundStyle(MacTheme.secondary)
                        }
                        Spacer()
                        Image(systemName: provider == candidate ? "checkmark.circle.fill" : "circle").font(.system(size: 19))
                    }.padding(15).background(MacTheme.panel, in: RoundedRectangle(cornerRadius: 14))
                }.buttonStyle(.plain)
            }
            HStack {
                Button(desktop.scanningCLIs ? "Scanning…" : "Scan again") { desktop.refreshCLIs() }.disabled(desktop.scanningCLIs)
                Spacer()
                Button("Choose executable…") { chooseExecutable() }
            }
        }
    }

    private var install: some View {
        Group {
            Text("Install \(provider.name)").font(.system(size: 29, weight: .medium))
            if let installation {
                Label("Already installed", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                Text(installation.path).font(.system(size: 13, design: .monospaced)).textSelection(.enabled)
                Text("You can continue to sign in. If this is not the installation you want, choose another executable.").foregroundStyle(MacTheme.secondary)
            } else {
                Text("Install the CLI on this Mac, then return here and scan again. The app never installs packages or changes your system in the background.")
                    .font(.system(size: 17)).lineSpacing(5)
                if provider != .grok {
                    Text("If you use npm, install Node.js first, then run:").foregroundStyle(MacTheme.secondary)
                    command(provider.installCommand)
                    Link("Get Node.js ↗", destination: URL(string: "https://nodejs.org/en/download")!)
                }
            }
            HStack {
                Link("Official install guide ↗", destination: provider.guideURL)
                Spacer()
                MacPillButton(title: desktop.scanningCLIs ? "Scanning…" : "Scan again") { desktop.refreshCLIs() }.disabled(desktop.scanningCLIs)
            }
            Button("Choose executable…") { chooseExecutable() }.buttonStyle(.link)
            info("Nothing is bundled or simulated", "Only a CLI actually installed on your Mac can answer. Its own model and account configuration determine availability and cost.", icon: "checkmark.shield")
        }
    }

    private var signIn: some View {
        Group {
            Text("Sign in through \(provider.name)").font(.system(size: 29, weight: .medium))
            Text("Open Terminal and run the command below. Follow the CLI’s browser or provider login, then return to this app.")
                .font(.system(size: 17)).lineSpacing(5)
            command(provider.loginCommand)
            HStack {
                MacPillButton(title: "Open Terminal") { NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app")) }
                MacPillButton(title: desktop.checkingLogin ? "Checking…" : (provider == .codex ? "Check sign-in" : "I’ve configured this CLI"), prominent: true) {
                    if let installation { desktop.chooseCLI(installation.id) }
                    desktop.checkLogin()
                }.disabled(desktop.checkingLogin || installation == nil)
            }
            if let feedback = desktop.setupFeedback { Text(feedback).foregroundStyle(MacTheme.secondary).lineSpacing(5) }
            info("Credentials stay with the CLI", "OpenGrokBot does not copy your login token. Codex sign-in can be checked locally; other providers validate their configured account when you send a message.", icon: "lock")
        }
    }

    private var ready: some View {
        Group {
            MacBotAvatar(size: 78, starred: true)
            Text("Ready for your first message").font(.system(size: 29, weight: .medium))
            Text("Grok Bot starts with an empty conversation. Add other Bots only when you choose to. Each Bot keeps a separate session with the selected CLI.")
                .font(.system(size: 18)).lineSpacing(6)
            if let installation { Label("\(installation.provider.name) on this Mac", systemImage: "terminal").font(.headline) }
            info("You stay in control", "The app does not add approval-bypass flags. Codex uses read-only workspace access; other CLIs keep their own permission settings. You can stop a response at any time.", icon: "hand.raised")
        }
    }

    private func command(_ text: String) -> some View {
        HStack {
            Text(text).font(.system(size: 14, design: .monospaced)).textSelection(.enabled)
            Spacer()
            Button("Copy") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(text, forType: .string) }
        }.padding(17).background(MacTheme.raised, in: RoundedRectangle(cornerRadius: 13))
    }
    private func info(_ title: String, _ detail: String, icon: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon).font(.system(size: 21)).frame(width: 28)
            VStack(alignment: .leading, spacing: 7) { Text(title).font(.headline); Text(detail).font(.system(size: 14)).lineSpacing(4).foregroundStyle(MacTheme.secondary) }
        }.padding(20).frame(maxWidth: .infinity, alignment: .leading).background(MacTheme.panel, in: RoundedRectangle(cornerRadius: 16))
    }
    private func chooseExecutable() {
        let panel = NSOpenPanel(); panel.canChooseDirectories = false; panel.canChooseFiles = true; panel.allowsMultipleSelection = false
        panel.message = "Choose the \(provider.name) CLI executable installed on this Mac."
        if panel.runModal() == .OK, let url = panel.url { desktop.setCLIPath(url.path, provider: provider) }
    }
}
