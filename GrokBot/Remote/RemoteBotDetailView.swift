import SwiftUI

struct RemoteBotDetailView: View {
    let botID: UUID
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var remote: RemoteController
    @Environment(\.dismiss) private var dismiss
    @State private var tab = "Details"
    @State private var provider = CLIProvider.codex
    @State private var modelID = ""
    @State private var models: [AvailableCLIModel] = []
    @State private var files: [RemoteFile] = []
    @State private var saving = false
    @State private var loading = false
    @State private var editingAvatar = false
    private var bot: Bot? { model.workspace.bots.first { $0.id == botID } }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                if let bot {
                    Button { editingAvatar = true } label: {
                        BotAvatar(color: bot.color, size: 80, appearance: bot.appearance)
                    }.buttonStyle(.plain).accessibilityLabel("Change Bot avatar").disabled(!remote.online)
                    Text(bot.name).font(.title2.weight(.medium))
                    Picker("Bot details",selection:$tab) { Text("Details").tag("Details");Text("Library").tag("Library");Text("Computer").tag("Computer") }.pickerStyle(.segmented)
                    if tab == "Details" {
                        if let members = bot.memberIDs {
                            Text("Group members").font(.headline)
                            ForEach(model.workspace.bots.filter { members.contains($0.id) }) { Text($0.name) }
                            Text("Each member uses its own selected provider and model.").font(.footnote).foregroundStyle(.secondary)
                        } else {
                            VStack(alignment:.leading,spacing:16) {
                                Text("Provider & model").font(.headline)
                                Picker("Provider",selection:$provider) {
                                    ForEach(remote.providers) { value in Text(value.provider.name).tag(value.provider) }
                                    if !remote.providers.contains(where: { $0.provider == provider }) { Text(provider.name + " · not installed").tag(provider) }
                                }.onChange(of:provider) { _, value in
                                    modelID = bot.aiConfiguration?.providers.first { $0.provider == value }?.model ?? ""; models = []
                                }
                                if !models.isEmpty {
                                    Picker("Model",selection:$modelID) {
                                        Text("CLI default").tag("")
                                        ForEach(models) { Text($0.name).tag($0.id) }
                                        if !modelID.isEmpty, !models.contains(where:{$0.id == modelID}) { Text(modelID).tag(modelID) }
                                    }
                                }
                                TextField("Exact model ID · blank uses CLI default",text:$modelID).textInputAutocapitalization(.never).autocorrectionDisabled().textFieldStyle(.roundedBorder)
                                if provider == .codex || provider == .opencode {
                                    Button(loading ? "Loading models…" : "Load models from desktop") { loading = true; Task { models = await remote.models(provider); loading = false } }.disabled(loading || !remote.online)
                                }
                                Button(saving ? "Saving…" : "Apply provider and model") { apply(bot) }.disabled(saving || !remote.online || remote.running.contains(botID))
                                Text("Only this selected provider and model answers for this Bot. Stop its response before changing models.").font(.footnote).foregroundStyle(.secondary)
                            }
                        }
                        if !bot.purpose.isEmpty { Text(bot.purpose).foregroundStyle(.secondary) }
                        if !(bot.memory ?? []).isEmpty { Text("This Bot’s memory").font(.headline); ForEach(bot.memory ?? [],id:\.self) { Text($0).textSelection(.enabled) } }
                        if !(model.workspace.sharedMemory ?? []).isEmpty { Text("Shared memory").font(.headline); ForEach(model.workspace.sharedMemory ?? [],id:\.self) { Text($0).textSelection(.enabled) } }
                    } else if tab == "Library" {
                        if files.isEmpty { Text("No files yet").foregroundStyle(.secondary) }
                        ForEach(files) { file in Label(file.name,systemImage:"doc.text").frame(maxWidth:.infinity,alignment:.leading) }
                        Button("Refresh from desktop") { Task { files = await remote.files(bot) } }.disabled(!remote.online)
                    } else {
                        Label(remote.hostName,systemImage:"desktopcomputer").font(.headline)
                        Text(remote.status).foregroundStyle(.secondary)
                        Text("This iPhone is a controller. CLI sessions, files and work stay on the desktop and continue when the phone disconnects.").font(.footnote).foregroundStyle(.secondary)
                        Button("Connection settings") { dismiss(); Task { try? await Task.sleep(for:.milliseconds(500)); remote.showConnection = true } }
                    }
                } else { Text("This Bot was removed on the desktop.").foregroundStyle(.secondary) }
            }.padding(24)
        }.navigationTitle("Bot details").navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $editingAvatar) {
                if let bot {
                    BotAvatarPicker(bot: bot, save: { appearance in
                        await remote.command(RemoteCommand(action: "update_avatar", botID: botID, appearance: appearance))
                    }, close: { editingAvatar = false })
                    .presentationDragIndicator(.visible)
                }
            }
            .onAppear { if let bot { provider = bot.aiConfiguration?.activeProvider ?? bot.aiConfiguration?.providers.first?.provider ?? remote.defaultProvider ?? .codex; modelID = bot.aiConfiguration?.providers.first { $0.provider == provider }?.model ?? "" } }
            .onChange(of:tab) { _, value in if value == "Library", let bot { Task { files = await remote.files(bot) } } }
    }
    private func apply(_ bot: Bot) {
        guard modelID.count <= 200, !modelID.contains(where: { $0.isNewline }) else { remote.error = "Enter a model ID of up to 200 characters."; return }
        var configuration = bot.aiConfiguration ?? BotAIConfiguration(providers: [])
        configuration.providers.removeAll { $0.provider == provider }; configuration.providers.append(BotAIProvider(provider:provider,model:modelID.trimmingCharacters(in:.whitespacesAndNewlines)))
        configuration.activeProvider = provider; configuration.replyMode = .one
        saving = true
        Task { _ = await remote.command(RemoteCommand(action:"configure_bot",botID:botID,configuration:configuration)); saving = false }
    }
}
