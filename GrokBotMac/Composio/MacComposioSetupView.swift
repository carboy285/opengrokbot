import SwiftUI

struct MacComposioSetupView: View {
    @ObservedObject var service: ComposioModel
    @State private var projectKey = ""
    @State private var search = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Connect your tools").font(.system(size: 29, weight: .medium))
            Text("Use your own Composio project to connect apps to Grok Bot. This step is optional; you can chat without connectors.")
                .font(.system(size: 16)).lineSpacing(5)
            if !service.configured {
                SecureField("Composio project API key", text: $projectKey).textFieldStyle(.roundedBorder).accessibilityIdentifier("composio-project-key")
                Link("Create a Composio project and get a key ↗", destination: URL(string: "https://platform.composio.dev")!)
                Text("Choose which tools to make available").font(.headline)
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 12) {
                    ForEach(ComposioModel.choices, id: \.slug) { choice in
                        Toggle(choice.name, isOn: Binding(get: { service.selected.contains(choice.slug) }, set: { enabled in
                            if enabled { service.selected.insert(choice.slug) } else { service.selected.remove(choice.slug) }
                        })).toggleStyle(.checkbox).disabled(service.busy)
                    }
                }
                MacPillButton(title: service.busy ? "Connecting…" : "Connect project", prominent: true) { service.connect(projectKey: projectKey); projectKey = "" }
                    .disabled(service.busy || projectKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || service.selected.isEmpty)
                Text("The key and tool session stay in this Mac’s Keychain. Composio and AI providers apply their own plans and usage limits.")
                    .font(.system(size: 12)).foregroundStyle(MacTheme.secondary)
            } else {
                HStack {
                    Label("\(service.connectedCount) connected", systemImage: "link").font(.headline)
                    Spacer()
                    Button(service.busy ? "Refreshing…" : "Refresh connections") { service.refresh() }.disabled(service.busy)
                }
                TextField("Search your selected tools", text: $search).textFieldStyle(.roundedBorder)
                ForEach(service.toolkits.filter { $0.enabled && (search.isEmpty || $0.name.localizedCaseInsensitiveContains(search)) }) { toolkit in
                    HStack {
                        Image(systemName: "app.connected.to.app.below.fill").frame(width: 32)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(toolkit.name).font(.system(size: 16, weight: .medium))
                            Text(toolkit.connected ? "Connected" : toolkit.is_no_auth ? "No sign-in required" : toolkit.connected_account?.status ?? "Not connected")
                                .font(.system(size: 12)).foregroundStyle(MacTheme.secondary)
                        }
                        Spacer()
                        if !toolkit.connected && !toolkit.is_no_auth {
                            MacPillButton(title: "Connect") { service.authorize(toolkit) }.disabled(service.busy)
                        } else { Image(systemName: "checkmark.circle.fill").foregroundStyle(.green) }
                    }.padding(15).background(MacTheme.raised, in: RoundedRectangle(cornerRadius: 14))
                }
                if service.toolkits.isEmpty && !service.busy { Text("Refresh to load the tools available to this project.").foregroundStyle(MacTheme.secondary) }
                Text("Connected tools are available to your selected CLI through MCP. Tool actions follow that CLI’s permission settings. To change the tool selection, remove this project and set it up again.")
                    .font(.system(size: 12)).lineSpacing(4).foregroundStyle(MacTheme.secondary)
                Button("Remove project from this Mac") { service.disconnect() }.disabled(service.busy)
                Link("Manage or revoke accounts in Composio ↗", destination: URL(string: "https://platform.composio.dev")!)
            }
            if let feedback = service.feedback { Text(feedback).font(.system(size: 14)).lineSpacing(4).foregroundStyle(MacTheme.secondary) }
        }.onAppear { if service.configured { service.refresh() } }
        .onDisappear { projectKey = "" }
    }
}
