import AppKit
import SwiftUI

struct MacWorkspaceView: View {
    @EnvironmentObject private var app: AppModel
    @EnvironmentObject private var desktop: MacAppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var deleting: Bot?
    @FocusState private var searchFocused: Bool

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                HStack(spacing: 0) {
                    sidebar.frame(width: min(310, max(260, geometry.size.width * 0.255)))
                    Rectangle().fill(MacTheme.line).frame(width: 1)
                    if let bot = desktop.selected(in: app) {
                        MacConversationView(bot: bot).id(bot.id)
                    } else {
                        emptyWorkspace.frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .allowsHitTesting(desktop.panel == nil)
                .accessibilityHidden(desktop.panel != nil)
                if let panel = desktop.panel {
                    Color.black.opacity(0.64)
                        .ignoresSafeArea()
                        .onTapGesture { desktop.panel = nil }
                        .accessibilityHidden(true)
                    panelView(panel)
                        .frame(width: min(1180, geometry.size.width - 80), height: min(850, geometry.size.height - 80))
                        .background(MacTheme.panel, in: RoundedRectangle(cornerRadius: 22))
                        .overlay(RoundedRectangle(cornerRadius: 22).stroke(Color.white.opacity(0.13), lineWidth: 1))
                        .shadow(color: .black.opacity(0.4), radius: 40, y: 16)
                        .clipShape(RoundedRectangle(cornerRadius: 22))
                        .transition(reduceMotion ? .opacity : .scale(scale: 0.98).combined(with: .opacity))
                        .accessibilityAddTraits(.isModal)
                }
            }
            .animation(reduceMotion ? .easeOut(duration: 0.12) : .spring(response: 0.32, dampingFraction: 1), value: desktop.panel)
            .background(MacTheme.canvas)
            .onExitCommand { if desktop.panel != nil { desktop.panel = nil } else { desktop.showSearch = false } }
        }
        .foregroundStyle(.primary.opacity(0.9))
        .confirmationDialog("Delete \(deleting?.name ?? "this Bot") and its local notes?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            Button("Delete preview Bot", role: .destructive) {
                if let bot = deleting {
                    app.removeBot(bot)
                    if desktop.selectedID == bot.id { desktop.selectedID = app.workspace.bots.first?.id }
                }
                deleting = nil
            }
        }
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Spacer()
                MacCircleButton(symbol: "magnifyingglass", label: "Search Bots") {
                    desktop.showSearch.toggle()
                    searchFocused = desktop.showSearch
                }
                MacCircleButton(symbol: "plus", label: "New preview Bot") { desktop.panel = .newBot }
            }.padding(.horizontal, 18).padding(.top, 12)
            if desktop.showSearch {
                HStack {
                    Image(systemName: "magnifyingglass").foregroundStyle(MacTheme.secondary)
                    TextField("Search Bots", text: $app.search).textFieldStyle(.plain).focused($searchFocused)
                    if !app.search.isEmpty { Button { app.search = "" } label: { Image(systemName: "xmark.circle.fill") }.buttonStyle(.plain) }
                }.padding(10).background(MacTheme.panel, in: Capsule()).padding(.horizontal, 18).padding(.top, 14)
            }
            if let first = app.workspace.bots.first {
                Button { desktop.selectedID = first.id } label: {
                    VStack(spacing: 13) {
                        MacBotAvatar(size: 76, starred: true)
                        Text("Grok Bot").font(.system(size: 16))
                    }
                    .padding(.vertical, 16).frame(width: 126)
                    .background(desktop.selected(in: app)?.id == first.id ? MacTheme.panel : .clear, in: RoundedRectangle(cornerRadius: 18))
                }.buttonStyle(.plain).padding(.top, 30).padding(.bottom, 22)
            }
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(app.visibleBots.filter { $0.id != app.workspace.bots.first?.id || !app.search.isEmpty }) { bot in
                        Button { desktop.selectedID = bot.id } label: {
                            HStack(spacing: 16) {
                                MacBotAvatar(color: bot.color, size: 39)
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(bot.name).font(.system(size: 17, weight: .medium)).lineLimit(1)
                                    Text(app.latest(for: bot)).font(.system(size: 14)).foregroundStyle(MacTheme.secondary).lineLimit(1)
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 15).padding(.vertical, 14)
                            .background(desktop.selected(in: app)?.id == bot.id ? Color.white.opacity(0.045) : .clear, in: RoundedRectangle(cornerRadius: 14))
                            .contentShape(RoundedRectangle(cornerRadius: 14))
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button("Export Conversation…") { desktop.exportConversation(bot, app: app) }
                            Button("Delete Preview Bot…", role: .destructive) { deleting = bot }
                        }
                    }
                    if !app.search.isEmpty && app.visibleBots.isEmpty {
                        Text("No Bots match “\(app.search)”.").foregroundStyle(MacTheme.secondary).padding(20)
                    }
                }.padding(.horizontal, 8)
            }
            Spacer(minLength: 10)
            Button { desktop.panel = .integration } label: {
                HStack(spacing: 6) {
                    Circle().fill(Color.orange.opacity(0.8)).frame(width: 5, height: 5)
                    Text("Offline preview · Not connected").font(.system(size: 11))
                }.foregroundStyle(MacTheme.secondary)
            }.buttonStyle(.plain).padding(.bottom, 14)
            HStack(spacing: 10) {
                Button { desktop.openSettings() } label: {
                    Text("LP").font(.system(size: 15)).frame(width: 42, height: 42).glassChrome(in: Circle())
                }.buttonStyle(.plain).help("Settings")
                Button { desktop.panel = .apps } label: {
                    HStack(spacing: 9) {
                        Text("Connect apps").font(.system(size: 16, weight: .medium))
                        HStack(spacing: -4) {
                            appChip("N", color: .white)
                            appChip("#", color: Color(hex: 0x54B9AB))
                            appChip("G", color: Color(hex: 0xD8DD50))
                        }
                    }.frame(maxWidth: .infinity).frame(height: 42).glassChrome(in: Capsule())
                }.buttonStyle(.plain)
            }.padding(.horizontal, 14).padding(.bottom, 15)
        }.background(MacTheme.sidebar)
    }

    private func appChip(_ name: String, color: Color) -> some View {
        Text(name).font(.system(size: 11, weight: .heavy)).foregroundStyle(.black)
            .frame(width: 18, height: 18).background(color, in: RoundedRectangle(cornerRadius: 4))
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(MacTheme.panel, lineWidth: 1))
    }

    @ViewBuilder private func panelView(_ panel: MacPanel) -> some View {
        switch panel {
        case .settings: MacSettingsView()
        case .apps: MacConnectAppsView()
        case .newBot: MacNewBotView()
        case .integration: MacIntegrationView()
        }
    }

    private var emptyWorkspace: some View {
        VStack(spacing: 22) {
            MacBotAvatar(size: 92)
            Text("A place for your Bots").font(.system(size: 28, weight: .medium))
            Text("Create a preview Bot to explore this local workspace.").foregroundStyle(MacTheme.secondary)
            MacPillButton(title: "Create preview Bot", prominent: true) { desktop.panel = .newBot }
        }
    }
}
