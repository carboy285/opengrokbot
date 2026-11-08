import SwiftUI

/// The Composio app catalog: browse, search, add apps, and authorize them. Search and category come from Connect Apps.
struct MacComposioSetupView: View {
    @ObservedObject var service: ComposioModel
    var query = ""
    var category: String?
    /// Called when "View all" is pressed on a category section.
    var viewAll: ((String) -> Void)?
    @State private var projectKey = ""

    private var filtering: Bool { !query.trimmingCharacters(in: .whitespaces).isEmpty || category != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            if service.configured { configuredBar } else { setupCard }
            if filtering {
                let results = ComposioCatalog.filter(query: query, category: category)
                if results.isEmpty { Text("No apps match your search.").font(.system(size: 14)).foregroundStyle(MacTheme.secondary) }
                else { section("Results", results) }
            } else {
                section("Recommended for you", ComposioCatalog.recommended.compactMap(ComposioCatalog.app))
                ForEach(ComposioCatalog.categories, id: \.self) { name in section(name, ComposioCatalog.filter(query: "", category: name), limit: 4, viewAllCategory: name) }
            }
            if let feedback = service.feedback { Text(feedback).font(.system(size: 14)).lineSpacing(4).foregroundStyle(MacTheme.secondary) }
            if service.configured { footer }
        }
        .onAppear { if service.configured { service.refresh() } }
        .onDisappear { projectKey = "" }
    }

    // MARK: Setup and status
    private var setupCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Connect your Composio project").font(.system(size: 18, weight: .medium))
            Text("Use your own Composio project to connect apps to your Bots. This step is optional; you can chat without connectors. Add the apps you want below, then connect.")
                .font(.system(size: 14)).lineSpacing(4).foregroundStyle(MacTheme.secondary)
            SecureField("Composio project API key", text: $projectKey).textFieldStyle(.roundedBorder).accessibilityIdentifier("composio-project-key")
            HStack(spacing: 14) {
                MacPillButton(title: service.busy ? "Connecting…" : "Connect project", prominent: true) { service.connect(projectKey: projectKey); projectKey = "" }
                    .disabled(service.busy || projectKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || service.selected.isEmpty)
                Text(service.selected.isEmpty ? "Add at least one app" : "\(service.selected.count) app\(service.selected.count == 1 ? "" : "s") chosen").font(.system(size: 13)).foregroundStyle(MacTheme.secondary)
                Link("Get a key ↗", destination: URL(string: "https://platform.composio.dev")!).font(.system(size: 13))
            }
            Text("The key and tool session stay in this Mac’s Keychain. Composio and AI providers apply their own plans and usage limits.")
                .font(.system(size: 12)).foregroundStyle(MacTheme.secondary)
        }.padding(20).frame(maxWidth: .infinity, alignment: .leading).background(MacTheme.raised, in: RoundedRectangle(cornerRadius: 16))
    }

    private var configuredBar: some View {
        HStack(spacing: 10) {
            Text(service.toolkits.isEmpty && !service.busy ? "Refresh to load your apps" : "\(service.connectedCount) of \(service.applied.count) apps connected").font(.system(size: 14)).foregroundStyle(MacTheme.secondary)
            Spacer()
            if service.hasPendingChanges {
                let changes = service.selected.symmetricDifference(service.applied).count
                MacPillButton(title: "Apply \(changes) change\(changes == 1 ? "" : "s")", prominent: true) { service.applySelection() }.disabled(service.busy)
            }
            MacPillButton(title: service.busy ? "Working…" : "Refresh connections") { service.refresh() }.disabled(service.busy)
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Connected apps are available to your selected CLI through MCP, and actions follow that CLI’s permission settings. Add more apps above and choose Apply; accounts you already authorized stay connected.")
                .font(.system(size: 12)).lineSpacing(4).foregroundStyle(MacTheme.secondary)
            Button("Remove project from this Mac") { service.disconnect() }.disabled(service.busy)
            Link("Manage or revoke accounts in Composio ↗", destination: URL(string: "https://platform.composio.dev")!)
        }
    }

    // MARK: Catalog
    @ViewBuilder private func section(_ title: String, _ apps: [CatalogApp], limit: Int? = nil, viewAllCategory: String? = nil) -> some View {
        if !apps.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(title).font(.system(size: 14)).foregroundStyle(MacTheme.secondary)
                    Spacer()
                    if let limit, let viewAllCategory, apps.count > limit, let viewAll {
                        Button("View all (\(apps.count))") { viewAll(viewAllCategory) }.buttonStyle(.plain).font(.system(size: 13, weight: .medium)).foregroundStyle(MacTheme.secondary)
                            .accessibilityLabel("View all \(title) apps")
                    }
                }
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                    ForEach(limit.map { Array(apps.prefix($0)) } ?? apps) { app in card(app) }
                }
            }
        }
    }

    private func card(_ app: CatalogApp) -> some View {
        HStack(spacing: 12) {
            Image(systemName: app.symbol).font(.system(size: 16)).frame(width: 38, height: 38).background(MacTheme.panel, in: RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 2) {
                Text(app.name).font(.system(size: 15, weight: .medium)).lineLimit(1)
                Text(app.category).font(.system(size: 11)).foregroundStyle(MacTheme.secondary)
            }
            Spacer(minLength: 6)
            trailing(app)
        }.padding(12).background(MacTheme.raised, in: RoundedRectangle(cornerRadius: 14))
    }

    @ViewBuilder private func trailing(_ app: CatalogApp) -> some View {
        if service.configured && service.applied.contains(app.slug) {
            if let toolkit = service.toolkits.first(where: { $0.slug == app.slug && $0.enabled }) {
                if toolkit.connected || toolkit.is_no_auth { Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).accessibilityLabel("\(app.name) connected") }
                else { MacPillButton(title: "Connect") { service.authorize(toolkit) }.disabled(service.busy) }
            } else { Text(service.busy ? "Loading…" : "—").font(.system(size: 12)).foregroundStyle(MacTheme.secondary) }
        } else {
            let chosen = service.selected.contains(app.slug)
            MacPillButton(title: chosen ? "Added ✓" : "Add") {
                if chosen { service.selected.remove(app.slug) } else { service.selected.insert(app.slug) }
            }.disabled(service.busy).accessibilityLabel(chosen ? "Remove \(app.name)" : "Add \(app.name)")
        }
    }
}
