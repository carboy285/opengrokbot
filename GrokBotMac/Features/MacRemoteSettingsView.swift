import SwiftUI

/// Settings of the computer being viewed, shown while this window is a remote for it. Everything here describes and changes THAT computer.
struct MacRemoteSettingsView: View {
    @EnvironmentObject private var desktop: MacAppModel
    @State private var settings: RemoteHostSettings?
    @State private var loading = true
    @State private var problem: String?
    @State private var drafts: [String: String] = [:]
    @State private var feedback: String?

    private let keyProviders: [CLIProvider] = CLIProvider.allCases.filter { ProviderAPIKeys.info(for: $0) != nil }

    private var name: String { desktop.gateway?.hostName ?? "the other computer" }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("Settings for \(name)").font(.system(size: 25, weight: .medium))
                Spacer()
                Button { desktop.panel = nil } label: { Image(systemName: "xmark").frame(width: 38, height: 38) }.buttonStyle(.plain).accessibilityLabel("Close settings")
            }
            Text("You are viewing \(name). These are its settings, and changes here are made on it, not on this Mac.").font(.system(size: 13)).foregroundStyle(MacTheme.secondary)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let settings { content(settings) }
                    else if loading { HStack { ProgressView().controlSize(.small); Text("Loading \(name)’s settings…").foregroundStyle(MacTheme.secondary) } }
                    if let problem { card { Text(problem).font(.system(size: 13)).foregroundStyle(.orange) } }
                    card {
                        Text("This Mac").font(.system(size: 16, weight: .medium))
                        Text("Looking for this Mac’s own settings (display name, phone access, backups, API keys)?").font(.system(size: 12)).foregroundStyle(MacTheme.secondary)
                        MacPillButton(title: "Open this Mac’s settings") { desktop.settingsTab = .general; desktop.panel = .settings }
                    }
                }.frame(maxWidth: 760, alignment: .leading).frame(maxWidth: .infinity)
            }
        }
        .padding(34)
        .task { await load() }
    }

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10, content: content).padding(20).frame(maxWidth: .infinity, alignment: .leading)
            .background(MacTheme.raised, in: RoundedRectangle(cornerRadius: 16))
    }

    @ViewBuilder private func content(_ s: RemoteHostSettings) -> some View {
        card {
            Text("Computer").font(.system(size: 16, weight: .medium))
            row("Name", s.hostName)
            row("System", s.platform == "windows" ? "Windows" : "Mac")
            row("OpenGrokBot version", s.appVersion)
            row("Share keys and connectors", s.sharing ? "On" : "Off")
            if !s.sharing { Text("Turn it on at \(s.hostName) (Settings → Computer on Windows, the Computers screen on Mac) before keys can be changed from here.").font(.system(size: 12)).foregroundStyle(MacTheme.secondary) }
        }
        card {
            Text("AI CLIs on \(s.hostName)").font(.system(size: 16, weight: .medium))
            if s.providers.isEmpty { Text("No AI CLI is installed there yet. Install one on \(s.hostName).").font(.system(size: 13)).foregroundStyle(MacTheme.secondary) }
            ForEach(s.providers) { provider in row(provider.provider.name + (provider.provider == s.defaultProvider ? " · default" : ""), "version " + provider.version) }
        }
        card {
            Text("API keys on \(s.hostName)").font(.system(size: 16, weight: .medium))
            Text("A key replaces that CLI’s own sign-in on \(s.hostName). It is sent only inside your encrypted account link and stored in its secure storage.").font(.system(size: 12)).lineSpacing(3).foregroundStyle(MacTheme.secondary)
            ForEach(keyProviders) { provider in
                let isSet = s.apiKeys[provider.rawValue] == true
                HStack(spacing: 10) {
                    Text(provider.name).frame(width: 110, alignment: .leading)
                    Text(isSet ? "Key saved" : "Not set").font(.system(size: 12)).foregroundStyle(isSet ? Color.green : MacTheme.secondary).frame(width: 70, alignment: .leading)
                    SecureField("Paste a key", text: Binding(get: { drafts[provider.rawValue] ?? "" }, set: { drafts[provider.rawValue] = $0 })).textFieldStyle(.roundedBorder)
                    MacPillButton(title: "Save") { Task { await save(provider, key: drafts[provider.rawValue] ?? "") } }.disabled(!s.sharing || (drafts[provider.rawValue] ?? "").isEmpty)
                    if isSet { MacPillButton(title: "Remove") { Task { await save(provider, key: "") } }.disabled(!s.sharing) }
                }
            }
            if let feedback { Text(feedback).font(.system(size: 12)).foregroundStyle(MacTheme.secondary) }
        }
        card {
            Text("Voice keys on \(s.hostName)").font(.system(size: 16, weight: .medium))
            let set = s.voiceKeys.filter { $0.value }.keys.sorted()
            Text(set.isEmpty ? "No voice keys are saved there." : "Saved for: " + set.joined(separator: ", ")).font(.system(size: 13)).foregroundStyle(MacTheme.secondary)
        }
        card {
            Text("Connectors on \(s.hostName)").font(.system(size: 16, weight: .medium))
            Text(s.connectors.configured ? "Connected apps: " + s.connectors.toolkits.sorted().joined(separator: ", ") : "No connector project is set up there.").font(.system(size: 13)).foregroundStyle(MacTheme.secondary)
            Text("To change connectors, use Connect apps on \(s.hostName), or copy yours with the Computers screen.").font(.system(size: 12)).foregroundStyle(MacTheme.secondary)
        }
        card {
            Text("Usage").font(.system(size: 16, weight: .medium))
            Text("\(s.hostName) doesn’t report usage to other computers yet. Open it directly to see its usage.").font(.system(size: 13)).foregroundStyle(MacTheme.secondary)
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack { Text(label).foregroundStyle(MacTheme.secondary); Spacer(); Text(value).textSelection(.enabled) }.font(.system(size: 13))
    }

    private func load() async {
        loading = true; problem = nil
        defer { loading = false }
        guard let gateway = desktop.gateway else { problem = "Switch to another computer first."; return }
        for _ in 0..<10 where !gateway.hasSnapshot { try? await Task.sleep(for: .seconds(1)) }
        do { settings = try await gateway.hostSettings() }
        catch { problem = "\(name) didn’t answer: " + ((error as? LocalizedError)?.errorDescription ?? error.localizedDescription) + " Update OpenGrokBot there to 0.8.5 if it is older." }
    }

    private func save(_ provider: CLIProvider, key: String) async {
        guard let gateway = desktop.gateway else { return }
        do {
            try await gateway.setAPIKey(key, for: provider)
            drafts[provider.rawValue] = ""
            feedback = key.isEmpty ? "Removed the \(provider.name) key on \(name)." : "Saved the \(provider.name) key on \(name)."
            settings = try? await gateway.hostSettings()
        } catch { feedback = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription }
    }
}
