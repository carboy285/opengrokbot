import SwiftUI

struct MacConnectAppsView: View {
    @EnvironmentObject private var desktop: MacAppModel
    @State private var query = ""
    @State private var category: String?
    private static let onThisMac = "This Mac"

    private struct MacEntry: Identifiable {
        let id: String, title: String, subtitle: String, symbol: String, keywords: String
    }
    private static let macEntries: [MacEntry] = [
        MacEntry(id: "apple", title: "Apple Connections", subtitle: "Calendar, Reminders, Contacts, Mail, Notes and Messages on this Mac", symbol: "apple.logo",
                 keywords: "apple mac calendar reminders contacts mail notes messages email imessage"),
        MacEntry(id: "logins", title: "Secure Logins", subtitle: "Let a Bot sign in to a site without ever seeing your password", symbol: "key.fill",
                 keywords: "secure logins password manager sign in credentials")
    ]

    private func open(_ entry: MacEntry) {
        switch entry.id {
        case "apple": desktop.panel = .apple
        default: desktop.settingsTab = .secureLogins; desktop.panel = .settings
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("Connect Apps").font(.system(size: 25, weight: .medium))
                Spacer()
                ConnectedBadge(service: desktop.composio)
                Button { desktop.panel = nil } label: { Image(systemName: "xmark").frame(width: 38, height: 38) }.buttonStyle(.plain).accessibilityLabel("Close Connect Apps")
            }
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").foregroundStyle(MacTheme.secondary)
                TextField("Search across apps", text: $query).textFieldStyle(.plain).font(.system(size: 15)).accessibilityLabel("Search apps")
                if !query.isEmpty { Button { query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(MacTheme.secondary) }.buttonStyle(.plain).accessibilityLabel("Clear search") }
            }.padding(.horizontal, 14).padding(.vertical, 11).background(MacTheme.raised, in: RoundedRectangle(cornerRadius: 12))
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    chip("All", selected: category == nil) { category = nil }
                    chip(Self.onThisMac, selected: category == Self.onThisMac) { category = Self.onThisMac }
                    ForEach(ComposioCatalog.categories, id: \.self) { name in chip(name, selected: category == name) { category = name } }
                }
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    if showsMacSection { macSection }
                    if category != Self.onThisMac { MacComposioSetupView(service: desktop.composio, query: query, category: category, viewAll: { category = $0 }) }
                }.frame(maxWidth: 780, alignment: .leading).padding(.vertical, 8).frame(maxWidth: .infinity)
            }
        }.padding(36)
    }

    private var visibleMacEntries: [MacEntry] {
        let words = query.lowercased().split(whereSeparator: \.isWhitespace).map(String.init)
        return Self.macEntries.filter { entry in words.allSatisfy { (entry.title + " " + entry.keywords).lowercased().contains($0) } }
    }
    private var showsMacSection: Bool { (category == nil || category == Self.onThisMac) && !visibleMacEntries.isEmpty }

    private var macSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("On this Mac").font(.system(size: 14)).foregroundStyle(MacTheme.secondary)
            ForEach(visibleMacEntries) { entry in
                HStack(spacing: 14) {
                    Image(systemName: entry.symbol).font(.system(size: 18)).frame(width: 42, height: 42).background(MacTheme.panel, in: RoundedRectangle(cornerRadius: 11))
                    VStack(alignment: .leading, spacing: 3) {
                        Text(entry.title).font(.system(size: 16, weight: .medium))
                        Text(entry.subtitle).font(.system(size: 12)).foregroundStyle(MacTheme.secondary)
                    }
                    Spacer()
                    MacPillButton(title: "Open") { open(entry) }
                }.padding(14).background(MacTheme.raised, in: RoundedRectangle(cornerRadius: 14))
            }
        }
    }

    private func chip(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.system(size: 14, weight: .medium)).padding(.horizontal, 14).padding(.vertical, 8)
                .foregroundStyle(selected ? Color.black : Color.white)
                .background(selected ? Color.white : MacTheme.raised, in: Capsule())
        }.buttonStyle(.plain).accessibilityAddTraits(selected ? [.isSelected] : [])
    }
}

private struct ConnectedBadge: View {
    @ObservedObject var service: ComposioModel
    var body: some View {
        if service.connectedCount > 0 {
            HStack(spacing: 8) {
                HStack(spacing: -8) {
                    ForEach(Array(service.toolkits.filter { $0.connected || $0.is_no_auth }.prefix(4)), id: \.slug) { toolkit in
                        Image(systemName: ComposioCatalog.app(toolkit.slug)?.symbol ?? "app").font(.system(size: 11))
                            .frame(width: 26, height: 26).background(MacTheme.panel, in: Circle()).overlay(Circle().stroke(MacTheme.canvas, lineWidth: 2))
                    }
                }.accessibilityHidden(true)
                Text("\(service.connectedCount) connected").font(.system(size: 13)).foregroundStyle(MacTheme.secondary)
            }
        }
    }
}
