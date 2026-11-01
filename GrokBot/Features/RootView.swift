import SwiftUI

struct RootView: View {
    @EnvironmentObject private var model: AppModel
    @State private var settings = false
    @State private var createBot = false

    var body: some View {
        NavigationStack {
            Group {
                if model.previewEnabled { roster } else { welcome }
            }
            .background(Palette.background)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    RoundButton(symbol: "person.crop.circle", label: "Settings") { settings = true }
                }
                if model.previewEnabled {
                    ToolbarItem(placement: .topBarTrailing) {
                        RoundButton(symbol: "plus", label: "Create a preview Bot") { createBot = true }
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $settings) { SettingsView() }
            .sheet(isPresented: $createBot) { CreateBotView() }
            .navigationDestination(for: Bot.self) { bot in ConversationView(bot: bot) }
        }
    }

    private var welcome: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                HStack { Spacer(); BotAvatar(size: 100); Spacer() }.padding(.top, 50).padding(.bottom, 16)
                VStack(alignment: .leading, spacing: 12) {
                    Text("Your Bots.\nRoom to work.").font(.system(.largeTitle, design: .rounded, weight: .semibold))
                    Text("An independent iPhone client foundation for Grok Bot.")
                        .font(.title3).foregroundStyle(.secondary)
                }
                StatusCard(title: "Integration awaiting verification", detail: "The 0.78.1 installer’s connection protocol still needs inspection. This app cannot sign in, sync Bots, or run tasks yet.", symbol: "cable.connector")
                VStack(spacing: 16) {
                    Button { model.enterPreview() } label: {
                        HStack { Text("Explore offline preview"); Spacer(); Image(systemName: "arrow.right") }
                            .font(.headline).padding(20).background(Color.primary, in: Capsule()).foregroundStyle(Palette.background)
                    }
                    NavigationLink { IntegrationView() } label: {
                        Label("View integration status", systemImage: "info.circle").font(.subheadline)
                    }
                }
                Text("Preview notes stay on your device. No account or credentials are requested.")
                    .font(.footnote).foregroundStyle(.secondary)
            }.padding(24).frame(maxWidth: 650)
                .frame(maxWidth: .infinity)
        }
    }

    private var roster: some View {
        VStack(spacing: 0) {
            PreviewBanner()
            List {
                if model.search.isEmpty, let first = model.workspace.bots.first {
                    NavigationLink(value: first) {
                        VStack(spacing: 16) {
                            BotAvatar(color: first.color, size: 88)
                            Text(first.name).font(.title3.weight(.medium))
                            Text("Your preview workspace").font(.caption).foregroundStyle(.secondary)
                        }.frame(maxWidth: .infinity).padding(.vertical, 30)
                    }
                    .buttonStyle(.plain)
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                }
                ForEach(model.visibleBots) { bot in
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
                    .swipeActions { Button("Delete", role: .destructive) { model.removeBot(bot) } }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .overlay {
                if model.visibleBots.isEmpty {
                    ContentUnavailableView(model.search.isEmpty ? "No preview Bots" : "No matches", systemImage: "magnifyingglass", description: Text(model.search.isEmpty ? "Use + to create a local preview Bot." : "Try another name or topic."))
                }
            }
            .searchable(text: $model.search, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search your Bots")
        }
    }
}

struct CreateBotView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
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
                } footer: { Text("Creates a local preview entry. No Bot is created in Grok Bot and no agent runs.") }
            }
            .navigationTitle("New preview Bot")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        if model.addBot(name: name, purpose: purpose, color: color) { dismiss() }
                    }.disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}
