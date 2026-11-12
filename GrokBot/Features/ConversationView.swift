import AVFoundation
import PhotosUI
import Speech
import SwiftUI
import UIKit

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
    @State private var showPhotos = false
    @State private var photoItems: [PhotosPickerItem] = []
    @EnvironmentObject private var voiceHub: PhoneVoiceHub
    @State private var attachNotice: String?
    @State private var clipboardHasImage = false
    @AppStorage("autoVoiceBotID") private var autoVoiceBotID = ""
    @StateObject private var dictation = PhoneDictation()
    @State private var nearBottom = true
    @State private var userScrolling = false
    @State private var scrollTask: Task<Void,Never>?
    @FocusState private var composing: Bool
    private var draft: Binding<String> { Binding(get: { remote.drafts[bot.id] ?? "" }, set: { remote.drafts[bot.id] = $0 }) }
    private var images: [RemoteAttachment] { remote.draftImages[bot.id] ?? [] }
    private var canSend: Bool { remote.online && !sending && (!draft.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !images.isEmpty) }
    private var hasContent: Bool { !draft.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !images.isEmpty }
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
                LazyVStack(alignment: .leading, spacing: 14) {
                    let entries = model.entries(for: bot)
                    let lastTalkID = entries.last(where: { $0.kind != .activity })?.id
                    if entries.isEmpty { emptyConversation }
                    ForEach(entries) { entry in
                        row(entry, lastTalkID: lastTalkID).equatable().id(entry.id)
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
            .onDisappear { scrollTask?.cancel(); dictation.stop() }

        }
        .background(Palette.background)
        .safeAreaInset(edge: .top, spacing: 0) { header }
        .safeAreaInset(edge: .bottom, spacing: 0) { composer }
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            remote.viewingBotID = bot.id
            if autoVoiceBotID == bot.id.uuidString { autoVoiceBotID = ""; startVoice() }
        }
        .onChange(of: composing) { _, focused in clipboardHasImage = focused && UIPasteboard.general.hasImages }
        .onReceive(NotificationCenter.default.publisher(for: UIPasteboard.changedNotification)) { _ in clipboardHasImage = composing && UIPasteboard.general.hasImages }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in clipboardHasImage = composing && UIPasteboard.general.hasImages }
        .onDisappear { if remote.viewingBotID == bot.id { remote.viewingBotID = nil } }
        .photosPicker(isPresented: $showPhotos, selection: $photoItems, maxSelectionCount: RemoteAttachment.maxCount, matching: .images)
        .onChange(of: photoItems) { _, items in
            guard !items.isEmpty else { return }
            Task {
                for item in items { if let data = try? await item.loadTransferable(type: Data.self) { addImage(ImageAttachments.make(from: data)) } }
                photoItems = []
            }
        }
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
                            .overlay {
                                if remote.running.contains(bot.id) {
                                    Circle().stroke(Palette.working, lineWidth: 2).padding(-3)
                                }
                            }
                        VStack(alignment: .leading, spacing: 0) {
                            Text(bot.name).font(.headline).lineLimit(1)
                            if remote.running.contains(bot.id) {
                                Text(remote.approval != nil ? "Needs your OK" : "Thinking it through…").font(.caption2)
                                    .foregroundStyle(remote.approval != nil ? Palette.attention : Color.secondary)
                            }
                        }
                    }.padding(.horizontal, 14).padding(.vertical, 8).frame(minHeight: 46).glassChrome(in: Capsule())
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
            if !images.isEmpty {
                ImageChips(images: images, tint: composerTint) { index in
                    var list = images; if list.indices.contains(index) { list.remove(at: index) }
                    remote.draftImages[bot.id] = list
                }
            }
            if clipboardHasImage && images.count < RemoteAttachment.maxCount {
                Button {
                    clipboardHasImage = false
                    if let image = UIPasteboard.general.image { addImage(ImageAttachments.make(from: image)) }
                } label: {
                    Label("Paste image from clipboard", systemImage: "doc.on.clipboard")
                        .font(.footnote.weight(.semibold)).foregroundStyle(composerInk)
                        .padding(.horizontal, 14).padding(.vertical, 8).background(composerTint, in: Capsule())
                }.buttonStyle(.plain).transition(.opacity).accessibilityHint("Attaches the copied image to your message")
            }
            if let attachNotice {
                Text(attachNotice).font(.footnote).foregroundStyle(.secondary).padding(.horizontal, 12)
            }
            if let note = dictation.note {
                Text(note).font(.footnote).foregroundStyle(.secondary).padding(.horizontal, 12).onTapGesture { dictation.note = nil }
            }
            HStack(alignment: .bottom, spacing: 10) {
                Menu {
                    Button("Paste text", systemImage: "doc.on.clipboard") {
                        if let text = UIPasteboard.general.string, !text.isEmpty {
                            draft.wrappedValue += (draft.wrappedValue.isEmpty ? "" : "\n") + text
                        }
                    }
                    Button("Photo library", systemImage: "photo.on.rectangle") { showPhotos = true }
                    Button("Paste image", systemImage: "photo.on.clipboard") {
                        guard UIPasteboard.general.hasImages, let image = UIPasteboard.general.image else { attachNotice = "There’s no image on the clipboard."; return }
                        addImage(ImageAttachments.make(from: image))
                    }.disabled(!UIPasteboard.general.hasImages)
                    Button("Voice mode", systemImage: "waveform") { startVoice() }
                    Button("Bot details", systemImage: "info.circle") { info = true }
                } label: {
                    Image(systemName: "plus").font(.system(size: 24, weight: .regular))
                        .foregroundStyle(.secondary).frame(width: 34, height: 44)
                        .contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityLabel("Message options")
                TextField("Ask \(bot.name)", text: draft, axis: .vertical)
                    .font(.system(size: 16)).lineLimit(1...6).focused($composing).padding(.vertical, 5).frame(minHeight: 44)
                    .accessibilityIdentifier("remote-chat-input")
                if remote.running.contains(bot.id) {
                    Button {
                        Task { await remote.command(RemoteCommand(action: "stop", botID: bot.id)) }
                    } label: {
                        Image(systemName: "stop.fill").font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(composerInk).frame(width: 36, height: 36)
                            .background(composerTint, in: Circle())
                            .frame(width: 44, height: 44).contentShape(Rectangle())
                    }.buttonStyle(.plain).disabled(!remote.online).accessibilityLabel("Stop response")
                } else if !hasContent && !sending {
                    Button { dictation.toggle(current: draft.wrappedValue) { draft.wrappedValue = $0 } } label: {
                        Image(systemName: dictation.listening ? "mic.fill" : "mic").font(.system(size: 19, weight: .regular))
                            .foregroundStyle(dictation.listening ? Color.red : Color.secondary).frame(width: 34, height: 44).contentShape(Rectangle())
                    }.buttonStyle(.plain).accessibilityLabel(dictation.listening ? "Stop dictation" : "Dictate a message")
                    Button { dictation.stop(); startVoice() } label: {
                        Image(systemName: "waveform").font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(composerInk).frame(width: 36, height: 36)
                            .background(composerTint, in: Circle())
                            .frame(width: 44, height: 44).contentShape(Rectangle())
                    }.buttonStyle(.plain).disabled(!remote.online).accessibilityLabel("Start voice mode")
                } else {
                    Button { send() } label: {
                        ZStack {
                            Circle().fill(composerTint.opacity(canSend || sending ? 1 : 0.22))
                                .frame(width: 36, height: 36)
                            if sending {
                                ProgressView().controlSize(.small).tint(composerInk)
                            } else {
                                Image(systemName: "arrow.up").font(.system(size: 19, weight: .semibold))
                                    .foregroundStyle(canSend ? composerInk : Color.secondary)
                            }
                        }.frame(width: 44, height: 44).contentShape(Rectangle())
                    }.buttonStyle(.plain).disabled(!canSend).accessibilityLabel(sending ? "Sending message" : "Send message")
                }
            }
            .padding(5)
            .background {
                RoundedRectangle(cornerRadius: 28).fill(.clear)
                    .glassChrome(in: RoundedRectangle(cornerRadius: 28), interactive: false)
                    .allowsHitTesting(false)
            }
            .shadow(color: .black.opacity(0.035), radius: 14, y: 4)
        }.padding(.horizontal, 18).padding(.top, 8).padding(.bottom, 4)
    }

    private func row(_ entry: Entry, lastTalkID: UUID?) -> MessageRow {
        let answerable = lastTalkID == entry.id && entry.kind == .bot && entry.state != .streaming && !remote.running.contains(bot.id) && remote.online
        let sender: Bot? = entry.senderBotID.flatMap { id in model.workspace.bots.first { $0.id == id } }
        return MessageRow(entry: entry, canRetry: canRetryMessage(entry), online: remote.online, canAnswer: answerable,
                          sender: sender, botName: bot.name, isGroup: bot.memberIDs != nil, actions: messageActions(for: entry))
    }

    private func canRetryMessage(_ entry: Entry) -> Bool { model.entries(for: bot).last?.id == entry.id && !remote.running.contains(bot.id) }

    private func messageActions(for entry: Entry) -> MessageActions {
        let current = bot
        return MessageActions(
            reply: {
                let quoted = entry.text.split(separator: "\n", omittingEmptySubsequences: true).prefix(3).map { "> " + String($0.prefix(240)) }.joined(separator: "\n")
                draft.wrappedValue = quoted + "\n\n" + draft.wrappedValue
                composing = true
            },
            react: { emoji in Task { _ = await remote.command(RemoteCommand(action: "react", botID: current.id, text: emoji ?? "", taskID: entry.id)) } },
            retry: { Task { _ = await remote.command(RemoteCommand(action: "retry", botID: current.id)) } },
            delete: { Task { _ = await remote.command(RemoteCommand(action: "delete_entry", botID: current.id, taskID: entry.id)) } },
            answer: { text in Task { _ = await remote.send(text, bot: current) } },
            other: { composing = true })
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

    private func addImage(_ attachment: RemoteAttachment?) {
        guard let attachment else { attachNotice = "That image couldn’t be prepared."; return }
        var list = images
        guard list.count < RemoteAttachment.maxCount, (list + [attachment]).reduce(0, { $0 + $1.data.count }) <= RemoteAttachment.maxTotalBytes else {
            attachNotice = "Attach up to \(RemoteAttachment.maxCount) images per message."; return
        }
        list.append(attachment); remote.draftImages[bot.id] = list; attachNotice = nil
    }

    /// Voice mode lives at the app's root (PhoneVoiceHub), so it keeps going when you open another Bot.
    private func startVoice() { voiceHub.start(bot: bot, model: model, remote: remote) }

    private func send() {
        dictation.stop()
        let typed = draft.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let sentImages = images
        let text = typed.isEmpty && !sentImages.isEmpty ? "Please look at the attached image\(sentImages.count == 1 ? "" : "s")." : typed
        guard canSend else { return }; sending = true; nearBottom = true; attachNotice = nil
        Task {
            if await remote.send(text, bot: bot, images: sentImages) {
                if draft.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines) == typed { draft.wrappedValue = "" }
                if remote.draftImages[bot.id] == sentImages { remote.draftImages[bot.id] = [] }
            } else if !sentImages.isEmpty, remote.error == nil {
                attachNotice = "The image couldn’t be sent. Update the Mac or Windows app to this version and try again."
            }
            sending = false
        }
    }
}

