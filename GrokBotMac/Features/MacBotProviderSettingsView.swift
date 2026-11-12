import SwiftUI

struct MacBotProviderSettingsView: View {
    let bot: Bot
    @EnvironmentObject private var app: AppModel
    @EnvironmentObject private var desktop: MacAppModel
    @State private var modelDrafts: [CLIProvider:String] = [:]
    @State private var serverDrafts: [CLIProvider:String] = [:]
    @State private var feedback: String?
    private var configuration: BotAIConfiguration { desktop.aiConfiguration(for: bot) }
    private var busy: Bool { desktop.runningBots.contains(bot.id) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Providers & models").font(.system(size: 13, weight: .semibold)).foregroundStyle(MacTheme.secondary)
                .padding(.horizontal, 4).accessibilityAddTraits(.isHeader)
            if configuration.providers.count > 1 {
                Picker("Active provider", selection: Binding(get: { configuration.activeProvider ?? configuration.providers[0].provider }, set: { provider in update { $0.activeProvider = provider } })) {
                    ForEach(configuration.providers) { choice in Text(choice.provider.name).tag(choice.provider) }
                }.disabled(busy).accessibilityIdentifier("bot-active-provider").padding(.horizontal, 4).padding(.bottom, 4)
            }
            if configuration.providers.count > 1 {
                Toggle("Ask every enabled provider and compare answers", isOn: Binding(get: { configuration.replyMode == .compare }, set: { on in update { $0.replyMode = on ? .compare : .one } }))
                    .toggleStyle(.checkbox).font(.system(size: 13)).disabled(busy).padding(.horizontal, 4).accessibilityIdentifier("bot-compare-toggle")
            }
            ForEach(CLIProvider.allCases) { provider in
                let installed = desktop.installedCLIs.first { $0.provider == provider }
                let choice = configuration.providers.first { $0.provider == provider }
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Toggle(provider.name, isOn: Binding(get: { choice != nil }, set: { enabled in
                            update { value in
                                if enabled { value.providers.append(BotAIProvider(provider: provider)); if value.activeProvider == nil { value.activeProvider = provider } }
                                else { value.providers.removeAll { $0.provider == provider }; if value.activeProvider == provider { value.activeProvider = value.providers.first?.provider } }
                            }
                        })).toggleStyle(.checkbox).font(.system(size: 14, weight: .medium))
                            .disabled(busy || (installed == nil && choice == nil))
                            .accessibilityIdentifier("bot-provider-\(provider.rawValue)")
                        Spacer()
                        if installed == nil && provider.isLocalServer {
                            Button("Check again") { desktop.setCLIPath(serverDrafts[provider] ?? provider.defaultServer, provider: provider) }.buttonStyle(InspectorButtonStyle(compact: true))
                        } else if installed == nil {
                            Button("Set up") { desktop.setupProvider = provider; desktop.panel = .setup }.buttonStyle(InspectorButtonStyle(compact: true))
                        }
                    }
                    if choice != nil { Text(CLISignIn.credentialLabel(for: provider)).font(.system(size: 11)).foregroundStyle(MacTheme.secondary) }
                    if installed == nil && provider.isLocalServer {
                        // Ollama and LM Studio: a server on this Mac, not a CLI.
                        Text("Not running. Open \(provider.name) and start its server\(provider == .lmstudio ? " (Developer tab)" : ""), then check again.").font(.system(size: 11)).foregroundStyle(MacTheme.secondary)
                        HStack(spacing: 8) {
                            TextField("Address", text: Binding(get: { serverDrafts[provider] ?? provider.defaultServer }, set: { serverDrafts[provider] = $0 }))
                                .textFieldStyle(.roundedBorder).font(.system(size: 12))
                            Link("Get \(provider.name) ↗", destination: provider.guideURL).font(.system(size: 12))
                        }
                    } else if installed == nil { Text("Not installed on this Mac").font(.system(size: 11)).foregroundStyle(MacTheme.secondary) }
                    else if let installed, provider.isLocalServer { Text(installed.version).font(.system(size: 11)).foregroundStyle(MacTheme.secondary) }
                    if let choice {
                        if !(desktop.modelCatalogs[provider] ?? []).isEmpty {
                            Picker("Model", selection: Binding(get: { choice.model }, set: { model in
                                modelDrafts[provider] = model; saveModel(model, provider: provider)
                            })) {
                                Text("CLI default").tag("")
                                ForEach(desktop.modelCatalogs[provider] ?? []) { model in Text(model.name).tag(model.id) }
                                if !choice.model.isEmpty && !(desktop.modelCatalogs[provider] ?? []).contains(where: { $0.id == choice.model }) { Text(choice.model).tag(choice.model) }
                            }.font(.system(size: 12)).disabled(busy).accessibilityIdentifier("bot-model-picker-\(provider.rawValue)")
                        }
                        HStack(spacing: 8) {
                            TextField("Model ID · blank uses CLI default", text: Binding(get: { modelDrafts[provider] ?? choice.model }, set: { modelDrafts[provider] = $0 }))
                                .textFieldStyle(.roundedBorder).font(.system(size: 12))
                                .accessibilityIdentifier("bot-model-id-\(provider.rawValue)")
                                .onSubmit { saveModel(modelDrafts[provider] ?? choice.model, provider: provider) }
                            Button("Apply") { saveModel(modelDrafts[provider] ?? choice.model, provider: provider) }
                                .buttonStyle(InspectorButtonStyle(compact: true)).accessibilityLabel("Apply \(provider.name) model")
                        }.disabled(busy)
                        if provider == .codex || provider == .opencode || provider.isLocalServer {
                            Button(desktop.loadingModels.contains(provider) ? "Loading models…" : "Load available models") { desktop.loadModels(for: provider) }
                                .buttonStyle(InspectorButtonStyle(compact: true)).disabled(desktop.loadingModels.contains(provider) || installed == nil)
                                .accessibilityLabel("Load \(provider.name) models")
                        }
                        if let note = desktop.modelCatalogFeedback[provider] { Text(note).font(.system(size: 11)).foregroundStyle(MacTheme.secondary) }
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14).background(MacTheme.panel, in: RoundedRectangle(cornerRadius: 16))
            }
            Text("Only the active provider and model answer for this Bot. Model access follows each CLI’s account.")
                .font(.system(size: 12)).foregroundStyle(MacTheme.secondary).fixedSize(horizontal: false, vertical: true).padding(.horizontal, 4)
            if busy { Text("Stop the current response to change providers or models.").font(.system(size: 12)).foregroundStyle(MacTheme.secondary).padding(.horizontal, 4) }
            if let feedback { Text(feedback).font(.system(size: 12)).foregroundStyle(MacTheme.secondary).padding(.horizontal, 4) }
        }.onChange(of: bot.id) { _, _ in modelDrafts = [:]; feedback = nil }
    }

    private func saveModel(_ model: String, provider: CLIProvider) {
        let value = model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.count <= 200, !value.contains(where: { $0.isNewline }) else { feedback = "Enter a model ID of up to 200 characters."; return }
        update { configuration in if let index = configuration.providers.firstIndex(where: { $0.provider == provider }) { configuration.providers[index].model = value } }
        modelDrafts[provider] = value
        feedback = value.isEmpty ? "Using this CLI’s default model." : "Model set to \(value)."
    }
    private func update(_ change: (inout BotAIConfiguration) -> Void) {
        guard !busy else { return }
        var value = configuration; change(&value); if value.providers.count < 2 { value.replyMode = .one }
        _ = app.setAIConfiguration(value, for: bot)
    }
}
