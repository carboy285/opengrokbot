import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var remote: RemoteController
    @Environment(\.dismiss) private var dismiss
    @AppStorage("appearance") private var appearance = "dark"
    @State private var disconnect = false
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing:16) { BotAvatar(size:42); VStack(alignment:.leading,spacing:4) { Text("OpenGrokBot").font(.headline);Text("Your desktop controller").font(.caption).foregroundStyle(.secondary) } }.padding(.vertical,8)
                    LabeledContent("Host",value:remote.hostName)
                    Text(remote.status).font(.footnote).foregroundStyle(.secondary)
                    Button("Connect / change desktop") { dismiss(); remote.showPairing = true }
                    if remote.hasSnapshot { Button("Disconnect this iPhone",role:.destructive) { disconnect = true } }
                } footer: { Text("Disconnecting this phone leaves desktop Bots, conversations and running work in place.") }
                Section("Appearance") { Picker("Theme",selection:$appearance) { Text("Follow system").tag("system");Text("Dark").tag("dark");Text("Light").tag("light") } }
                Section("Setup") {
                    NavigationLink("Desktop connection guide") { IntegrationView() }
                    Link("Get Tailscale",destination:URL(string:"https://tailscale.com/download")!)
                    Link("Project and downloads",destination:URL(string:"https://github.com/carboy285/opengrokbot")!)
                }
                Section { LabeledContent("App version",value:"0.5.0");Text("AI CLIs and optional Composio tools run on your Mac or Windows host using its accounts and permissions.").font(.footnote).foregroundStyle(.secondary) }
            }.navigationTitle("Settings").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement:.confirmationAction) { Button("Done") { dismiss() } } }
                .confirmationDialog("Disconnect this phone from the desktop?",isPresented:$disconnect,titleVisibility:.visible) { Button("Disconnect",role:.destructive) { remote.disconnect() } }
        }
    }
}
struct IntegrationView: View {
    var body: some View {
        Form {
            Section("1 · Desktop setup") { Text("Choose an installed AI CLI and sign in on your Mac or Windows computer. Optionally connect your Composio project there.") }
            Section("2 · Remote access") { Text("In desktop Settings → Computer, enable iPhone remote control. Private Tailscale HTTPS works across Wi-Fi and cellular when both devices are connected to your tailnet. Funnel provides a public HTTPS address protected by the app’s pairing key. Wi-Fi/private IP works locally; a custom HTTPS reverse proxy is also supported.") }
            Section("3 · Pair your phone") { Text("Copy the desktop’s pairing link. Open it on this iPhone or paste it into Connect Desktop. Connect only to your own host and keep the link private.") }
            Section("Staying connected") { Text("Keep the desktop awake with OpenGrokBot running. The iPhone reconnects when you reopen it or your connection returns. Desktop work continues while the phone is offline. Direct Wi-Fi HTTP is unencrypted; use a trusted network or choose HTTPS.") }
        }.navigationTitle("Desktop setup").navigationBarTitleDisplayMode(.inline)
    }
}