private struct ChatScrollMetrics: Equatable {
    var height: CGFloat
    var viewport: CGFloat
    var bottom: CGFloat
}

/// What the long-press menu on a message can do. These closures are never compared: the row's equality uses only plain values.
private struct MessageActions: @unchecked Sendable {
    var reply: () -> Void = {}
    var react: (String?) -> Void = { _ in }
    var retry: () -> Void = {}
    var delete: () -> Void = {}
    var answer: (String) -> Void = { _ in }
    var other: () -> Void = {}
}

private struct MessageRow: View, Equatable {
    let entry: Entry
    let canRetry: Bool
    let online: Bool
    let canAnswer: Bool
    let sender: Bot?
    let botName: String
    let isGroup: Bool
    let actions: MessageActions
    nonisolated static func == (lhs: MessageRow, rhs: MessageRow) -> Bool {
        lhs.entry == rhs.entry && lhs.canRetry == rhs.canRetry && lhs.online == rhs.online && lhs.canAnswer == rhs.canAnswer
            && lhs.sender == rhs.sender && lhs.botName == rhs.botName && lhs.isGroup == rhs.isGroup
    }
    private func formatted(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(text)
    }
    @ViewBuilder private var senderAvatar: some View {
        if let sender { BotAvatar(color: sender.color, size: 26, appearance: sender.appearance) }
        else { Image(systemName: "person.crop.circle.fill").font(.system(size: 24)).foregroundStyle(.tertiary).frame(width: 26, height: 26) }
    }
    var body: some View {
        if entry.kind == .activity, entry.senderBotID != nil, entry.text.hasPrefix("Message from ") {
            botToBot
        } else if entry.kind == .activity || entry.delivery == "scheduled" {
            ActivityPill(text: entry.text, routine: entry.delivery == "scheduled")
        } else {
            bubbleRow
        }
    }

