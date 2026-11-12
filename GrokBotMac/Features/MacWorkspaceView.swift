import AppKit
import SwiftUI

struct MacWorkspaceView: View {
    @EnvironmentObject private var app: AppModel
    @EnvironmentObject private var desktop: MacAppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var deleting: Bot?
    @State private var renaming: Bot?
    @State private var renameDraft = ""
    @State private var folderFilter: String? = nil
    private var sidebarBots: [Bot] { app.visibleBots.filter { folderFilter == nil || ($0.folder ?? "") == folderFilter } }
    private func pinned(_ bot: Bot) -> Bool { desktop.gateway?.isPinned(bot) ?? bot.isPinned ?? (bot.isMain == true) }
    private func touch(_ bot: Bot) { if let gateway = desktop.gateway { gateway.touch(bot.id) } else { _ = app.touchBot(bot.id); _ = app.setUnread(false, for: bot.id) } }
    @FocusState private var searchFocused: Bool
    @ObservedObject private var approval = MacApproval.shared
    /// The avatar carries what a Bot is doing, as in Grok Bot's roster.
    private func status(_ bot: Bot) -> MacBotStatus {
        if approval.isWaiting(on: bot.name) { return .attention }
        return desktop.runningBots.contains(bot.id) ? .working : .idle
    }
    @AppStorage("profileName") private var profileName = "You"

