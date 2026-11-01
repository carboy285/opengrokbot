import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var remote: RemoteController
    @Environment(\.dismiss) private var dismiss
    @AppStorage("appearance") private var appearance = "dark"
    @State private var disconnect = false
    var body: some View {
        NavigationStack {
            Form {
                Section("Account") { CloudSignInView(account:remote.account) }
                Section {
                    HStack(spacing:16) { BotAvatar(size:42); VStack(alignment:.leading,spacing:4) { Text("OpenGrokBot").font(.headline);Text("Your desktop controller").font(.caption).foregroundStyle(.secondary) } }.padding(.vertical,8)
                    LabeledContent("Host",value:remote.hostName)
                    Text(remote.status).font(.footnote).foregroundStyle(.secondary)
                    Button("Connect / change desktop") { dismiss(); Task { try? await Task.sleep(for:.milliseconds(500)); remote.showConnection = true } }
                    if remote.hasSnapshot { Button("Disconnect this iPhone",role:.destructive) { disconnect = true } }
                } footer: { Text("Disconnecting this phone leaves desktop Bots, conversations and running work in place.") }
                Section("Appearance") { Picker("Theme",selection:$appearance) { Text("Follow system").tag("system");Text("Dark").tag("dark");Text("Light").tag("light") } }
                Section("Setup") {
                    NavigationLink("Desktop connection guide") { IntegrationView() }
                    Link("Project and downloads",destination:URL(string:"https://github.com/carboy285/opengrokbot")!)
                }
                Section { LabeledContent("App version",value:"0.6.0");Text("AI CLIs and optional Composio tools run on your Mac or Windows host using its accounts and permissions.").font(.footnote).foregroundStyle(.secondary) }
            }.navigationTitle("Settings").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement:.confirmationAction) { Button("Done") { dismiss() } } }
                .confirmationDialog("Disconnect this phone from the desktop?",isPresented:$disconnect,titleVisibility:.visible) { Button("Disconnect",role:.destructive) { remote.disconnect() } }
        }
    }
}
struct IntegrationView: View {
    var body: some View {
        Form {
            Section("1 · Desktop setup") { Text("Choose and sign into an AI CLI on your Mac. Optional Composio tools also run there.") }
            Section("2 · One account") { Text("In Mac Settings → Computer, create an email account, confirm the email, and sign in. Turn on Allow phone access. Sign into the same account on this iPhone.") }
            Section("3 · Approve this phone") { Text("Compare the phone’s fingerprint on both screens. Click Approve phone on your Mac, then choose your Mac in Connect Desktop on the phone.") }
            Section("Anywhere you go") { Text("The apps connect through Supabase over HTTPS, with encrypted commands and replies. Keep the Mac awake and the desktop app running. No VPN, pairing link, public IP, or router setup is needed.") }
        }.navigationTitle("Desktop setup").navigationBarTitleDisplayMode(.inline)
    }
}