    /// Another Bot asking this Bot something: the sender's face, an arrow to this Bot, and a dashed bubble.
    private var botToBot: some View {
        let parts = entry.text.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
        let message = parts.count > 1 ? String(parts[1]) : entry.text
        let from = entry.senderName ?? "Another Bot"
        return HStack(alignment: .top, spacing: 8) {
            senderAvatar.padding(.top, 20)
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 4) {
                    Text(from).fontWeight(.semibold)
                    Image(systemName: "arrow.right").font(.caption2.weight(.bold)).foregroundStyle(.tertiary)
                    Text(botName)
                }.font(.caption).foregroundStyle(.secondary).padding(.leading, 4)
                Text(formatted(message)).font(.system(size: 16)).lineSpacing(4).textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 15).padding(.vertical, 11)
                    .background(Palette.card.opacity(0.5), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Color.secondary.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
            }
            Spacer(minLength: 30)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Message from \(from) to \(botName): \(message)")
    }

    private var bubbleRow: some View {
        let choice: (text: String, prompt: ChoicePrompt?) = entry.kind == .bot ? ChoicePrompt.split(entry.text) : (entry.text, nil)
        let follow: (text: String, suggestions: [String]) = entry.kind == .bot ? FollowUps.split(choice.text) : (choice.text, [])
        let split: (text: String, prompt: ChoicePrompt?) = (follow.text, choice.prompt)
        let fromOtherBot = entry.kind == .bot && entry.senderBotID != nil
        let isUser = entry.kind == .user
        return HStack(alignment: .top, spacing: 8) {
            if isUser { Spacer(minLength: 48) }
            if fromOtherBot { senderAvatar.padding(.top, 20) }
            VStack(alignment: isUser ? .trailing : .leading, spacing: 6) {
                if fromOtherBot {
                    Text(isGroup ? (entry.senderName ?? "Bot") : "\(entry.senderName ?? "Another Bot") replied")
                        .font(.caption.weight(.semibold)).foregroundStyle(.secondary).padding(.leading, 4)
                }
                if entry.text.isEmpty, entry.state == .streaming {
                    HStack(spacing: 10) {
                        TypingDots().padding(.horizontal, 16).padding(.vertical, 14)
                            .background(Palette.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                        Text("Thinking it through").font(.footnote).foregroundStyle(.secondary)
                    }
                } else if !split.text.isEmpty {
                    bubble(split.text)
                }
                if let prompt = split.prompt {
                    QuestionCard(prompt: prompt, canAnswer: canAnswer, answer: { actions.answer($0) }, other: { actions.other() })
                } else if canAnswer, !follow.suggestions.isEmpty {
                    // Tap-to-send follow-ups under the latest reply (0.9.5).
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(follow.suggestions, id: \.self) { suggestion in
                                Button { actions.answer(suggestion) } label: {
                                    Label(suggestion, systemImage: "arrow.up.right").labelStyle(.titleAndIcon).font(.subheadline)
                                        .padding(.horizontal, 12).padding(.vertical, 8).background(Palette.card, in: Capsule())
                                }.buttonStyle(.plain)
                            }
                        }
                    }
                }
                if entry.state == .failed {
                    Label(entry.provider.map { "Couldn’t finish · \($0)" } ?? "Couldn’t finish", systemImage: "exclamationmark.circle")
                        .font(.caption).foregroundStyle(Color.red.opacity(0.85)).padding(.horizontal, 6)
                }
            }
            if !isUser { Spacer(minLength: 30) }
        }
    }

    private func bubble(_ text: String) -> some View {
        Text(formatted(text)).font(.system(size: 16)).lineSpacing(4).textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 15).padding(.vertical, 11)
            .background(entry.kind == .user ? Palette.userBubble : Palette.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(alignment: entry.kind == .user ? .bottomLeading : .bottomTrailing) {
                if let reaction = entry.reaction, !reaction.isEmpty {
                    Text(reaction).font(.system(size: 14)).padding(.horizontal, 7).padding(.vertical, 3)
                        .background(Palette.background, in: Capsule()).overlay(Capsule().stroke(.primary.opacity(0.1)))
                        .offset(y: 12).accessibilityLabel("Reaction \(reaction)")
                }
            }
            .padding(.bottom, entry.reaction?.isEmpty == false ? 12 : 0)
            .contextMenu {
                Button("Copy text", systemImage: "doc.on.doc") { UIPasteboard.general.string = entry.text }
                Button("Copy as Markdown", systemImage: "doc.richtext") { UIPasteboard.general.string = (entry.kind == .user ? "**You:** " : "") + entry.text }
                Button("Reply", systemImage: "arrowshape.turn.up.left") { actions.reply() }
                Menu("React", systemImage: "face.smiling") {
                    ForEach(["👍", "👎", "❤️", "😂", "🎉", "🤔"], id: \.self) { emoji in
                        Button(entry.reaction == emoji ? "\(emoji)  Remove" : emoji) { actions.react(entry.reaction == emoji ? nil : emoji) }
                    }
                }.disabled(!online)
                if entry.kind == .bot, canRetry { Button("Retry", systemImage: "arrow.clockwise") { actions.retry() }.disabled(!online) }
                if entry.kind == .bot, let provider = entry.provider { Text("Answered by \(provider)") }
                ShareLink(item: entry.text) { Label("Share text", systemImage: "square.and.arrow.up") }
                if entry.state != .streaming { Button("Delete message", systemImage: "trash", role: .destructive) { actions.delete() }.disabled(!online) }
            }
    }
}