    /// Every pinned Bot is a tile at the top, with the main Bot first.
    private var heroBots: [Bot] {
        let pins = sidebarBots.filter { pinned($0) }
        return pins.filter { $0.isMain == true } + pins.filter { $0.isMain != true }
    }
    /// Everything else, by recent use.
    private var listBots: [Bot] { app.recentlyUsed(sidebarBots.filter { !pinned($0) }) }

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
                MacVMHandoffOverlay(handoff: MacVMHandoff.shared).zIndex(60)
                // Voice mode floats above every chat so it keeps going while you open other Bots.
                MacVoiceOverlay(hub: MacVoiceHub.shared).zIndex(55)
                if desktop.showPalette {
                    MacCommandPalette().transition(.opacity).zIndex(5)
                }
                if let panel = desktop.panel {
                    Color.black.opacity(0.64)
                        .ignoresSafeArea()
                        .onTapGesture { desktop.panel = nil }
                        .accessibilityHidden(true)
                    panelView(panel)
                        .frame(width: min(panelSize(panel).width, geometry.size.width - 80), height: min(panelSize(panel).height, geometry.size.height - 80))
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
            .onChange(of: approval.pending?.id) { _, id in
                // An approval card lives in the chat: make sure nothing covers it.
                if id != nil { desktop.panel = nil; desktop.showPalette = false }
            }
            .onExitCommand { if desktop.showPalette { desktop.showPalette = false } else if desktop.panel != nil { desktop.panel = nil } else if desktop.showBotInspector { desktop.showBotInspector = false } else { desktop.showSearch = false } }
        }
        .alert("Rename Bot", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Name", text: $renameDraft)
            Button("Save") { if let bot = renaming, !app.renameBot(bot, to: renameDraft) { app.errorMessage = "Use a name no other Bot has." }; renaming = nil }
            Button("Cancel", role: .cancel) { renaming = nil }
        }
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
                Spacer()
                MacCircleButton(symbol: "magnifyingglass", label: "Search Bots") { desktop.showPalette = true }
                MacCircleButton(symbol: "plus", label: "New Bot") { desktop.panel = .newBot }
            }.padding(.horizontal, 18).padding(.top, 12)
            if let gateway = desktop.gateway {
                Button { desktop.openComputer(nil, app: desktop.localApp ?? app) } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "server.rack")
                        Text("Viewing \(gateway.hostName)").lineLimit(1)
                        Spacer(minLength: 4)
                        Text("Back to this Mac").font(.system(size: 12)).underline()
                    }.font(.system(size: 13)).padding(.horizontal, 14).padding(.vertical, 9).background(MacTheme.raised, in: Capsule())
                }.buttonStyle(.plain).padding(.horizontal, 18).padding(.top, 12).help("Stop viewing \(gateway.hostName) and return to this Mac’s own Bots")
            }
            ScrollView {
                LazyVStack(spacing: 8) {
                    if !heroBots.isEmpty {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 12)], spacing: 12) {
                            ForEach(heroBots) { bot in
                                Button { desktop.selectedID = bot.id; touch(bot) } label: {
                                    VStack(spacing: 10) {
                                        MacBotAvatar(color: bot.color, size: 58, starred: true, appearance: bot.appearance, status: status(bot))
                                        HStack(spacing: 5) {
                                            if bot.unread == true { Circle().fill(MacTheme.unread).frame(width: 7, height: 7).accessibilityLabel("Unread") }
                                            Text(bot.name).font(.system(size: 13, weight: bot.unread == true ? .semibold : .regular)).multilineTextAlignment(.center).lineLimit(2).help(bot.name)
                                        }
                                    }
                                    .padding(.vertical, 14).padding(.horizontal, 8).frame(maxWidth: .infinity)
                                    .background(desktop.selected(in: app)?.id == bot.id ? MacTheme.selection : .clear, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                                    .contentShape(RoundedRectangle(cornerRadius: 18))
                                }.buttonStyle(.plain).contextMenu { botMenu(bot) }.draggable(bot.id.uuidString)
                                    .dropDestination(for: String.self) { values, _ in guard let value = values.first.flatMap(UUID.init(uuidString:)) else { return false }; return app.moveBot(value, before: bot.id) }
                            }
                        }.padding(.horizontal, 10).padding(.top, 14).padding(.bottom, 10)
                    }
                    ForEach(listBots) { bot in
                        Button { desktop.selectedID = bot.id; touch(bot) } label: {
                            MacRosterRow(bot: bot, status: status(bot), latest: app.latest(for: bot),
                                         selected: desktop.selected(in: app)?.id == bot.id)
                        }
                        .buttonStyle(.plain)
                        .draggable(bot.id.uuidString)
                        .dropDestination(for: String.self) { values, _ in guard let value = values.first.flatMap(UUID.init(uuidString:)) else { return false }; return app.moveBot(value, before: bot.id) }
                        .contextMenu { botMenu(bot) }
                    }
                    if !app.search.isEmpty && app.visibleBots.isEmpty {
                        Text("No Bots match “\(app.search)”.").foregroundStyle(MacTheme.secondary).padding(20)
                    }
                }.padding(.horizontal, 8).padding(.bottom, 8)
            }
            .scrollIndicators(.hidden)
            Spacer(minLength: 6)
            if desktop.gateway == nil, !desktop.canChat {
                Button { desktop.panel = .setup } label: {
                    HStack(spacing: 6) {
                        Circle().fill(Color.orange.opacity(0.8)).frame(width: 5, height: 5)
                        Text(desktop.statusText).font(.system(size: 11))
                    }.foregroundStyle(MacTheme.secondary)
                }.buttonStyle(.plain).padding(.bottom, 10)
            }
            HStack(spacing: 10) {
                Button { desktop.openSettings() } label: {
                    Group {
                        if profileName.trimmingCharacters(in: .whitespaces).isEmpty || profileName == "You" { Image(systemName: "person.fill").font(.system(size: 14)) }
                        else { Text(String(profileName.prefix(2)).uppercased()).font(.system(size: 13, weight: .medium)) }
                    }.frame(width: 34, height: 34).glassChrome(in: Circle())
                }.buttonStyle(.plain).help("Settings").accessibilityLabel("Settings")
                Button { desktop.panel = desktop.gateway == nil ? .apps : .remoteSettings } label: {
                    Text("Connect apps").font(.system(size: 15, weight: .medium)).frame(maxWidth: .infinity).frame(height: 44).glassChrome(in: Capsule())
                }.buttonStyle(.plain).accessibilityLabel("Connect apps")
                if desktop.gateway == nil, desktop.updates.available || desktop.updates.stagedVersion != nil {
                    Button {
                        if desktop.updates.stagedVersion != nil { desktop.updates.restartAndInstall() } else { desktop.openSettings(.updates) }
                    } label: {
                        Image(systemName: "arrow.down").font(.system(size: 14, weight: .semibold)).foregroundStyle(.white)
                            .frame(width: 34, height: 34).background(Color(hex: 0x2F7BFF), in: Circle())
                    }.buttonStyle(.plain).help(desktop.updates.stagedVersion != nil ? "Update ready: restart to install" : "An update is available").accessibilityLabel(desktop.updates.stagedVersion != nil ? "Restart to update" : "Update available")
                }
            }.padding(.horizontal, 14).padding(.bottom, 15)
        }.background(MacTheme.sidebar)
    }

    /// The same right-click menu for the hero card and every list row.
    @ViewBuilder
    private func botMenu(_ bot: Bot) -> some View {
        Button(pinned(bot) ? "Unpin" : "Pin to top") {
            if let gateway = desktop.gateway { gateway.setPinned(bot, !pinned(bot)) } else { desktop.remote.setPinned(bot, pinned: !pinned(bot)) }
        }
        if desktop.gateway == nil {
            Menu("Move to section") {
                Button("No section") { _ = app.organize(bot, folder: "") }
                ForEach(Array(Set(app.workspace.bots.compactMap(\.folder).filter { !$0.isEmpty })).sorted(), id: \.self) { folder in
                    Button(folder) { _ = app.organize(bot, folder: folder) }
                }
                Button("New section…") { desktop.selectedID = bot.id; desktop.showBotInspector = true }
            }
            Button(bot.unread == true ? "Mark as read" : "Mark as unread") { _ = app.setUnread(bot.unread != true, for: bot.id) }
            Button("Rename Bot…") { renameDraft = bot.name; renaming = bot }
            Button("Bot details") { desktop.selectedID = bot.id; desktop.showBotInspector = true }
        }
        Button("Copy conversation ID") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(bot.id.uuidString, forType: .string) }
        if desktop.gateway == nil, bot.isMain != true { Button("Hide from sidebar") { _ = app.setHidden(true, for: bot) } }
        if bot.memberIDs == nil {
            Button("Copy to another computer…") { desktop.copyingBot = bot.id; desktop.copyNotice = nil; desktop.panel = .computers }
        }
        Divider()
        Button("Export Conversation…") { desktop.exportConversation(bot, app: app) }
        if bot.isMain != true { Button("Delete Bot…", role: .destructive) { deleting = bot } }
    }

    private func appChip(_ name: String, color: Color) -> some View {
        Text(name).font(.system(size: 11, weight: .heavy)).foregroundStyle(.black)
            .frame(width: 18, height: 18).background(color, in: RoundedRectangle(cornerRadius: 4))
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(MacTheme.panel, lineWidth: 1))
    }

    /// Small dialogs stay small; the big screens (settings, apps, computers) keep the wide panel.
    private func panelSize(_ panel: MacPanel) -> CGSize {
        switch panel {
        case .newBot: CGSize(width: 520, height: 700)
        case .newGroup: CGSize(width: 520, height: 640)
        case .shortcuts: CGSize(width: 520, height: 640)
        default: CGSize(width: 1180, height: 850)
        }
    }

    @ViewBuilder private func panelView(_ panel: MacPanel) -> some View {
        switch panel {
        case .settings: MacSettingsView()
        case .apps: MacConnectAppsView()
        case .apple: MacAppleConnectionsView()
        case .computers: MacComputersView()
        case .remoteSettings: MacRemoteSettingsView()
        case .newGroup: MacNewGroupView()
        case .shortcuts: MacShortcutsView()
        case .permissions: MacPermissionsView()
        case .newBot: MacNewBotView()
        case .integration: MacIntegrationView()
        case .setup: MacSetupView()
        }
    }

    private var emptyWorkspace: some View {
        if let gateway = desktop.gateway, !gateway.hasSnapshot {
            return AnyView(VStack(spacing: 16) {
                ProgressView()
                Text("Connecting to \(gateway.hostName)…").font(.system(size: 22, weight: .medium))
                Text("Its Bots will appear here as soon as it answers. Make sure it is awake with OpenGrokBot open and phone access on.").foregroundStyle(MacTheme.secondary).multilineTextAlignment(.center).frame(maxWidth: 360)
            })
        }
        return AnyView(VStack(spacing: 22) {
            MacBotAvatar(size: 92)
            Text("A place for your Bots").font(.system(size: 28, weight: .medium))
            Text("Create a Bot to start a separate AI conversation.").foregroundStyle(MacTheme.secondary)
            MacPillButton(title: "Create Bot", prominent: true) { desktop.panel = .newBot }
        })
    }
}

