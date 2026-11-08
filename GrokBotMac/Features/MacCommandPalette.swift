import AppKit
import SwiftUI

/// A centred search-and-command window: type to find a Bot or an action, Up/Down to move, Return to run, Escape to close.
struct MacCommandPalette: View {
    @EnvironmentObject private var app: AppModel
    @EnvironmentObject private var desktop: MacAppModel
    @State private var query = ""
    @State private var index = 0
    @FocusState private var focused: Bool

    private struct Item: Identifiable {
        let id: String
        let title: String
        let subtitle: String
        let symbol: String
        let bot: Bot?
        let run: () -> Void
    }

    private func close() { desktop.showPalette = false }

    private var items: [Item] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        var result: [Item] = []
        let bots = app.workspace.bots.filter { bot in
            needle.isEmpty || bot.name.localizedCaseInsensitiveContains(needle) || bot.purpose.localizedCaseInsensitiveContains(needle) || app.latest(for: bot).localizedCaseInsensitiveContains(needle)
        }
        for bot in app.recentlyUsed(bots).prefix(8) {
            result.append(Item(id: "bot-" + bot.id.uuidString, title: bot.name, subtitle: (bot.hidden == true ? "Hidden · " : "") + app.latest(for: bot), symbol: "bubble.left", bot: bot) {
                if bot.hidden == true, desktop.gateway == nil { _ = app.setHidden(false, for: bot) }
                desktop.selectedID = bot.id
                if let gateway = desktop.gateway { gateway.touch(bot.id) } else { _ = app.touchBot(bot.id); _ = app.setUnread(false, for: bot.id) }
                close()
            })
        }
        var actions: [(String, String, String, () -> Void)] = [
            ("New Bot", "Create a Bot", "plus", { desktop.panel = .newBot }),
            ("Computers…", "Look at another computer, or copy Bots between them", "desktopcomputer", { desktop.copyingBot = nil; desktop.copyNotice = nil; desktop.panel = .computers }),
            ("Settings…", "Preferences", "gearshape", { desktop.openSettings() }),
            ("Keyboard shortcuts", "See every shortcut", "keyboard", { desktop.panel = .shortcuts })
        ]
        if desktop.gateway == nil { actions.insert(("New group chat", "Chat with several Bots at once", "person.3", { desktop.panel = .newGroup }), at: 1) }
        for action in actions where needle.isEmpty || action.0.localizedCaseInsensitiveContains(needle) || action.1.localizedCaseInsensitiveContains(needle) {
            result.append(Item(id: "action-" + action.0, title: action.0, subtitle: action.1, symbol: action.2, bot: nil) { close(); action.3() })
        }
        return result
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.45).ignoresSafeArea().onTapGesture { close() }
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass").foregroundStyle(MacTheme.secondary)
                    TextField("Search Bots and actions", text: $query).textFieldStyle(.plain).font(.system(size: 17)).focused($focused)
                        .onSubmit { run(index) }
                        .onKeyPress(.downArrow) { index = min(index + 1, max(items.count - 1, 0)); return .handled }
                        .onKeyPress(.upArrow) { index = max(index - 1, 0); return .handled }
                        .onKeyPress(.escape) { close(); return .handled }
                        .accessibilityLabel("Search Bots and actions")
                }.padding(.horizontal, 18).padding(.vertical, 15)
                Divider()
                ScrollView {
                    LazyVStack(spacing: 2) {
                        let list = items
                        if list.isEmpty { Text("Nothing matches “\(query)”.").foregroundStyle(MacTheme.secondary).padding(24) }
                        ForEach(Array(list.enumerated()), id: \.element.id) { position, item in
                            Button { run(position) } label: {
                                HStack(spacing: 12) {
                                    if let bot = item.bot { MacBotAvatar(color: bot.color, size: 30, appearance: bot.appearance) }
                                    else { Image(systemName: item.symbol).font(.system(size: 14)).frame(width: 30, height: 30).background(MacTheme.panel, in: Circle()) }
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(item.title).font(.system(size: 15, weight: .medium)).lineLimit(1)
                                        Text(item.subtitle).font(.system(size: 12)).foregroundStyle(MacTheme.secondary).lineLimit(1)
                                    }
                                    Spacer(minLength: 0)
                                }.padding(.horizontal, 12).padding(.vertical, 8).frame(maxWidth: .infinity, alignment: .leading)
                                    .background(position == index ? Color.white.opacity(0.08) : .clear, in: RoundedRectangle(cornerRadius: 10)).contentShape(Rectangle())
                            }.buttonStyle(.plain)
                        }
                    }.padding(8)
                }.frame(maxHeight: 380)
            }
            .frame(width: 560).background(MacTheme.raised, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.1)))
            .shadow(color: .black.opacity(0.4), radius: 30, y: 12)
            .padding(.bottom, 120)
        }
        .onAppear { focused = true }
        .onChange(of: query) { _, _ in index = 0 }
        .accessibilityAddTraits(.isModal)
    }

    private func run(_ position: Int) {
        let list = items
        guard position >= 0, position < list.count else { return }
        list[position].run()
    }
}