/// Dictation for the message box: tap the mic, talk, tap again. Uses Apple's on-device recognition when available, so nothing leaves the phone.
@MainActor
final class PhoneDictation: ObservableObject {
    @Published private(set) var listening = false
    @Published var note: String?
    private let engine = AVAudioEngine()
    private var task: SFSpeechRecognitionTask?
    private var generation = 0
    private var base = ""
    private var deliver: ((String) -> Void)?

    func toggle(current: String, set: @escaping (String) -> Void) {
        if listening { stop(); return }
        note = nil
        Task { await begin(current: current, set: set) }
    }

    private func begin(current: String, set: @escaping (String) -> Void) async {
        guard await VoiceSession.requestAccess(needsSpeech: true) else {
            note = "Allow Microphone and Speech Recognition for OpenGrokBot in Settings → OpenGrokBot, then try again."
            return
        }
        guard let recognizer = SFSpeechRecognizer(locale: VoiceSettings.locale) ?? SFSpeechRecognizer(locale: Locale(identifier: "en-US")), recognizer.isAvailable else {
            note = "Speech recognition isn't available for this language right now."
            return
        }
        do {
            let audio = AVAudioSession.sharedInstance()
            try audio.setCategory(.record, mode: .measurement, options: .duckOthers)
            try audio.setActive(true, options: .notifyOthersOnDeactivation)
        } catch { note = "The microphone is busy. Try again."; return }
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.addsPunctuation = true
        if recognizer.supportsOnDeviceRecognition { request.requiresOnDeviceRecognition = true }
        base = current.trimmingCharacters(in: .whitespacesAndNewlines)
        deliver = set
        generation += 1
        let mine = generation
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0 else { note = "No microphone was found."; return }
        input.removeTap(onBus: 0)
        Self.installTap(on: input, format: format, request: request)
        task = recognizer.recognitionTask(with: request, resultHandler: Self.handler { [weak self] text, done in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.heard(text, done: done, generation: mine) } }
        })
        engine.prepare()
        do { try engine.start(); listening = true } catch {
            note = "Couldn't start the microphone: \(error.localizedDescription)"
            teardown()
        }
    }

    nonisolated private static func installTap(on input: AVAudioInputNode, format: AVAudioFormat, request: SFSpeechAudioBufferRecognitionRequest) {
        let box = DictationRequestBox(request)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in box.request.append(buffer) }
    }

    nonisolated private static func handler(deliver: @escaping @Sendable (String, Bool) -> Void) -> (SFSpeechRecognitionResult?, Error?) -> Void {
        { result, error in deliver(result?.bestTranscription.formattedString ?? "", (result?.isFinal ?? false) || error != nil) }
    }

    private func heard(_ text: String, done: Bool, generation current: Int) {
        guard current == generation else { return }
        if !text.isEmpty { deliver?(base.isEmpty ? text : base + " " + text) }
        if done { stop() }
    }

    func stop() {
        guard listening || task != nil else { return }
        generation += 1
        task?.finish()
        teardown()
    }

    private func teardown() {
        if engine.isRunning { engine.stop() }
        engine.inputNode.removeTap(onBus: 0)
        task = nil; deliver = nil; listening = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}

