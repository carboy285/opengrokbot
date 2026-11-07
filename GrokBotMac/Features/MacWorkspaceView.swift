import AppKit
import SwiftUI

struct MacWorkspaceView: View {
    @EnvironmentObject private var app: AppModel
    @EnvironmentObject private var desktop: MacAppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var deleting: Bot?
    @State private var folderFilter: String? = nil
    private var sidebarBots: [Bot] { app.visibleBots.filter { folderFilter == nil || ($0.folder ?? "") == folderFilter } }
    private func pinned(_ bot: Bot) -> Bool { desktop.gateway?.isPinned(bot) ?? bot.isPinned ?? (bot.isMain == true) }
    private func touch(_ bot: Bot) { if let gateway = desktop.gateway { gateway.touch(bot.id) } else { _ = app.touchBot(bot.id) } }
    @FocusState private var searchFocused: Bool

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                HStack(spacing: 0) {
                    let hideRoster = desktop.showBotInspector && geometry.size.width < 1180
                    sidebar.frame(width: hideRoster ? 0 : min(370, max(280, geometry.size.width * 0.268)))
                        .clipped().allowsHitTesting(!hideRoster).accessibilityHidden(hideRoster)
                    Rectangle().fill(MacTheme.line).frame(width: hideRoster ? 0 : 1)
                    if let bot = desktop.selected(in: app) {
                        MacConversationView(bot: bot).id(bot.id)
                        if desktop.showBotInspector && desktop.gateway == nil {
                            Rectangle().fill(MacTheme.line).frame(width: 1)
                            MacBotInspectorView(bot: bot)
                                .id(bot.id)
                                .frame(width: min(440, max(340, geometry.size.width * 0.31)))
                                .transition(reduceMotion ? .opacity : .move(edge: .trailing).combined(with: .opacity))
                        }
                    } else {
                        emptyWorkspace.frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .disabled(desktop.panel != nil)
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
            .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 1), value: desktop.showBotInspector)
            .background(MacTheme.canvas)
            .onExitCommand { if desktop.panel != nil { desktop.panel = nil } else if desktop.showBotInspector { desktop.showBotInspector = false } else { desktop.showSearch = false } }
        }
        .alert("Copy Bot", isPresented: Binding(get: { desktop.copyNotice != nil }, set: { if !$0 { desktop.copyNotice = nil } })) {
            Button("OK") { desktop.copyNotice = nil }
        } message: { Text(desktop.copyNotice ?? "") }
        .sheet(isPresented: $desktop.showMirror) { MacMirrorView(source: desktop.remote.account).frame(minWidth: 950, minHeight: 650) }
        .onChange(of: desktop.showSearch) { _, visible in searchFocused = visible }
        .foregroundStyle(.primary.opacity(0.9))
        .confirmationDialog("Delete \(deleting?.name ?? "this Bot") and its local notes?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            Button("Delete Bot", role: .destructive) {
                if let bot = deleting, let gateway = desktop.gateway {
                    gateway.stop(bot.id); gateway.delete(bot.id)
                    if desktop.selectedID == bot.id { desktop.selectedID = nil }
                } else if let bot = deleting {
                    desktop.stop(botID: bot.id)
                    app.removeBot(bot)
                    if !app.workspace.bots.contains(where: { $0.id == bot.id }) { desktop.drafts[bot.id] = nil }
                    if desktop.selectedID == bot.id { desktop.selectedID = app.workspace.bots.first?.id }
                }
                deleting = nil
            }
        }
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                computerMenu
                Spacer()
                MacCircleButton(symbol: "magnifyingglass", label: "Search Bots") {
                    desktop.showSearch.toggle()
                    searchFocused = desktop.showSearch
                }
                MacCircleButton(symbol: "plus", label: "New Bot") { desktop.panel = .newBot }
            }.padding(.horizontal, 18).padding(.top, 12)
            if desktop.showSearch {
                HStack {
                    Image(systemName: "magnifyingglass").foregroundStyle(MacTheme.secondary)
                    TextField("Search Bots", text: $app.search).textFieldStyle(.plain).focused($searchFocused)
                    if !app.search.isEmpty { Button { app.search = "" } label: { Image(systemName: "xmark.circle.fill") }.buttonStyle(.plain) }
                }.padding(10).background(MacTheme.panel, in: Capsule()).padding(.horizontal, 18).padding(.top, 14)
            }
            Picker("Bot folder", selection: $folderFilter) {
                Text("All Bots").tag(Optional<String>.none)
                Text("Unfiled").tag(Optional(""))
                ForEach(Array(Set(app.workspace.bots.compactMap(\.folder).filter { !$0.isEmpty })).sorted(), id: \.self) { folder in Text(folder).tag(Optional(folder)) }
            }.labelsHidden().padding(.horizontal, 18).padding(.top, 16)
            ScrollView {
                LazyVStack(spacing: 8) {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 12)], spacing: 12) {
                        ForEach(sidebarBots.filter { pinned($0) }) { bot in
                            Button { desktop.selectedID = bot.id; touch(bot) } label: {
                                VStack(spacing: 12) {
                                    MacBotAvatar(color: bot.color, size: 64, starred: true, appearance: bot.appearance)
                                    Text(bot.name).font(.system(size: 14)).multilineTextAlignment(.center).lineLimit(2).help(bot.name)
                                }.padding(14).frame(maxWidth: .infinity).background(desktop.selected(in: app)?.id == bot.id ? MacTheme.panel : .clear, in: RoundedRectangle(cornerRadius: 18))
                            }.buttonStyle(.plain).contextMenu { organizationActions(bot) }.draggable(bot.id.uuidString)
                                .dropDestination(for: String.self) { values, _ in guard let value = values.first.flatMap(UUID.init(uuidString:)) else { return false }; return app.moveBot(value, before: bot.id) }
                        }
                    }.padding(.horizontal, 18).padding(.vertical, 20)
                    ForEach(app.recentlyUsed(sidebarBots.filter { !pinned($0) })) { bot in
                        Button { desktop.selectedID = bot.id; touch(bot) } label: {
                            HStack(spacing: 16) {
                                MacBotAvatar(color: bot.color, size: 39, appearance: bot.appearance)
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(bot.name).font(.system(size: 17, weight: .medium)).lineLimit(1).help(bot.name)
                                    Text(app.latest(for: bot)).font(.system(size: 14)).foregroundStyle(MacTheme.secondary).lineLimit(1)
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 15).padding(.vertical, 14)
                            .background(desktop.selected(in: app)?.id == bot.id ? Color.white.opacity(0.045) : .clear, in: RoundedRectangle(cornerRadius: 14))
                            .contentShape(RoundedRectangle(cornerRadius: 14))
                        }
                        .buttonStyle(.plain)
                        .draggable(bot.id.uuidString)
                        .dropDestination(for: String.self) { values, _ in guard let value = values.first.flatMap(UUID.init(uuidString:)) else { return false }; return app.moveBot(value, before: bot.id) }
                        .contextMenu {
                            organizationActions(bot)
                            Button("Export Conversation…") { desktop.exportConversation(bot, app: app) }
                            if bot.isMain != true { Button("Delete Bot…", role: .destructive) { deleting = bot } }
                        }
                    }
                    if !app.search.isEmpty && app.visibleBots.isEmpty {
                        Text("No Bots match “\(app.search)”.").foregroundStyle(MacTheme.secondary).padding(20)
                    }
                }.padding(.horizontal, 8)
            }
            Spacer(minLength: 10)
            Button { desktop.panel = .setup } label: {
                HStack(spacing: 6) {
                    Circle().fill(desktop.canChat ? Color.green : Color.orange.opacity(0.8)).frame(width: 5, height: 5)
                    Text(desktop.statusText).font(.system(size: 11))
                }.foregroundStyle(MacTheme.secondary)
            }.buttonStyle(.plain).padding(.bottom, 14)
            HStack(spacing: 10) {
                Button { desktop.openSettings() } label: {
                    Text(desktop.updates.available ? "↓" : "You").font(.system(size: 15)).frame(width: 42, height: 42).glassChrome(in: Circle())
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
                }.buttonStyle(.plain).accessibilityLabel("Connect apps")
            }.padding(.horizontal, 14).padding(.bottom, 15)
        }.background(MacTheme.sidebar)
    }

    /// Switch between this computer and any other computer on the account. The other computer appears in this same window.
    private var computerMenu: some View {
        Menu {
            Button { desktop.openComputer(nil, app: desktop.localApp ?? app) } label: { Label("This computer", systemImage: desktop.gateway == nil ? "checkmark" : "desktopcomputer") }
            Divider()
            if !desktop.remote.account.signedIn {
                Button("Sign in to view another computer…") { desktop.openSettings(.computer) }
            } else {
                let others = desktop.computers()
                if others.isEmpty { Text("No other computers found yet. Open OpenGrokBot on them and turn on phone access.") }
                ForEach(others) { host in
                    Button { desktop.openComputer(host, app: desktop.localApp ?? app) } label: {
                        Label(host.name + (host.online ? "" : " · offline"), systemImage: desktop.gateway?.hostName == host.name ? "checkmark" : "server.rack")
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: desktop.gateway == nil ? "desktopcomputer" : "server.rack")
                Text(desktop.gateway?.hostName ?? "This computer").lineLimit(1)
                Image(systemName: "chevron.down").font(.system(size: 9, weight: .semibold))
            }
        }
        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
        .help("Switch to another computer on your account. Its Bots appear here exactly like this Mac’s.")
    }

    @ViewBuilder
    private func organizationActions(_ bot: Bot) -> some View {
        Button(pinned(bot) ? "Unpin Bot" : "Pin to top") {
            if let gateway = desktop.gateway { gateway.setPinned(bot, !pinned(bot)) } else { desktop.remote.setPinned(bot, pinned: !pinned(bot)) }
        }
        if desktop.gateway == nil {
            Button("Bot details") { desktop.selectedID = bot.id; desktop.showBotInspector = true }
            Menu("Move to folder") {
                Button("Unfiled") { _ = app.organize(bot, folder: "") }
                ForEach(Array(Set(app.workspace.bots.compactMap(\.folder).filter { !$0.isEmpty })).sorted(), id: \.self) { folder in
                    Button(folder) { _ = app.organize(bot, folder: folder) }
                }
                Button("New folder…") { desktop.selectedID = bot.id; desktop.showBotInspector = true }
            }
        }
        if bot.memberIDs == nil {
            Menu("Copy to another computer") {
                if desktop.gateway != nil { Button("This computer") { desktop.copyBot(bot, shown: app, to: nil) } }
                let targets = desktop.copyTargets()
                ForEach(targets) { host in Button(host.name + (host.online ? "" : " · offline")) { desktop.copyBot(bot, shown: app, to: host) } }
                if targets.isEmpty && desktop.gateway == nil { Text("No other computers found yet.") }
            }
        }
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
        case .apple: MacAppleConnectionsView()
        case .newBot: MacNewBotView()
        case .integration: MacIntegrationView()
        case .setup: MacSetupView()
        }
    }

    private var emptyWorkspace: some View {
        VStack(spacing: 22) {
            MacBotAvatar(size: 92)
            Text("A place for your Bots").font(.system(size: 28, weight: .medium))
            Text("Create a Bot to start a separate AI conversation.").foregroundStyle(MacTheme.secondary)
            MacPillButton(title: "Create Bot", prominent: true) { desktop.panel = .newBot }
        }
    }
}
