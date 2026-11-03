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
    @State private var modelTask: Task<Void,Never>?
    @State private var modelRequest = UUID()
    @State private var editingAvatar = false
    @State private var browser = false
    @State private var vmViewer = false
    private var bot: Bot? { model.workspace.bots.first { $0.id == botID } }

    private var avatarColor: String { bot?.appearance?.color ?? bot?.color ?? "white" }
    private var tint: Color { (bot?.appearance == nil && bot?.color == "white") ? .primary : AvatarArtwork.color(avatarColor) }
    private var ink: Color {
        if bot?.appearance == nil && bot?.color == "white" { return Palette.background }
        return ["white", "amber", "orange", "green", "teal", "gray"].contains(avatarColor) ? .black : .white
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                if let bot {
                    header(bot)
                    Picker("Bot details", selection: $tab) { Text("Details").tag("Details"); Text("Library").tag("Library"); Text("Computer").tag("Computer") }
                        .pickerStyle(.segmented)
                    Group {
                        if tab == "Details" { details(bot) }
                        else if tab == "Library" { library(bot) }
                        else { computer }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                } else { Text("This Bot was removed on the desktop.").foregroundStyle(.secondary) }
            }.padding(.horizontal, 20).padding(.vertical, 24)
        }
        .background(Palette.background)
        .navigationTitle("Bot details").navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $vmViewer) { CloudBrowserView(isVM: true, botID: botID, remote: remote) }
        .sheet(isPresented: $browser) { CloudBrowserView(botID: botID, remote: remote) }
        .sheet(isPresented: $editingAvatar) {
            if let bot {
                BotAvatarPicker(bot: bot, save: { appearance in
                    await remote.command(RemoteCommand(action: "update_avatar", botID: botID, appearance: appearance))
                }, close: { editingAvatar = false })
                .presentationDragIndicator(.visible)
            }
        }
        .onDisappear { modelTask?.cancel(); modelRequest = UUID(); loading = false }
        .onAppear { if let bot { provider = bot.aiConfiguration?.activeProvider ?? bot.aiConfiguration?.providers.first?.provider ?? remote.defaultProvider ?? .codex; modelID = bot.aiConfiguration?.providers.first { $0.provider == provider }?.model ?? "" } }
        .onChange(of: tab) { _, value in if value == "Library", let bot { Task { files = await remote.files(bot) } } }
    }

    private func header(_ bot: Bot) -> some View {
        VStack(spacing: 6) {
            Button { editingAvatar = true } label: {
                BotAvatar(color: bot.color, size: 80, appearance: bot.appearance)
            }.buttonStyle(.plain).accessibilityLabel("Change Bot avatar").disabled(!remote.online)
            Text(bot.name).font(.title2.weight(.semibold)).padding(.top, 8)
            if bot.isMain != true, !bot.purpose.isEmpty {
                Text(bot.purpose).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center).lineLimit(3)
            }
        }.frame(maxWidth: .infinity)
    }

    private func details(_ bot: Bot) -> some View {
        VStack(alignment: .leading, spacing: 22) {
            DetailCard(title: "Organize") {
                Toggle("Pinned to top", isOn: Binding(get: { remote.isPinned(bot) }, set: { remote.setPinned($0, bot: bot) }))
                    .tint(tint)
            }
            DetailCard(title: "Browser and VM", footer: "These open windows on the computer that runs your Bots.") {
                DetailAction(title: "Local browser", systemImage: "globe", disabled: !remote.online) { browser = true }
                DetailAction(title: "Linux VM", systemImage: "desktopcomputer", disabled: !remote.online) { vmViewer = true }
            }
            if let members = bot.memberIDs {
                DetailCard(title: "Group members", footer: "Each member answers with its own provider and model.") {
                    ForEach(model.workspace.bots.filter { members.contains($0.id) }) { Text($0.name) }
                }
            } else { providerCard(bot) }
            if !(bot.memory ?? []).isEmpty {
                DetailCard(title: "Memory") { ForEach(bot.memory ?? [], id: \.self) { Text($0).font(.subheadline).textSelection(.enabled) } }
            }
            if !(model.workspace.sharedMemory ?? []).isEmpty {
                DetailCard(title: "Shared memory") { ForEach(model.workspace.sharedMemory ?? [], id: \.self) { Text($0).font(.subheadline).textSelection(.enabled) } }
            }
            DetailCard(title: "Routines", footer: "Ask the Bot to run a task at a set time, repeat it hourly, daily or weekly, or run it when another Bot messages it. Your computer must be running; missed runs catch up once.") {
                if (bot.schedules ?? []).isEmpty { Text("No routines yet.").font(.subheadline).foregroundStyle(.secondary) }
                ForEach(Array((bot.schedules ?? []).enumerated()), id: \.element.id) { index, task in
                    if index > 0 { Divider() }
                    VStack(alignment: .leading, spacing: 4) {
                        Text(task.name).font(.subheadline.weight(.semibold))
                        Text("\(task.enabled ? (task.nextRun ?? "When another Bot messages") : "Paused") · \(task.recurrence) · \(task.timezone)").font(.caption).foregroundStyle(.secondary)
                        Button("Cancel routine", role: .destructive) { Task { await remote.command(RemoteCommand(action: "cancel_task", botID: bot.id, taskID: task.id)) } }
                            .font(.subheadline).disabled(!remote.online).padding(.top, 2)
                    }
                }
            }
        }
    }

    private func providerCard(_ bot: Bot) -> some View {
        DetailCard(title: "Provider and model", footer: "Only this provider and model answer for this Bot. Stop its response before changing them.") {
            Picker("Provider", selection: $provider) {
                ForEach(remote.providers) { value in Text(value.provider.name).tag(value.provider) }
                if !remote.providers.contains(where: { $0.provider == provider }) { Text(provider.name + " · not installed").tag(provider) }
            }.onChange(of: provider) { _, value in
                modelTask?.cancel(); modelRequest = UUID(); loading = false
                modelID = bot.aiConfiguration?.providers.first { $0.provider == value }?.model ?? ""; models = []
            }
            if !models.isEmpty {
                Picker("Model", selection: $modelID) {
                    Text("CLI default").tag("")
                    ForEach(models) { Text($0.name).tag($0.id) }
                    if !modelID.isEmpty, !models.contains(where: { $0.id == modelID }) { Text(modelID).tag(modelID) }
                }
            }
            TextField("Model ID, blank uses the CLI default", text: $modelID)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
                .padding(.horizontal, 12).frame(minHeight: 44).background(Palette.background, in: RoundedRectangle(cornerRadius: 10))
            if provider == .codex || provider == .opencode {
                DetailAction(title: loading ? "Loading models…" : "Load models from computer", systemImage: "arrow.down.circle", disabled: loading || !remote.online) { loadModels() }
            }
            Button { apply(bot) } label: {
                Text(saving ? "Saving…" : "Apply").font(.headline).foregroundStyle(ink)
                    .frame(maxWidth: .infinity).frame(height: 46).background(tint, in: Capsule())
            }.buttonStyle(.plain).disabled(saving || !remote.online || remote.running.contains(botID)).opacity(saving || !remote.online || remote.running.contains(botID) ? 0.4 : 1)
        }
    }

    private func library(_ bot: Bot) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if files.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "doc.text").font(.system(size: 28, weight: .light)).foregroundStyle(.secondary)
                    Text("No files yet").font(.headline)
                    Text("Files this Bot creates on your computer show up here.").font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }.frame(maxWidth: .infinity).padding(.vertical, 32)
            }
            if !files.isEmpty {
                DetailCard(title: nil) {
                    ForEach(Array(files.enumerated()), id: \.element.id) { index, file in
                        if index > 0 { Divider() }
                        Label(file.name.replacingOccurrences(of: #"^[0-9A-Fa-f]{8}(-[0-9A-Fa-f]{4}){3}-[0-9A-Fa-f]{12}-"#, with: "", options: .regularExpression), systemImage: "doc.text")
                            .font(.subheadline).frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            DetailAction(title: "Refresh", systemImage: "arrow.clockwise", disabled: !remote.online) { Task { files = await remote.files(bot) } }
        }
    }

    private var computer: some View {
        VStack(alignment: .leading, spacing: 22) {
            DetailCard(title: "Runs on", footer: "This iPhone only controls your Bots. Their work and files stay on your computer and keep going when the phone disconnects.") {
                Label(remote.hostName, systemImage: "desktopcomputer").font(.headline)
                Text(remote.status).font(.subheadline).foregroundStyle(.secondary)
            }
            DetailAction(title: "Connection settings", systemImage: "gearshape", disabled: false) {
                dismiss(); Task { try? await Task.sleep(for: .milliseconds(500)); remote.showConnection = true }
            }
        }
    }

    private func loadModels() {
        modelTask?.cancel(); modelRequest = UUID()
        let request = modelRequest, requestedProvider = provider
        loading = true
        modelTask = Task { @MainActor in
            let loaded = await remote.models(requestedProvider)
            guard !Task.isCancelled, request == modelRequest, provider == requestedProvider else { return }
            models = loaded; loading = false
        }
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

/// A titled group on a rounded card. Content always aligns to the leading edge.
private struct DetailCard<Content: View>: View {
    let title: String?
    var footer: String? = nil
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title {
                Text(title).font(.footnote.weight(.semibold)).foregroundStyle(.secondary).padding(.horizontal, 4)
                    .accessibilityAddTraits(.isHeader)
            }
            VStack(alignment: .leading, spacing: 14) { content }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16).background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 18))
            if let footer {
                Text(footer).font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true).padding(.horizontal, 4)
            }
        }
    }
}

/// A full-width row with an icon, used for actions inside cards.
private struct DetailAction: View {
    let title: String
    let systemImage: String
    let disabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: systemImage).frame(width: 24)
                Text(title)
                Spacer()
                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
            }
            .font(.body).foregroundStyle(.primary)
            .padding(.horizontal, 14).frame(minHeight: 46)
            .background(Palette.background, in: RoundedRectangle(cornerRadius: 12))
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }.buttonStyle(.plain).disabled(disabled).opacity(disabled ? 0.4 : 1)
    }
}