private final class DictationRequestBox: @unchecked Sendable {
    let request: SFSpeechAudioBufferRecognitionRequest
    init(_ request: SFSpeechAudioBufferRecognitionRequest) { self.request = request }
}

/// Voice mode belongs to the app, not one chat (0.9.3): it keeps listening and speaking while you open other Bots,
/// and shows as a card, full screen, or a small pill. The computer that runs the Bot is told voice mode is on,
/// so replies come back short, spoken-style and from a quick model.
@MainActor
final class PhoneVoiceHub: ObservableObject {
    let conversation = VoiceConversation()
    @Published private(set) var botID: UUID?
    @Published var layout: VoiceLayout = VoiceSettings.layout
    private weak var remote: RemoteController?

    func start(bot: Bot, model: AppModel, remote: RemoteController) {
        if botID == bot.id { if layout == .mini { layout = VoiceSettings.layout }; return }
        if botID != nil { stop() }
        self.remote = remote
        botID = bot.id; layout = VoiceSettings.layout
        let current = bot
        Task { _ = await remote.command(RemoteCommand(action: "voice_mode", botID: current.id, text: "on")) }
        Task {
            await conversation.start(
                botVoice: current.voice,
                send: { text in await remote.send(text, bot: current) },
                latestReply: {
                    guard let entry = model.entries(for: current).last(where: { $0.kind == .bot }) else { return nil }
                    let finished = entry.state != .streaming && !remote.running.contains(current.id)
                    return VoiceReply(id: entry.id, text: entry.text, finished: finished)
                },
                stopReply: { Task { _ = await remote.command(RemoteCommand(action: "stop", botID: current.id)) } },
                activity: { model.entries(for: current).suffix(12).filter { $0.kind == .activity }.map { VoiceStep(id: $0.id, text: $0.text, date: $0.date) } },
                vocabulary: model.workspace.bots.map(\.name))
        }
    }

    func stop() {
        guard let id = botID else { return }
        conversation.stop()
        botID = nil
        if let remote { Task { _ = await remote.command(RemoteCommand(action: "voice_mode", botID: id, text: "off")) } }
    }
}
