import SwiftUI

struct ConversationView: View {
    private let initialBot: Bot
    init(bot: Bot) { initialBot = bot }
    private var bot: Bot { model.workspace.bots.first { $0.id == initialBot.id } ?? initialBot }
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var remote: RemoteController
    @State private var sending = false
    private var draft: Binding<String> { Binding(get: { remote.drafts[bot.id] ?? "" }, set: { remote.drafts[bot.id] = $0 }) }
    @FocusState private var composing: Bool
    @State private var info = false

    var body: some View {
        VStack(spacing: 0) {
            RemoteConnectionBanner()
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 20) {
                        if model.entries(for: bot).isEmpty {
                            VStack(spacing: 16) {
                                BotAvatar(color: bot.color, size: 70, appearance: bot.appearance)
                                Text("A fresh conversation").font(.title2.weight(.medium))
                                Text("Send a message to this Bot on \(remote.hostName).")
                                    .foregroundStyle(.secondary).multilineTextAlignment(.center)
                            }.frame(maxWidth: .infinity).padding(.vertical, 60)
                        }
                        ForEach(model.entries(for: bot)) { entry in
                            MessageRow(entry: entry)
                        }
                        Color.clear.frame(height: 1).id("bottom")
                    }.padding(20).frame(maxWidth: 760).frame(maxWidth: .infinity)
                }
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: model.entries(for: bot).count) { _, _ in
                    withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo("bottom", anchor: .bottom) }
                }
            }
        }
        .background(Palette.background)
        .safeAreaInset(edge: .bottom, spacing: 0) { composer }
        .toolbar {
            ToolbarItem(placement: .principal) {
                Button { info = true } label: { HStack(spacing: 10) { BotAvatar(color: bot.color, size: 24, appearance: bot.appearance); Text(bot.name).font(.headline).lineLimit(1) } }.accessibilityLabel("Bot details for \(bot.name)")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { info = true } label: { Image(systemName: "info.circle").frame(width: 44, height: 44) }.accessibilityLabel("Connection details")
            }
        }
        .sheet(isPresented: $info) {
            NavigationStack {
                RemoteBotDetailView(botID: bot.id)
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { info = false } } }
            }.presentationDetents([.medium, .large])
        }
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .bottom, spacing: 12) {
                TextField("Message \(bot.name)", text: draft, axis: .vertical)
                    .lineLimit(1...7).focused($composing).padding(.vertical, 12)
                    .accessibilityIdentifier("remote-chat-input")
                if remote.running.contains(bot.id) {
                    Button { Task { await remote.command(RemoteCommand(action: "stop", botID: bot.id)) } } label: { Image(systemName: "stop.fill").frame(width:44,height:44) }
                        .disabled(!remote.online).accessibilityLabel("Stop response")
                } else {
                    Button { send() } label: { Image(systemName: "arrow.up").font(.system(size:20,weight:.semibold)).foregroundStyle(.black).frame(width:38,height:38).background(.white,in:Circle()) }
                        .disabled(!remote.online || sending || draft.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty).accessibilityLabel("Send message")
                }
            }.padding(8).padding(.leading,14).glassChrome(in:RoundedRectangle(cornerRadius:28))
            if model.entries(for:bot).last?.state == .failed {
                Button("Retry response") { Task { await remote.command(RemoteCommand(action:"retry",botID:bot.id)) } }.font(.caption).disabled(!remote.online)
            }
            Text("Runs on \(remote.hostName)").font(.caption2).foregroundStyle(.secondary).frame(maxWidth:.infinity)
        }.padding(.horizontal,16).padding(.vertical,10).background(Palette.background)
    }
    private func send() {
        let text = draft.wrappedValue.trimmingCharacters(in:.whitespacesAndNewlines)
        guard !text.isEmpty, !sending else { return }; sending = true
        Task {
            if await remote.send(text,bot:bot), draft.wrappedValue.trimmingCharacters(in:.whitespacesAndNewlines) == text { draft.wrappedValue = "" }
            sending = false
        }
    }

}

private struct MessageRow: View {
    let entry: Entry
    var body: some View {
        if entry.kind == .activity {
            Label(entry.text, systemImage: "arrow.triangle.branch")
                .font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity).padding(.vertical, 8)
        } else {
            HStack {
                if entry.kind == .user { Spacer(minLength: 35) }
                VStack(alignment: .leading, spacing: 8) {
                    if let sender = entry.senderName { Text("Message from \(sender)").font(.caption).foregroundStyle(.secondary) }
                    if let provider = entry.provider { Text(provider).font(.caption2).foregroundStyle(.secondary) }
                    Text(entry.text).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                }
                .padding(16)
                .background(entry.kind == .user ? Color.primary.opacity(0.16) : Palette.card, in: RoundedRectangle(cornerRadius: 24))
                .contextMenu { ShareLink(item: entry.text) { Label("Share text", systemImage: "square.and.arrow.up") } }
                if entry.kind == .bot { Spacer(minLength: 20) }
            }
        }
    }
}
