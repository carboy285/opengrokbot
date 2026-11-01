import SwiftUI

struct CatalogApp: Identifiable, Sendable {
    let name: String
    let category: String
    let glyph: String
    let color: UInt32
    var id: String { name }
    static let all: [CatalogApp] = [
        .init(name: "Datadog", category: "Code", glyph: "dog", color: 0x7B4BB9),
        .init(name: "Vercel", category: "Code", glyph: "triangle.fill", color: 0xFFFFFF),
        .init(name: "Supabase", category: "Code", glyph: "bolt.fill", color: 0x3ECF8E),
        .init(name: "Cloudflare", category: "Code", glyph: "cloud.fill", color: 0xF6821F),
        .init(name: "Sentry", category: "Code", glyph: "waveform.path", color: 0xCFC4DF),
        .init(name: "Firebase", category: "Code", glyph: "flame.fill", color: 0xFFB300),
        .init(name: "1Password", category: "Password Managers", glyph: "key.fill", color: 0xD6D9E5),
        .init(name: "Notion", category: "Productivity", glyph: "n.square.fill", color: 0xFFFFFF),
        .init(name: "Atlassian", category: "Productivity", glyph: "a.circle.fill", color: 0x2684FF),
        .init(name: "Google Drive", category: "Productivity", glyph: "externaldrive.fill", color: 0x39A96B),
        .init(name: "Slack", category: "Communication", glyph: "number", color: 0x59B9A9),
        .init(name: "Gmail", category: "Communication", glyph: "envelope.fill", color: 0xE05A50),
        .init(name: "Figma", category: "Design", glyph: "circle.hexagongrid.fill", color: 0xA66BFE),
        .init(name: "GitHub", category: "Code", glyph: "chevron.left.forwardslash.chevron.right", color: 0xE7E7E7)
    ]
}

struct MacConnectAppsView: View {
    @EnvironmentObject private var desktop: MacAppModel
    @State private var search = ""
    @State private var category = "All"
    private let categories = ["All", "Password Managers", "Productivity", "Communication", "Design", "Code"]
    private var filtered: [CatalogApp] {
        CatalogApp.all.filter { (category == "All" || $0.category == category) && (search.isEmpty || $0.name.localizedCaseInsensitiveContains(search)) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Connect Apps").font(.system(size: 25, weight: .medium))
                Spacer()
                Text("No account connected").font(.system(size: 14)).foregroundStyle(MacTheme.secondary)
                Button { desktop.panel = nil } label: { Image(systemName: "xmark").font(.system(size: 20)).frame(width: 38, height: 38) }.buttonStyle(.plain).padding(.leading, 12)
            }.padding(.bottom, 28)
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").foregroundStyle(MacTheme.secondary)
                TextField("Search across apps and skills", text: $search).textFieldStyle(.plain).font(.system(size: 18))
            }.padding(.horizontal, 17).padding(.vertical, 12)
                .overlay(Capsule().stroke(MacTheme.line)).padding(.bottom, 17)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(categories, id: \.self) { item in
                        Button { category = item } label: {
                            Text(item).font(.system(size: 15)).padding(.horizontal, 17).padding(.vertical, 10)
                                .foregroundStyle(category == item ? MacTheme.onProminent : Color.primary.opacity(0.9))
                                .background(category == item ? MacTheme.prominent : MacTheme.raised, in: Capsule())
                        }.buttonStyle(.plain).accessibilityAddTraits(category == item ? [.isSelected] : [])
                    }
                }
            }.padding(.bottom, 22)
            ScrollView {
                VStack(alignment: .leading, spacing: 30) {
                    if category == "All" && search.isEmpty {
                        catalogSection("Recommended for you", apps: Array(CatalogApp.all.prefix(6)))
                        catalogSection("Password Managers", apps: CatalogApp.all.filter { $0.category == "Password Managers" })
                        catalogSection("Productivity", apps: CatalogApp.all.filter { $0.category == "Productivity" })
                        catalogSection("Communication", apps: CatalogApp.all.filter { $0.category == "Communication" })
                        catalogSection("Design", apps: CatalogApp.all.filter { $0.category == "Design" })
                    } else if filtered.isEmpty {
                        ContentUnavailableView.search(text: search).frame(maxWidth: .infinity).padding(.top, 50)
                    } else {
                        catalogSection(category == "All" ? "Search results" : category, apps: filtered)
                    }
                }.padding(.top, 8).padding(.bottom, 24)
            }
            Text("Catalog preview · Connecting an app requires a verified Grok Bot session.")
                .font(.system(size: 11)).foregroundStyle(MacTheme.secondary).padding(.top, 12)
        }.padding(.horizontal, 38).padding(.top, 26).padding(.bottom, 18)
    }

    private func catalogSection(_ title: String, apps: [CatalogApp]) -> some View {
        VStack(alignment: .leading, spacing: 24) {
            Text(title).font(.system(size: 19, weight: .medium))
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 36), GridItem(.flexible())], spacing: 28) {
                ForEach(apps) { app in
                    HStack(spacing: 14) {
                        Image(systemName: app.glyph).font(.system(size: 26, weight: .semibold)).foregroundStyle(Color(hex: app.color))
                            .frame(width: 52, height: 52).background(Color.black.opacity(0.18), in: RoundedRectangle(cornerRadius: 14))
                            .overlay(RoundedRectangle(cornerRadius: 14).stroke(MacTheme.line))
                        Text(app.name).font(.system(size: 17)).lineLimit(1)
                        Spacer(minLength: 4)
                        Button {
                            desktop.importFeedback = "\(app.name) cannot be connected in offline preview. No authorization was requested and no account was changed."
                            desktop.panel = .integration
                        } label: {
                            Text("Connect").font(.system(size: 15)).frame(width: 114, height: 34).background(MacTheme.raised, in: Capsule())
                        }.buttonStyle(.plain).help("View connection requirements for \(app.name)")
                    }
                }
            }
        }
    }
}
