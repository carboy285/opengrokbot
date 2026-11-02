import SwiftUI

struct ConversationView: View {
    private let initialBot: Bot
    init(bot: Bot) { initialBot = bot }
    private var bot: Bot { model.workspace.bots.first { $0.id == initialBot.id } ?? initialBot }
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var remote: RemoteController
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var sending = false
    @State private var info = false
    @State private var nearBottom = true
    @State private var userScrolling = false
    @State private var scrollTask: Task<Void,Never>?
    @FocusState private var composing: Bool
    private var draft: Binding<String> { Binding(get: { remote.drafts[bot.id] ?? "" }, set: { remote.drafts[bot.id] = $0 }) }
    private var canSend: Bool { remote.online && !sending && !draft.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    private var avatarColor: String { bot.appearance?.color ?? bot.color }
    private var composerTint: Color {
        bot.appearance == nil && bot.color == "white" ? .primary : AvatarArtwork.color(avatarColor)
    }
    private var composerInk: Color {
        if bot.appearance == nil && bot.color == "white" { return Palette.background }
        return ["white", "amber", "orange", "green", "teal", "gray"].contains(avatarColor) ? .black : .white
    }
    private var transcript: String {
        model.entries(for: bot).map { "\($0.kind == .user ? "You" : $0.senderName ?? bot.name):\n\($0.text)" }.joined(separator: "\n\n")
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 22) {
                    if model.entries(for: bot).isEmpty { emptyConversation }
                    ForEach(model.entries(for: bot)) { entry in
                        MessageRow(entry: entry).equatable().id(entry.id)
                    }
                    Color.clear.frame(height: 1).id("bottom")
                }.padding(.horizontal, 20).padding(.top, 22).padding(.bottom, 24)
                    .frame(maxWidth: 760).frame(maxWidth: .infinity)
            }
            .defaultScrollAnchor(.bottom, for: .initialOffset)
            .scrollDismissesKeyboard(.interactively)
            .onScrollPhaseChange { _, phase in
                userScrolling = phase == .tracking || phase == .interacting || phase == .decelerating
            }
            .onScrollGeometryChange(for: ChatScrollMetrics.self) { geometry in
                ChatScrollMetrics(height: geometry.contentSize.height, viewport: geometry.containerSize.height,
                                  bottom: geometry.visibleRect.maxY)
            } action: { old, next in
                // Content growth is not a user scroll. Keep the existing follow intent
                // until the person actually scrolls away from the latest message.
                if userScrolling { nearBottom = next.bottom >= next.height - 80 }
                if nearBottom && !userScrolling && (old.height != next.height || old.viewport != next.viewport) {
                    scrollToLatest(proxy)
                }
            }
            .task(id: bot.id) { nearBottom = true; scrollToLatest(proxy); if remote.online { _ = await remote.command(RemoteCommand(action: "touch_bot", botID: bot.id)) } }
            .onChange(of: model.entries(for: bot).last) { _, _ in
                if nearBottom && !userScrolling { scrollToLatest(proxy) }
            }
            .onDisappear { scrollTask?.cancel() }

        }
        .background(Palette.background)
        .safeAreaInset(edge: .top, spacing: 0) { header }
        .safeAreaInset(edge: .bottom, spacing: 0) { composer }
        .toolbar(.hidden, for: .navigationBar)
        .simultaneousGesture(DragGesture(minimumDistance: 24, coordinateSpace: .global).onEnded { value in
            if value.startLocation.x < 28, value.translation.width > 80, abs(value.translation.height) < 70 { dismiss() }
        })
        .sheet(isPresented: $info) {
            NavigationStack {
                RemoteBotDetailView(botID: bot.id)
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { info = false } } }
            }.presentationDetents([.medium, .large]).presentationDragIndicator(.visible)
        }
    }

    private var header: some View {
        VStack(spacing: 12) {
            ZStack {
                HStack {
                    RoundButton(symbol: "chevron.left", label: "Back to your Bots") { dismiss() }
                    Spacer()
                    Menu {
                        Button("Bot details", systemImage: "info.circle") { info = true }
                        ShareLink(item: transcript) { Label("Share conversation", systemImage: "square.and.arrow.up") }
                        if remote.running.contains(bot.id) {
                            Button("Stop response", systemImage: "stop") {
                                Task { await remote.command(RemoteCommand(action: "stop", botID: bot.id)) }
                            }.disabled(!remote.online)
                        }
                    } label: {
                        Image(systemName: "ellipsis").font(.system(size: 22, weight: .medium))
                            .frame(width: 50, height: 50).glassChrome(in: Circle())
                    }.buttonStyle(.plain).accessibilityLabel("Conversation options")
                }
                Button { info = true } label: {
                    HStack(spacing: 9) {
                        BotAvatar(color: bot.color, size: 28, appearance: bot.appearance)
                        Text(bot.name).font(.headline).lineLimit(1)
                    }.padding(.horizontal, 14).padding(.vertical, 10).glassChrome(in: Capsule())
                }.buttonStyle(.plain).frame(maxWidth: 220).accessibilityLabel("Bot details for \(bot.name)")
            }.padding(.horizontal, 20).padding(.top, 8)
            if !remote.online { RemoteConnectionBanner() }
        }.padding(.bottom, 10)
    }

    private var emptyConversation: some View {
        VStack(spacing: 20) {
            BotAvatar(color: bot.color, size: 84, appearance: bot.appearance)
            Text("What’s on your mind?").font(.title2.weight(.medium))
            Text(bot.purpose.isEmpty ? "Start a conversation with \(bot.name)." : bot.purpose)
                .font(.body).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }.frame(maxWidth: .infinity).padding(.horizontal, 24).padding(.vertical, 70)
    }

    private var composer: some View {
        VStack(spacing: 9) {
            if model.entries(for: bot).last?.state == .failed {
                Button {
                    Task { await remote.command(RemoteCommand(action: "retry", botID: bot.id)) }
                } label: { Label("Retry response", systemImage: "arrow.clockwise") }
                    .font(.footnote).disabled(!remote.online)
            }
            HStack(alignment: .bottom, spacing: 10) {
                Menu {
                    PasteButton(payloadType: String.self) { values in
                        let text = values.joined(separator: "\n")
                        draft.wrappedValue += (draft.wrappedValue.isEmpty ? "" : "\n") + text
                    }
                    Button("Bot details", systemImage: "info.circle") { info = true }
                } label: {
                    Image(systemName: "plus").font(.system(size: 21, weight: .regular))
                        .foregroundStyle(composerInk).frame(width: 36, height: 36)
                        .background(composerTint, in: Circle())
                        .overlay(Circle().stroke(.primary.opacity(0.08), lineWidth: 1).allowsHitTesting(false))
                        .frame(width: 48, height: 48).contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityLabel("Message options")
                TextField("Ask \(bot.name)", text: draft, axis: .vertical)
                    .font(.body).lineLimit(1...6).focused($composing).padding(.vertical, 7)
                    .accessibilityIdentifier("remote-chat-input")
                if remote.running.contains(bot.id) {
                    Button {
                        Task { await remote.command(RemoteCommand(action: "stop", botID: bot.id)) }
                    } label: {
                        Image(systemName: "stop.fill").font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(composerInk).frame(width: 38, height: 38)
                            .background(composerTint, in: Circle())
                            .frame(width: 48, height: 48).contentShape(Rectangle())
                    }.buttonStyle(.plain).disabled(!remote.online).accessibilityLabel("Stop response")
                } else {
                    Button { send() } label: {
                        ZStack {
                            Circle().fill(composerTint.opacity(canSend || sending ? 1 : 0.22))
                                .frame(width: 38, height: 38)
                                .overlay(Circle().stroke(.primary.opacity(0.08), lineWidth: 1).allowsHitTesting(false))
                            if sending {
                                ProgressView().controlSize(.small).tint(composerInk)
                            } else {
                                Image(systemName: "arrow.up").font(.system(size: 21, weight: .semibold))
                                    .foregroundStyle(canSend ? composerInk : Color.secondary)
                            }
                        }.frame(width: 48, height: 48).contentShape(Rectangle())
                    }.buttonStyle(.plain).disabled(!canSend).accessibilityLabel(sending ? "Sending message" : "Send message")
                }
            }
            .padding(5)
            .background {
                RoundedRectangle(cornerRadius: 30).fill(.clear)
                    .glassChrome(in: RoundedRectangle(cornerRadius: 30), interactive: false)
                    .allowsHitTesting(false)
            }
            .shadow(color: .black.opacity(0.035), radius: 14, y: 4)
        }.padding(.horizontal, 18).padding(.top, 8).padding(.bottom, 4)
    }

    private func scrollToLatest(_ proxy: ScrollViewProxy) {
        scrollTask?.cancel()
        scrollTask = Task { @MainActor in
            await Task.yield()
            guard !Task.isCancelled, nearBottom, !userScrolling else { return }
            var transaction = Transaction(); transaction.disablesAnimations = true
            withTransaction(transaction) { proxy.scrollTo("bottom", anchor: .bottom) }
        }
    }

    private func send() {
        let text = draft.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard canSend else { return }; sending = true; nearBottom = true
        Task {
            if await remote.send(text, bot: bot), draft.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines) == text { draft.wrappedValue = "" }
            sending = false
        }
    }
}