/// One Bot in the sidebar roster: face, name, and one line that says what it is doing or what it last said.
struct MacRosterRow: View {
    let bot: Bot
    let status: MacBotStatus
    let latest: String
    let selected: Bool
    @State private var hovering = false

    private var subtitle: String {
        switch status {
        case .attention: return "Needs your OK"
        case .working: return "Thinking it through…"
        case .idle:
            // One clean line: no question-card block, no blank lines.
            let clean = ChoicePrompt.split(latest).text
            return clean.split(separator: "\n").first.map { String($0) } ?? clean
        }
    }
    private var subtitleColor: Color {
        switch status {
        case .attention: return MacTheme.attention
        case .working: return MacTheme.working
        case .idle: return MacTheme.secondary
        }
    }

    var body: some View {
        HStack(spacing: 13) {
            MacBotAvatar(color: bot.color, size: 36, appearance: bot.appearance, status: status)
            VStack(alignment: .leading, spacing: 3) {
                Text(bot.name).font(.system(size: 14.5, weight: bot.unread == true ? .semibold : .medium)).lineLimit(1).help(bot.name)
                Text(subtitle).font(.system(size: 12.5)).foregroundStyle(subtitleColor).lineLimit(1)
            }
            Spacer(minLength: 4)
            if bot.unread == true {
                Circle().fill(MacTheme.unread).frame(width: 8, height: 8).accessibilityLabel("Unread")
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 9)
        .background(selected ? MacTheme.selection : (hovering ? MacTheme.hover : .clear), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 14))
        .onHover { hovering = $0 }
        .accessibilityElement(children: .combine)
    }
}
