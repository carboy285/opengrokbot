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
                            Text("Independent client foundation").font(.caption).foregroundStyle(.secondary)
                        }
                    }.padding(.vertical, 8)
                    NavigationLink { IntegrationView() } label: {
                        Label("Integration status", systemImage: "cable.connector")
                    }
                } footer: { Text("Not affiliated with xAI or Cursor. No account is connected.") }
                Section("Appearance") {
                    Picker("Theme", selection: $appearance) {
                        Text("Follow system").tag("system")
                        Text("Dark").tag("dark")
                        Text("Light").tag("light")
                    }
                }
                if model.previewEnabled {
                    Section("Offline preview") {
                        LabeledContent("Storage", value: "On this device")
                        LabeledContent("Preview Bots", value: "\(model.workspace.bots.count)")
                        Button("Leave preview") { model.leavePreview(); dismiss() }
                        Button("Reset preview data", role: .destructive) { reset = true }
                    } footer: { Text("Leaving preview keeps local notes. Reset replaces preview Bots and notes with the example workspace.") }
                }
                Section("Learn more") {
                    Link(destination: URL(string: "https://docs.x.ai/grok-bot/overview")!) { Label("Official Grok Bot documentation", systemImage: "arrow.up.right.square") }
                    Link(destination: URL(string: "https://docs.x.ai/grok-bot/mobile")!) { Label("Official mobile setup", systemImage: "iphone") }
                }
                Section {
                    LabeledContent("App version", value: "0.1.0")
                    LabeledContent("Verified harness versions", value: "None")
                    Text("Voice, connectors, Vault, computer access, task execution, and approvals require a verified protocol. This build does not offer these workflows.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .confirmationDialog("Replace all local preview notes and Bots?", isPresented: $reset, titleVisibility: .visible) {
                Button("Reset preview", role: .destructive) { model.resetPreview() }
            }
        }
    }
}

struct IntegrationView: View {
    @EnvironmentObject private var model: AppModel
    @AppStorage("connectionDraft") private var storedDraft = ""
    @State private var address = ""
    @State private var feedback: String?
    @State private var invalid = false

    var body: some View {
        Form {
            Section {
                Label("Not connected", systemImage: "circle.slash").font(.headline)
                Text(model.client.capabilities.reason).foregroundStyle(.secondary)
                Text("No network request is made by this app. The Connect workflow will be implemented after transport and authentication are verified.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("Verified product facts") {
                Label("Persistent Bots and a cloud computer", systemImage: "desktopcomputer")
                Label("Cursor account, browser sign-in", systemImage: "person.crop.circle")
                Label("Official iOS companion exists", systemImage: "iphone")
                Link("Read official setup documentation", destination: URL(string: "https://docs.x.ai/grok-bot/get-started")!)
            }
            Section {
                TextField("https://your-server.example", text: $address)
                    .keyboardType(.URL).textContentType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                    .accessibilityLabel("Future server origin, optional")
                Button("Save address draft") {
                    do {
                        let draft = try ConnectionDraft(address: address)
                        storedDraft = draft.origin.absoluteString
                        address = storedDraft
                        feedback = "Address saved locally. Compatibility is unverified; no connection was attempted."
                        invalid = false
                    } catch {
                        feedback = (error as? IntegrationError)?.errorDescription ?? "Check the server address."
                        invalid = true
                    }
                }
                if !storedDraft.isEmpty {
                    Button("Clear saved address", role: .destructive) { storedDraft = ""; address = ""; feedback = nil }
                }
                if let feedback {
                    Label(feedback, systemImage: invalid ? "exclamationmark.circle" : "doc.badge.checkmark")
                        .font(.footnote).foregroundStyle(.secondary).accessibilityAddTraits(.updatesFrequently)
                }
            } header: { Text("Optional future connection") } footer: { Text("Only save a server origin if you plan to operate a supported bridge. This is not a Grok Bot endpoint setting. No bridge or token-provisioning method is verified. Do not enter credentials or secret URLs.") }
            Section("What is needed") {
                Text("An inspected 0.78.1 bundle, versioned protocol schemas, browser authentication and callback rules, plus authorized service access. The project includes tools to inspect your local DMG on a Mac.")
                Text("A generic Grok model API key does not establish access to your existing Bots or their computer.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Integration")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { address = storedDraft }
    }
}
