import AppKit
import SwiftUI

/// Header menu: switch the model for this Bot without opening its details, see which credentials it uses, and turn compare on.
struct MacModelMenu: View {
    let bot: Bot
    @EnvironmentObject private var app: AppModel
    @EnvironmentObject private var desktop: MacAppModel
    private var configuration: BotAIConfiguration { desktop.aiConfiguration(for: bot) }
    private var busy: Bool { desktop.runningBots.contains(bot.id) }
    private var active: BotAIProvider? { configuration.providers.first { $0.provider == configuration.activeProvider } ?? configuration.providers.first }

    private var title: String {
        guard let active else { return "Choose a model" }
        if configuration.replyMode == .all, configuration.providers.count > 1 { return "Comparing \(configuration.providers.count) models" }
        return active.provider.name + (active.model.isEmpty ? "" : " · " + active.model)
    }

    var body: some View {
        Menu {
            ForEach(configuration.providers) { choice in
                Button { choose(choice.provider) } label: {
                    Label(choice.provider.name + (choice.model.isEmpty ? "" : " · " + choice.model), systemImage: choice.provider == active?.provider && configuration.replyMode == .one ? "checkmark" : "circle")
                }.disabled(busy)
            }
            if configuration.providers.count > 1 {
                Divider()
                Toggle("Compare all enabled models", isOn: Binding(get: { configuration.replyMode == .all }, set: { on in set(on) })).disabled(busy)
            }
            if let active { Divider(); Text(CLISignIn.credentialLabel(for: active.provider)) }
            Divider()
            Button("Add knowledge files…") { addKnowledge() }
            Button("Open Knowledge folder") { openKnowledge() }
            Divider()
            Button("Providers & models…") { desktop.showBotInspector = true }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "cpu").font(.system(size: 11))
                Text(title).font(.system(size: 12)).lineLimit(1)
                Image(systemName: "chevron.down").font(.system(size: 9, weight: .semibold))
            }
            .padding(.horizontal, 11).padding(.vertical, 7).contentShape(Capsule()).glassChrome(in: Capsule())
        }
        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
        .accessibilityLabel("Model for \(bot.name): \(title)")
        .help("Switch the model for this Bot")
    }

    private func addKnowledge() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true; panel.canChooseDirectories = false
        panel.message = "Choose PDFs or text files that \(bot.name) can search"
        guard panel.runModal() == .OK else { return }
        let added = (try? KnowledgeSearch.add(panel.urls, to: desktop.workingDirectory(for: bot))) ?? 0
        desktop.sendFeedback[bot.id] = added == 0 ? "No supported files were added. Use PDF, text, Markdown, CSV or similar files under 8 MB." : "Added \(added) file\(added == 1 ? "" : "s") to \(bot.name)’s Knowledge. Ask it to search them."
    }

    private func openKnowledge() {
        let folder = KnowledgeSearch.folder(for: desktop.workingDirectory(for: bot))
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        NSWorkspace.shared.open(folder)
    }

    private func choose(_ provider: CLIProvider) {
        var value = configuration; value.activeProvider = provider; value.replyMode = .one
        _ = app.setAIConfiguration(value, for: bot)
    }
    private func set(_ compare: Bool) {
        var value = configuration; value.replyMode = compare ? .all : .one
        _ = app.setAIConfiguration(value, for: bot)
    }
}
