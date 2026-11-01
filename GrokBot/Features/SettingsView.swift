import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @AppStorage("appearance") private var appearance = "dark"
    @State private var reset = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 16) {
                        BotAvatar(size: 42)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("OpenGrokBot").font(.headline)
                            Text("Free app for local AI CLIs").font(.caption).foregroundStyle(.secondary)
                        }
                    }.padding(.vertical, 8)
                    NavigationLink { IntegrationView() } label: {
                        Label("Desktop setup guide", systemImage: "cable.connector")
                    }
                } footer: { Text("Independent open-source app. Your CLI account and Composio project have their own usage limits.") }
                Section("Appearance") {
                    Picker("Theme", selection: $appearance) {
                        Text("Follow system").tag("system")
                        Text("Dark").tag("dark")
                        Text("Light").tag("light")
                    }
                }
                if model.previewEnabled {
                    Section {
                        LabeledContent("Storage", value: "On this device")
                        LabeledContent("Bots", value: "\(model.workspace.bots.count)")
                        Button("Reset conversations", role: .destructive) { reset = true }
                    } header: { Text("Local workspace") } footer: { Text("Reset removes local conversations and additional Bots, leaving one empty Grok Bot.") }
                }
                Section("Learn more") {
                    Link(destination: URL(string: "https://github.com/carboy285/opengrokbot")!) { Label("Project and downloads", systemImage: "arrow.up.right.square") }
                    Link(destination: URL(string: "https://docs.composio.dev")!) { Label("Composio documentation", systemImage: "iphone") }
                }
                Section {
                    LabeledContent("App version", value: "0.4.0")
                    LabeledContent("CLI hosting", value: "Mac or Windows")
                    Text("The desktop apps run installed AI CLIs and connect tools with Composio. The iPhone host bridge is not implemented in this build.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .confirmationDialog("Remove local conversations and additional Bots?", isPresented: $reset, titleVisibility: .visible) {
                Button("Reset conversations", role: .destructive) { model.resetPreview() }
            }
        }
    }
}

struct IntegrationView: View {
    var body: some View {
        Form {
            Section {
                Label("Set up your desktop first", systemImage: "desktopcomputer").font(.headline)
                Text("AI CLIs run on the computer hosting them. iOS cannot launch a desktop CLI directly.")
            }
            Section("1 · Choose an AI CLI") {
                Text("Open the Mac or Windows app and follow setup. Choose Codex, Claude Code, Grok Build, OpenCode, or Gemini CLI. Install it and sign in using its own guide.")
                Link("Get the desktop app", destination: URL(string: "https://github.com/carboy285/opengrokbot")!)
            }
            Section("2 · Connect tools, optionally") {
                Text("In desktop setup, enter your Composio project key, choose tools, and authorize connections in your browser. You can also do this later in Connect Apps.")
                Link("Create a Composio project", destination: URL(string: "https://platform.composio.dev")!)
            }
            Section("iPhone connection") {
                Text("This build does not yet include a desktop host bridge. Chat from the desktop app until secure host pairing is available. No iPhone messages are sent or simulated.")
            }
        }.navigationTitle("Setup").navigationBarTitleDisplayMode(.inline)
    }
}
