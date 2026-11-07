import AppKit
import SwiftUI

/// The menu-bar window: pick a Bot, type a request, send it without opening the main window.
struct MacQuickAskView: View {
    @EnvironmentObject private var app: AppModel
    @EnvironmentObject private var desktop: MacAppModel
    @State private var botID: UUID?
    @State private var text = ""
    @State private var status: String?

    private var bots: [Bot] { app.workspace.bots }
    private var selected: Bot? { bots.first { $0.id == botID } ?? bots.first }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Ask a Bot").font(.system(size: 13, weight: .semibold))
            if bots.isEmpty {
                Text("Create a Bot in OpenGrokBot first.").font(.system(size: 12)).foregroundStyle(.secondary)
            } else {
                Picker("Bot", selection: Binding(get: { selected?.id ?? bots[0].id }, set: { botID = $0 })) {
                    ForEach(bots) { Text($0.name).tag($0.id) }
                }.labelsHidden()
                TextField("What do you need?", text: $text, axis: .vertical).lineLimit(1...5).textFieldStyle(.roundedBorder).onSubmit(send)
                HStack {
                    if let bot = selected, desktop.runningBots.contains(bot.id) { ProgressView().controlSize(.small); Text("\(bot.name) is working…").font(.system(size: 12)).foregroundStyle(.secondary) }
                    else if let status { Text(status).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(2) }
                    Spacer()
                    Button("Send", action: send).keyboardShortcut(.return, modifiers: .command).disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            Divider()
            Button("Open OpenGrokBot") { openMain() }.buttonStyle(.plain).font(.system(size: 12))
        }.padding(14).frame(width: 320)
    }

    private func send() {
        guard let bot = selected else { return }
        let message = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty else { return }
        if desktop.send(message, to: bot, app: app) {
            text = ""; status = "Sent to \(bot.name)."; desktop.selectedID = bot.id
        } else { status = desktop.sendFeedback[bot.id] ?? "That could not be sent." }
    }

    private func openMain() {
        NSApp.activate(ignoringOtherApps: true)
        if let window = NSApp.windows.first(where: { $0.identifier?.rawValue == "OpenGrokBot.workspace" }) { window.makeKeyAndOrderFront(nil) }
    }
}
