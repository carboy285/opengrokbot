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
    @ScaledMetric(relativeTo: .largeTitle) private var heroSize: CGFloat = 108

    private var featured: Bot? { model.workspace.bots.first(where: { $0.isMain == true }) ?? model.workspace.bots.first }
    private var showFeatured: Bool { model.search.isEmpty && filter == .all }
    private var bots: [Bot] {
        model.visibleBots.filter { bot in
            (!showFeatured || bot.id != featured?.id) &&
            (filter != .working || remote.running.contains(bot.id)) &&
            (filter != .groups || bot.memberIDs != nil)
        }
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
                RoundButton(symbol: "person.crop.circle", label: "Account and settings") { settings = true }
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
                if showFeatured, let bot = featured {
                    NavigationLink(value: bot) {
                        VStack(spacing: 16) {
                            ZStack(alignment: .bottomTrailing) {
                                BotAvatar(color: bot.color, size: min(heroSize, 150), appearance: bot.appearance)
                                Image(systemName: "star.fill").font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(.white).frame(width: 27, height: 27)
                                    .background(.orange, in: Circle())
                                    .overlay(Circle().stroke(Palette.background, lineWidth: 3)).offset(x: 3, y: 3)
                            }
                            Text(bot.name).font(.title2.weight(.medium)).foregroundStyle(.primary)
                            Text("Your assistant").font(.subheadline).foregroundStyle(.secondary)
                        }.frame(maxWidth: .infinity).padding(.top, 36).padding(.bottom, 42)
                            .contentShape(Rectangle())
                    }.buttonStyle(.plain).accessibilityLabel("Open \(bot.name), your main assistant")
                }
                ForEach(bots) { bot in
                    NavigationLink(value: bot) { botRow(bot) }.buttonStyle(.plain)
                        .contextMenu {
                            if bot.isMain != true {
                                Button("Delete Bot", systemImage: "trash", role: .destructive) { deleting = bot }.disabled(!remote.online)
                            }
                        }
                }
                if bots.isEmpty, !showFeatured || featured == nil {
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

    private func botRow(_ bot: Bot) -> some View {
        let latest = model.entries(for: bot).last
        return HStack(spacing: 18) {
            BotAvatar(color: bot.color, size: 50, appearance: bot.appearance)
            VStack(alignment: .leading, spacing: 7) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(bot.name).font(.title3.weight(.semibold)).foregroundStyle(.primary).lineLimit(1)
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
            Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(.quaternary)
        }
        .padding(.horizontal, 24).padding(.vertical, 23).contentShape(Rectangle())
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
                Text("Match this fingerprint on your Mac, then choose Approve phone.").font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
            Button { remote.showConnection = true } label: {
                Label("Connect your Mac", systemImage: "desktopcomputer").font(.body.weight(.medium))
                    .padding(.horizontal, 22).padding(.vertical, 14).glassChrome(in: Capsule())
            }.buttonStyle(.plain)
            Spacer()
            Text("Your Mac runs the work. Your iPhone keeps you connected.").font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
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