private struct ChatScrollMetrics: Equatable {
    var height: CGFloat
    var viewport: CGFloat
    var bottom: CGFloat
}

private struct MessageRow: View, Equatable {
    let entry: Entry
    private var formattedText: AttributedString {
        (try? AttributedString(markdown: entry.text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(entry.text)
    }
    var body: some View {
        if entry.kind == .activity || entry.delivery == "scheduled" {
            Label(entry.text, systemImage: entry.delivery == "scheduled" ? "clock" : "arrow.triangle.branch")
                .font(.footnote).foregroundStyle(.secondary).frame(maxWidth: .infinity).padding(.vertical, 5)
                .textSelection(.enabled)
        } else {
            HStack(alignment: .top, spacing: 0) {
                if entry.kind == .user { Spacer(minLength: 42) }
                VStack(alignment: .leading, spacing: 10) {
                    if let sender = entry.senderName {
                        Label("Message from \(sender)", systemImage: "paperplane").font(.caption).foregroundStyle(.secondary)
                    }
                    if entry.state == .failed, let provider = entry.provider, !provider.isEmpty {
                        Text(provider).font(.caption).foregroundStyle(.secondary)
                    }
                    if entry.text.isEmpty, entry.state == .streaming {
                        HStack(spacing: 8) { ProgressView().controlSize(.small); Text("Thinking…").foregroundStyle(.secondary) }
                    } else {
                        Text(formattedText).font(.body).lineSpacing(5).textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.horizontal, 19).padding(.vertical, 17)
                .background(entry.kind == .user ? Palette.userBubble : Palette.card, in: RoundedRectangle(cornerRadius: 26))
                .contextMenu {
                    ShareLink(item: entry.text) { Label("Share text", systemImage: "square.and.arrow.up") }
                }
                if entry.kind == .bot { Spacer(minLength: 26) }
            }
        }
    }
}
