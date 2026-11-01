import SwiftUI

struct RootView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var remote: RemoteController
    @State private var settings = false
    @State private var createBot = false

    var body: some View {
        NavigationStack {
            Group {
                if remote.hasSnapshot { roster }
                else {
                    VStack(spacing: 22) {
                        BotAvatar(size: 88)
                        Text("Your desktop, in your pocket").font(.title2.weight(.medium))
                        Text(remote.status).foregroundStyle(.secondary).multilineTextAlignment(.center)
                        Button("Connect Desktop") { remote.showConnection = true }.buttonStyle(.borderedProminent)
                    }.padding(28).frame(maxWidth: .infinity,maxHeight: .infinity)
                }
            }
            .background(Palette.background)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    RoundButton(symbol: "person.crop.circle", label: "Settings") { settings = true }
                }
                if remote.hasSnapshot {
                    ToolbarItem(placement: .topBarTrailing) {
                        RoundButton(symbol: "plus", label: "Create a Bot") { createBot = true }
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)

            .sheet(isPresented: $settings) { SettingsView() }
            .sheet(isPresented: $createBot) { CreateBotView() }
            .navigationDestination(for: Bot.self) { bot in ConversationView(bot: bot) }
        }
    }

    private var roster: some View {
        VStack(spacing: 0) {
            RemoteConnectionBanner()
            List {
                if model.search.isEmpty, let first = model.workspace.bots.first {
                    NavigationLink(value: first) {
                        VStack(spacing: 16) {
                            BotAvatar(color: first.color, size: 88)
                            Text(first.name).font(.title3.weight(.medium))
                            Text("Your assistant").font(.caption).foregroundStyle(.secondary)
                        }.frame(maxWidth: .infinity).padding(.vertical, 30)
                    }
                    .buttonStyle(.plain)
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                }
                ForEach(model.visibleBots.filter { !model.search.isEmpty || $0.id != model.workspace.bots.first?.id }) { bot in
                    NavigationLink(value: bot) {
                        HStack(spacing: 18) {
                            BotAvatar(color: bot.color, size: 44)
                            VStack(alignment: .leading, spacing: 7) {
                                Text(bot.name).font(.headline).lineLimit(2)
                                Text(model.latest(for: bot)).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                            }
                            .padding(.vertical, 8)
                        }.padding(.vertical, 6)
                    }
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                    .swipeActions { if bot.isMain != true { Button("Delete", role: .destructive) { Task { await remote.command(RemoteCommand(action: "delete_bot", botID: bot.id)) } } } }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .overlay {
                if model.visibleBots.isEmpty {
                    ContentUnavailableView(model.search.isEmpty ? "No Bots" : "No matches", systemImage: "magnifyingglass", description: Text(model.search.isEmpty ? "Use + to create a Bot." : "Try another name or topic."))
                }
            }
            .searchable(text: $model.search, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search your Bots")
        }
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
