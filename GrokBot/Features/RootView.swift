import SwiftUI

private enum RosterFilter: String, CaseIterable, Identifiable {
    case all = "All Bots", working = "Working", groups = "Groups"
    var id: String { rawValue }
}

struct RootView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var remote: RemoteController
    @State private var settings = false
    @State private var createBot = false
    @State private var filter = RosterFilter.all
    @State private var deleting: Bot?
    @FocusState private var searching: Bool
    @ScaledMetric(relativeTo: .largeTitle) private var heroSize: CGFloat = 104
    @State private var inspectedBot: Bot?

    private var matchingBots: [Bot] {
        model.visibleBots.filter { bot in
            (filter != .working || remote.running.contains(bot.id)) &&
            (filter != .groups || bot.memberIDs != nil)
        }
    }
    private var pinnedBots: [Bot] {
        let ids = remote.pinnedBotIDs ?? model.workspace.bots.filter { $0.isMain == true }.map(\.id)
        return matchingBots.filter { remote.isPinned($0) }.sorted {
            (ids.firstIndex(of: $0.id) ?? 0) < (ids.firstIndex(of: $1.id) ?? 0)
        }
    }
    private var bots: [Bot] { matchingBots.filter { !remote.isPinned($0) } }
    private var initials: String {
        guard remote.account.signedIn else { return "" }
        let name = remote.account.email.split(separator: "@").first.map(String.init) ?? ""
        let letters = name.split(whereSeparator: { !$0.isLetter }).prefix(2).compactMap(\.first)
        return letters.isEmpty ? "" : String(letters).uppercased()
    }

    var body: some View {
        NavigationStack {
            Group {
                if remote.hasSnapshot { roster }
                else { connectionWelcome }
            }
            .background(Palette.background)
            .safeAreaInset(edge: .top, spacing: 0) { header }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if remote.hasSnapshot { searchBar }
            }
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $settings) { SettingsView() }
            .sheet(isPresented: $createBot) { CreateBotView() }
            .sheet(item: $inspectedBot) { bot in
                NavigationStack {
                    RemoteBotDetailView(botID: bot.id)
                        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { inspectedBot = nil } } }
                }.presentationDetents([.large]).presentationDragIndicator(.visible)
            }
            .navigationDestination(for: Bot.self) { bot in ConversationView(bot: bot) }
            .confirmationDialog("Delete \(deleting?.name ?? "this Bot") and its conversations?", isPresented: Binding(
                get: { deleting != nil }, set: { if !$0 { deleting = nil } }
            ), titleVisibility: .visible) {
                Button("Delete Bot", role: .destructive) {
                    if let bot = deleting { Task { await remote.command(RemoteCommand(action: "delete_bot", botID: bot.id)) } }
                    deleting = nil
                }
            }
        }
    }

    private var header: some View {
        VStack(spacing: 15) {
            HStack {
                Button { settings = true } label: {
                    Group {
                        if initials.isEmpty { Image(systemName: "person.crop.circle").font(.system(size: 25)) }
                        else { Text(initials).font(.system(size: 16, weight: .medium)).foregroundStyle(.secondary) }
                    }.frame(width: 48, height: 48).background(.primary.opacity(0.04), in: Circle())
                        .padding(4).glassChrome(in: Circle())
                }.buttonStyle(.plain).accessibilityLabel("Account and settings")
                Spacer()
                if remote.hasSnapshot {
                    RoundButton(symbol: "plus", label: "Create a Bot") { createBot = true }.disabled(!remote.online)
                }
            }.padding(.horizontal, 20).padding(.top, 8)
            if remote.hasSnapshot { RemoteConnectionBanner() }
        }.padding(.bottom, 8).background(Palette.background)
    }

    private var roster: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if !pinnedBots.isEmpty {
                    if pinnedBots.count == 1, let bot = pinnedBots.first {
                        HStack {
                            Spacer(minLength: 0)
                            pinnedTile(bot, large: true)
                            Spacer(minLength: 0)
                        }.padding(.top, 32).padding(.bottom, 28)
                    } else {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 18)], spacing: 28) {
                            ForEach(pinnedBots) { bot in pinnedTile(bot, large: false) }
                        }.padding(.horizontal, 24).padding(.top, 28).padding(.bottom, 26)
                    }
                }
                ForEach(bots) { bot in
                    NavigationLink(value: bot) { botRow(bot) }.buttonStyle(.plain)
                        .contextMenu { botActions(bot) }
                }
                if matchingBots.isEmpty {
                    ContentUnavailableView(filter == .working ? "No Bots working" : filter == .groups ? "No groups yet" : "No matches",
                        systemImage: filter == .working ? "sparkles" : "magnifyingglass",
                        description: Text(filter == .all ? "Try another name or topic." : filter == .working ? "Your running Bots will appear here." : "Groups created on your Mac appear here."))
                        .padding(.top, 56)
                }
            }.padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
    }

    private func pinnedTile(_ bot: Bot, large: Bool) -> some View {
        NavigationLink(value: bot) {
            VStack(spacing: large ? 17 : 12) {
                ZStack(alignment: .bottomTrailing) {
                    BotAvatar(color: bot.color, size: large ? min(heroSize, 140) : 64, appearance: bot.appearance)
                    Image(systemName: "star.fill").font(.system(size: large ? 11 : 8, weight: .bold))
                        .foregroundStyle(.white).frame(width: large ? 25 : 20, height: large ? 25 : 20)
                        .background(.orange, in: Circle())
                        .overlay(Circle().stroke(Palette.background, lineWidth: 3)).offset(x: 2, y: 2)
                }
                Text(bot.name).font(large ? .title3 : .subheadline).foregroundStyle(.primary)
                    .multilineTextAlignment(.center).lineLimit(2)
            }.frame(width: large ? min(max(heroSize + 24, 140), 180) : 100)
                .contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityLabel("\(bot.name), pinned. Open chat")
            .contextMenu { botActions(bot) }
    }

    @ViewBuilder
    private func botActions(_ bot: Bot) -> some View {
        Button(remote.isPinned(bot) ? "Unpin Bot" : "Pin to top", systemImage: remote.isPinned(bot) ? "pin.slash" : "pin") {
            remote.setPinned(!remote.isPinned(bot), bot: bot)
        }
        Button("Bot details", systemImage: "info.circle") { inspectedBot = bot }
        if bot.isMain != true {
            Button("Delete Bot", systemImage: "trash", role: .destructive) { deleting = bot }.disabled(!remote.online)
        }
    }

    private func botRow(_ bot: Bot) -> some View {
        let latest = model.entries(for: bot).last
        return HStack(spacing: 18) {
            BotAvatar(color: bot.color, size: 46, appearance: bot.appearance)
            VStack(alignment: .leading, spacing: 7) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(bot.name).font(.system(.body, design: .default).weight(.semibold)).foregroundStyle(.primary).lineLimit(1)
                    Spacer(minLength: 0)
                    if let date = latest?.date {
                        Text(date, format: .relative(presentation: .named)).font(.caption).foregroundStyle(.tertiary).lineLimit(1)
                    }
                }
                HStack(spacing: 5) {
                    if remote.running.contains(bot.id) {
                        Image(systemName: "sparkles").font(.caption).foregroundStyle(.secondary)
                    } else if latest?.senderBotID != nil {
                        Image(systemName: "paperplane").font(.caption).foregroundStyle(.secondary)
                    }
                    Text(remote.running.contains(bot.id) ? "Working…" : model.latest(for: bot))
                        .font(.body).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Image(systemName: "chevron.right").font(.system(size: 14, weight: .medium)).foregroundStyle(.quaternary)
        }
        .padding(.horizontal, 24).padding(.vertical, 19).contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private var searchBar: some View {
        HStack(spacing: 12) {
            Menu {
                Picker("Show Bots", selection: $filter) {
                    ForEach(RosterFilter.allCases) { item in Text(item.rawValue).tag(item) }
                }
            } label: {
                Image(systemName: filter == .all ? "square.grid.2x2" : filter == .working ? "sparkles" : "person.3")
                    .font(.system(size: 21)).frame(width: 52, height: 52).glassChrome(in: Circle())
            }.accessibilityLabel("Filter Bots, \(filter.rawValue)")
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").font(.system(size: 20)).accessibilityHidden(true)
                TextField("Search your Bots", text: $model.search)
                    .font(.body).textInputAutocapitalization(.never).autocorrectionDisabled()
                    .focused($searching).submitLabel(.search).onSubmit { searching = false }
                    .accessibilityLabel("Search your Bots")
                if !model.search.isEmpty {
                    Button { model.search = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                        .accessibilityLabel("Clear search")
                }
            }.padding(.horizontal, 17).frame(minHeight: 52).glassChrome(in: Capsule())
        }.buttonStyle(.plain).padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 12)
    }

    private var connectionWelcome: some View {
        VStack(spacing: 22) {
            Spacer()
            BotAvatar(size: 100)
            Text("Your Bots, wherever you go").font(.title2.weight(.medium)).multilineTextAlignment(.center)
            Text(remote.status).font(.body).foregroundStyle(.secondary).multilineTextAlignment(.center)
            if remote.needsApproval, let phone = remote.account.localDevice {
                Text(phone.fingerprint).font(.system(.body, design: .monospaced))
                Text("Match this fingerprint on your computer, then choose Approve phone.").font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
            Button { remote.showConnection = true } label: {
                Label("Connect your computer", systemImage: "desktopcomputer").font(.body.weight(.medium))
                    .padding(.horizontal, 22).padding(.vertical, 14).glassChrome(in: Capsule())
            }.buttonStyle(.plain)
            Spacer()
            Text("Your computer runs the work. Your iPhone keeps you connected.").font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }.padding(30).frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct CreateBotView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var remote: RemoteController
    @State private var saving = false
    @State private var name = ""
    @State private var purpose = ""
    @State private var color = "purple"

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack { Spacer(); BotAvatar(color: color, size: 72); Spacer() }.padding()
                    TextField("Bot name", text: $name).textInputAutocapitalization(.words)
                    TextField("What will this Bot help with?", text: $purpose, axis: .vertical).lineLimit(3...5)
                    Picker("Color", selection: $color) {
                        Text("Violet").tag("purple")
                        Text("Rose").tag("pink")
                        Text("Amber").tag("ochre")
                    }
                } footer: { Text("Creates a Bot in your connected desktop workspace.") }
            }
            .navigationTitle("New Bot")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        saving = true
                        Task { if await remote.command(RemoteCommand(action: "create_bot", name: name, purpose: purpose, color: color)) { dismiss() }; saving = false }
                    }.disabled(saving || !remote.online || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}