/// Create a chat that several Bots join. Each member answers with its own provider and model.
struct MacNewGroupView: View {
    @EnvironmentObject private var app: AppModel
    @EnvironmentObject private var desktop: MacAppModel
    @State private var name = ""
    @State private var members: Set<UUID> = []
    @State private var problem: String?

    private var candidates: [Bot] { app.workspace.bots.filter { $0.memberIDs == nil } }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("New group chat").font(.system(size: 24, weight: .medium))
                Spacer()
                Button { desktop.panel = nil } label: { Image(systemName: "xmark").frame(width: 34, height: 34) }.buttonStyle(.plain).accessibilityLabel("Close")
            }
            TextField("Group name", text: $name).textFieldStyle(.plain).font(.system(size: 18)).padding(14).background(MacTheme.raised, in: RoundedRectangle(cornerRadius: 12))
            Text("Choose 2 to 8 Bots").font(.system(size: 13)).foregroundStyle(MacTheme.secondary)
            ScrollView {
                VStack(spacing: 6) {
                    ForEach(candidates) { bot in
                        Button { if members.contains(bot.id) { members.remove(bot.id) } else if members.count < 8 { members.insert(bot.id) } } label: {
                            HStack(spacing: 12) {
                                MacBotAvatar(color: bot.color, size: 30, appearance: bot.appearance)
                                Text(bot.name).font(.system(size: 15))
                                Spacer()
                                Image(systemName: members.contains(bot.id) ? "checkmark.circle.fill" : "circle").foregroundStyle(members.contains(bot.id) ? Color.accentColor : MacTheme.secondary)
                            }.padding(10).background(MacTheme.raised, in: RoundedRectangle(cornerRadius: 10)).contentShape(Rectangle())
                        }.buttonStyle(.plain)
                    }
                }
            }
            if let problem { Text(problem).font(.system(size: 12)).foregroundStyle(.orange) }
            HStack {
                Spacer()
                MacPillButton(title: "Create group", prominent: true) {
                    if app.addGroup(name: name, members: Array(members)) { desktop.selectedID = app.workspace.bots.last?.id; desktop.panel = nil }
                    else { problem = "Use a name no other Bot has, and pick 2 to 8 Bots." }
                }.disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || members.count < 2)
            }
        }.padding(30)
    }
}

/// Every keyboard shortcut in one place.
struct MacShortcutsView: View {
    @EnvironmentObject private var desktop: MacAppModel
    private let rows: [(String, String)] = [
        ("⌘K", "Search Bots and actions"), ("⌘F", "Search Bots and actions"), ("⌘N", "New Bot"), ("⌘,", "Settings"),
        ("⌥⌘K", "Computers"), ("⇧⌘]", "Next Bot"), ("⇧⌘[", "Previous Bot"), ("⇧⌘E", "Export this conversation"),
        ("⏎", "Send a message"), ("⇧⏎", "New line in a message"), ("⌘V", "Paste an image or file into a message"), ("Esc", "Close the window on top")
    ]
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Keyboard shortcuts").font(.system(size: 24, weight: .medium))
                Spacer()
                Button { desktop.panel = nil } label: { Image(systemName: "xmark").frame(width: 34, height: 34) }.buttonStyle(.plain).accessibilityLabel("Close")
            }
            VStack(spacing: 0) {
                ForEach(rows, id: \.0) { row in
                    HStack { Text(row.1); Spacer(); Text(row.0).font(.system(size: 13, design: .monospaced)).foregroundStyle(MacTheme.secondary) }.padding(.vertical, 11).padding(.horizontal, 16)
                    Divider()
                }
            }.background(MacTheme.raised, in: RoundedRectangle(cornerRadius: 14))
            Spacer()
        }.padding(30)
    }
}
