import AppKit
import SwiftUI

struct MacConversationView: View {
    let bot: Bot
    @EnvironmentObject private var app: AppModel
    @EnvironmentObject private var desktop: MacAppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("spellChecking") private var spellChecking = true
    @FocusState private var composing: Bool
    @State private var followLatest = true
    @State private var showActions = false
    @State private var voiceOn = false
    @StateObject private var voice = VoiceConversation()
    @StateObject private var dictation = MacDictation()
    @ObservedObject private var approval = MacApproval.shared
    @State private var pasteMonitor: Any?
    @State private var scrollTask: Task<Void,Never>?

    private var avatarColor: String { bot.appearance?.color ?? bot.color }
    @AppStorage("accentStyle") private var accentStyle = "bot"
    private var tint: Color { accentStyle == "neutral" || (bot.appearance == nil && bot.color == "white") ? .primary : AvatarArtwork.color(avatarColor) }
    private var ink: Color {
        if bot.appearance == nil && bot.color == "white" { return MacTheme.canvas }
        return ["white", "amber", "orange", "green", "teal", "gray"].contains(avatarColor) ? .black : .white
    }

    private var draft: Binding<String> {
        Binding(get: { desktop.drafts[bot.id] ?? "" }, set: { desktop.drafts[bot.id] = $0 })
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 12) {
                        let messages = app.entries(for: bot)
                        let lastBotID = messages.last(where: { $0.kind == .bot })?.id
                        let lastUserID = messages.last(where: { $0.kind == .user && $0.delivery != "scheduled" })?.id
                        // A question card can be answered while nothing has been said after it.
                        let lastTalkID = messages.last(where: { $0.kind != .activity })?.id
                        let bots = app.workspace.bots
                        ForEach(messages) { entry in
                            // Equatable rows: a streaming reply redraws only the message that changed, not every message in the chat.
                            row(entry, lastBotID: lastBotID, lastUserID: lastUserID, lastTalkID: lastTalkID, bots: bots).equatable().id(entry.id)
                        }
                        if messages.isEmpty { emptyConversation.padding(.top, 120) }
                        Color.clear.frame(height: 1).id("bottom")
                    }
                    .padding(.horizontal, 24).padding(.top, 80).padding(.bottom, 20)
                    .frame(maxWidth: 780).frame(maxWidth: .infinity)
                    .background(ChatScrollMonitor(onUserScroll: { nearBottom in followLatest = nearBottom },
                        onLayout: { if followLatest { scrollToLatest(proxy) } }))
                }
                .task(id: bot.id) { followLatest = true; scrollToLatest(proxy) }
                .onChange(of: app.entries(for: bot).last) { _, _ in
                    if followLatest { scrollToLatest(proxy) }
                }
                .onDisappear { scrollTask?.cancel() }

            }
            composer
        }
        .overlay(alignment: .top) {
            Button {
                if desktop.gateway != nil { desktop.sendFeedback[bot.id] = "Bot details aren’t available while viewing another computer yet. Provider and model are in the header menu, and its settings are under “You”."; return }
                desktop.showBotInspector.toggle()
            } label: {
                HStack(spacing: 10) {
                    MacBotAvatar(color: bot.color, size: 26, appearance: bot.appearance, status: headerStatus)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(bot.name).font(.system(size: 15, weight: .semibold)).lineLimit(1)
                        if let line = headerLine {
                            Text(line).font(.system(size: 11)).foregroundStyle(headerStatus == .attention ? MacTheme.attention : MacTheme.secondary).lineLimit(1)
                                .transition(.opacity)
                        }
                    }
                    Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold)).foregroundStyle(MacTheme.tertiary)
                        .rotationEffect(.degrees(desktop.showBotInspector ? 180 : 0))
                }
                .animation(.easeOut(duration: 0.15), value: headerLine)
                .padding(.leading, 9).padding(.trailing, 14).padding(.vertical, 7).frame(minHeight: 42)
                .contentShape(Capsule()).glassChrome(in: Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("bot-details-toggle")
            .accessibilityLabel("Bot details for \(bot.name)")
            .accessibilityValue(desktop.showBotInspector ? "Expanded" : "Collapsed")
            .help(desktop.showBotInspector ? "Close bot details" : "Open bot details")
            .padding(.top, 12)
        }
        .overlay(alignment: .topTrailing) { MacModelMenu(bot: bot).padding(.top, 14).padding(.trailing, 18) }
        .background(MacTheme.canvas)
        .overlay { if voiceOn { VoiceModeView(conversation: voice, botName: bot.name, tint: tint, ink: ink) { stopVoice() }.transition(.opacity) } }
        .onChange(of: bot.id) { _, _ in stopVoice() }
        .onDisappear { stopVoice() }
        .dropDestination(for: URL.self) { urls, _ in
            guard urls.allSatisfy(\.isFileURL), bot.memberIDs == nil else { return false }
            desktop.importAttachments(urls, for: bot); return true
        }
    }

    private func row(_ entry: Entry, lastBotID: UUID?, lastUserID: UUID?, lastTalkID: UUID?, bots: [Bot]) -> MacMessageRow {
        let running = desktop.runningBots.contains(bot.id)
        let answerable = lastTalkID == entry.id && entry.kind == .bot && entry.state != .streaming && !running
        let sender: Bot? = entry.senderBotID.flatMap { id in bots.first { $0.id == id } }
        return MacMessageRow(entry: entry, canReact: desktop.gateway == nil, isLastBot: lastBotID == entry.id,
                             isLastUser: lastUserID == entry.id, canAnswer: answerable, sender: sender,
                             botName: bot.name, isGroup: bot.memberIDs != nil, actions: messageActions)
    }

    /// The avatar ring in the header: working while a reply runs, orange while this Bot waits for your OK.
    private var headerStatus: MacBotStatus {
        if approval.isWaiting(on: bot.name) { return .attention }
        return desktop.runningBots.contains(bot.id) ? .working : .idle
    }
    private var headerLine: String? {
        switch headerStatus {
        case .attention: return "Needs your OK"
        case .working: return "Thinking it through…"
        case .idle:
            guard let members = bot.memberIDs else { return nil }
            return "\(members.count) Bots"
        }
    }

    private var composer: some View {
        VStack(spacing: 8) {
            if let request = approval.pending {
                MacApprovalCard(request: request, bot: app.workspace.bots.first { request.title.hasPrefix("Let \($0.name) ") }) { allowed in
                    approval.answer(id: request.id, approved: allowed)
                }
                .frame(maxWidth: 740)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            if let recovery = desktop.recoverableDrafts[bot.id]?.first {
                HStack {
                    Text("An interrupted or failed message is available to restore. Check the chat before resending.").font(.caption)
                    Button("Restore draft") {
                        let current = draft.wrappedValue
                        draft.wrappedValue = [current, recovery.text].filter { !$0.isEmpty }.joined(separator: "\n\n")
                        var files = desktop.attachments[bot.id] ?? []
                        for file in recovery.files where !files.contains(file) { files.append(file) }
                        desktop.attachments[bot.id] = files; desktop.recoverableDrafts[bot.id]?.removeFirst(); desktop.flushDrafts()
                    }
                }
            }
            if desktop.importingAttachments.contains(bot.id) { ProgressView("Copying files…").controlSize(.small) }
            if let files = desktop.attachments[bot.id], !files.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(files, id: \.self) { file in
                            HStack(spacing: 6) {
                                Image(systemName: file.lowercased().hasSuffix(".png") || file.lowercased().hasSuffix(".jpg") || file.lowercased().hasSuffix(".jpeg") ? "photo" : "doc")
                                    .foregroundStyle(MacTheme.secondary)
                                Text(String(file.dropFirst(min(file.count, 37)))).lineLimit(1)
                                Button { desktop.attachments[bot.id]?.removeAll { $0 == file } } label: {
                                    Image(systemName: "xmark.circle.fill").foregroundStyle(MacTheme.secondary)
                                }.buttonStyle(.plain).accessibilityLabel("Remove attachment")
                            }
                            .padding(.vertical, 6).padding(.leading, 10).padding(.trailing, 8)
                            .background(tint.opacity(0.2), in: Capsule())
                        }
                    }.padding(.horizontal, 4)
                }.font(.caption)
            }
            MacBrowserPill(botID: bot.id)
            MacTeachBar(bot: bot, teach: desktop.teach)
            HStack(alignment: .bottom, spacing: 11) {
                Button { showActions.toggle() } label: {
                    Image(systemName: "plus").font(.system(size: 18, weight: .regular))
                        .foregroundStyle(MacTheme.secondary)
                        .frame(width: 30, height: 36)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain).help("Attach or export").accessibilityLabel("Attach or export")
                .popover(isPresented: $showActions) { actionsMenu }
                TextField("Message \(bot.name)", text: draft, axis: .vertical)
                    .textFieldStyle(.plain).font(.system(size: 16)).lineLimit(1...7)
                    .disableAutocorrection(!spellChecking).focused($composing)
                    .padding(.vertical, 6).frame(minHeight: 36)
                    .onKeyPress(keys: [.return], phases: .down) { press in
                        if let editor = NSApp.keyWindow?.firstResponder as? NSTextView, editor.hasMarkedText() { return .ignored }
                        if press.modifiers.contains(.shift) {
                            if let editor = NSApp.keyWindow?.firstResponder as? NSTextView {
                                editor.insertText("\n", replacementRange: editor.selectedRange())
                            } else { draft.wrappedValue += "\n" }
                            return .handled
                        }
                        sendMessage(); return .handled
                    }
                    .onExitCommand { if desktop.panel != nil { desktop.panel = nil } else { desktop.showBotInspector = false } }
                    .accessibilityIdentifier("chat-input").accessibilityLabel("Message for \(bot.name)")
                Button { dictation.toggle(current: draft.wrappedValue) { draft.wrappedValue = $0 } } label: {
                    Image(systemName: dictation.listening ? "mic.fill" : "mic").font(.system(size: 17, weight: .regular))
                        .foregroundStyle(dictation.listening ? Color.red : MacTheme.secondary)
                        .frame(width: 30, height: 36).contentShape(Rectangle())
                }
                .buttonStyle(.plain).help(dictation.listening ? "Stop dictation" : "Dictate a message").accessibilityLabel(dictation.listening ? "Stop dictation" : "Dictate a message")
                .popover(isPresented: Binding(get: { dictation.note != nil }, set: { if !$0 { dictation.note = nil } })) {
                    Text(dictation.note ?? "").font(.callout).padding(14).frame(width: 280)
                }
                if desktop.runningBots.contains(bot.id) {
                    Button { desktop.stop(botID: bot.id) } label: { Image(systemName: "stop.fill").foregroundStyle(ink).frame(width: 36, height: 36).background(tint, in: Circle()) }.buttonStyle(.plain).help("Stop response")
                } else if !draft.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !(desktop.attachments[bot.id] ?? []).isEmpty {
                    Button { sendMessage() } label: {
                        Image(systemName: "arrow.up").font(.system(size: 18, weight: .semibold)).foregroundStyle(ink)
                            .frame(width: 36, height: 36).background(tint, in: Circle())
                    }.buttonStyle(.plain).disabled(desktop.needsProvider(bot))
                        .help("Send message").accessibilityLabel("Send message")
                } else {
                    Button { startVoice() } label: {
                        Image(systemName: "waveform").font(.system(size: 17, weight: .semibold)).foregroundStyle(ink)
                            .frame(width: 36, height: 36).background(tint, in: Circle())
                    }.buttonStyle(.plain).help("Start voice mode").accessibilityLabel("Start voice mode")
                }
            }
            .padding(.leading, 10).padding(.trailing, 8).padding(.vertical, 6).frame(minHeight: 52)
            .background { RoundedRectangle(cornerRadius: 26, style: .continuous).fill(MacTheme.panel.opacity(0.55)).glassChrome(in: RoundedRectangle(cornerRadius: 26, style: .continuous), interactive: false).allowsHitTesting(false) }
            .frame(maxWidth: 780)
            .onAppear { installPasteMonitor() }
            .onChange(of: bot.id) { _, _ in installPasteMonitor(); dictation.stop() }
            .onDisappear { removePasteMonitor(); dictation.stop() }
            // Quiet by default: the model is in the header menu. This line only appears when something needs doing.
            if desktop.scanningCLIs || desktop.needsProvider(bot) || desktop.runningBots.contains(bot.id) {
                HStack(spacing: 8) {
                    if desktop.scanningCLIs { ProgressView().controlSize(.mini) }
                    if desktop.needsProvider(bot) {
                        Button("Choose a provider") { desktop.showBotInspector = true }.buttonStyle(.link)
                    }
                    Spacer()
                    if desktop.runningBots.contains(bot.id) {
                        Text(approval.isWaiting(on: bot.name) ? "Waiting for your OK" : "Thinking it through…")
                        Button("Stop") { desktop.stop(botID: bot.id) }.buttonStyle(.link)
                    }
                }
                .font(.system(size: 11)).foregroundStyle(MacTheme.secondary).frame(maxWidth: 760)
            }
            if let feedback = desktop.sendFeedback[bot.id] {
                HStack { Text(feedback).font(.caption); Button("AI CLI setup") { desktop.panel = .setup } }.foregroundStyle(.secondary)
            }
            if let error = desktop.runErrors[bot.id] {
                HStack {
                    if app.entries(for: bot).last(where: { $0.kind == .bot })?.text != error { Text(error).font(.system(size: 11)) }
                    Spacer()
                    Button("Copy diagnostics") {
                        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
                        let provider = desktop.providersToRun(for: bot).first?.cli.provider.name ?? "not configured"
                        let info = "OpenGrokBot \(version)\nProvider: \(provider)\nStatus: last response failed\nBot ID: \(bot.id.uuidString)"
                        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(info, forType: .string)
                    }.help("Copy version, provider and run status without chat text or credentials")
                    Button("AI CLI setup") { desktop.panel = .setup }
                    Button("Retry") { desktop.retry(bot: bot, app: app) }
                }.foregroundStyle(MacTheme.secondary)
            }
        }
        .padding(.horizontal, 20).padding(.bottom, 14).padding(.top, 6)
        .animation(.spring(response: 0.3, dampingFraction: 1), value: approval.pending)
    }

    private var emptyConversation: some View {
        VStack(spacing: 14) {
            MacBotAvatar(color: bot.color, size: 72, appearance: bot.appearance)
                .padding(.bottom, 6)
            Text(bot.name).font(.system(size: 26, weight: .semibold))
            Text(bot.purpose).font(.system(size: 14)).foregroundStyle(MacTheme.secondary)
                .multilineTextAlignment(.center).frame(maxWidth: 420)
            Text("Say hi to get started.")
                .font(.system(size: 13)).foregroundStyle(MacTheme.tertiary)
        }.frame(maxWidth: .infinity)
    }

    private func scrollToLatest(_ proxy: ScrollViewProxy) {
        scrollTask?.cancel()
        scrollTask = Task { @MainActor in
            await Task.yield()
            guard !Task.isCancelled, followLatest else { return }
            var transaction = Transaction(); transaction.disablesAnimations = true
            withTransaction(transaction) { proxy.scrollTo("bottom", anchor: .bottom) }
        }
    }

    private func startVoice() {
        withAnimation { voiceOn = true }
        let current = bot, model = desktop, workspace = app
        Task {
            await voice.start(
                botVoice: current.voice,
                send: { text in model.send(text, to: current, app: workspace) },
                latestReply: {
                    guard let entry = workspace.entries(for: current).last(where: { $0.kind == .bot }) else { return nil }
                    let finished = entry.state != .streaming && !model.runningBots.contains(current.id)
                    return VoiceReply(id: entry.id, text: entry.text, finished: finished)
                },
                stopReply: { model.stop(botID: current.id) })
        }
    }

    private func stopVoice() {
        guard voiceOn || voice.isRunning else { return }
        voice.stop()
        withAnimation { voiceOn = false }
    }

    private var attachDisabled: Bool { bot.memberIDs != nil || desktop.gateway != nil || desktop.importingAttachments.contains(bot.id) }

    private var actionsMenu: some View {
        VStack(alignment: .leading, spacing: 2) {
            ComposerActionRow(title: "Attach files", icon: "paperclip", disabled: attachDisabled, tint: tint) {
                showActions = false
                DispatchQueue.main.async { desktop.chooseAttachments(for: bot) }
            }
            ComposerActionRow(title: "Paste image", icon: "photo.on.clipboard", disabled: attachDisabled, tint: tint) {
                showActions = false
                desktop.pasteAttachments(from: .general, for: bot)
            }
            if desktop.gateway == nil, bot.memberIDs == nil {
                ComposerActionRow(title: desktop.teach.recording ? "Recording…" : "Teach a task", icon: "record.circle", disabled: desktop.teach.recording, tint: .red) {
                    showActions = false
                    desktop.teach.start(for: bot.id)
                }
            }
            Divider().padding(.vertical, 4)
            ComposerActionRow(title: "Export conversation…", icon: "square.and.arrow.up", disabled: false, tint: tint) {
                showActions = false
                DispatchQueue.main.async { desktop.exportConversation(bot, app: app) }
            }
        }
        .padding(8).frame(width: 220)
    }

    /// Lets ⌘V attach an image or file from the clipboard while the message box is focused.
    private func installPasteMonitor() {
        removePasteMonitor()
        let target = bot, model = desktop
        pasteMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
                  event.charactersIgnoringModifiers == "v",
                  target.memberIDs == nil,
                  let window = event.window, window.isKeyWindow,
                  window.firstResponder is NSTextView else { return event }
            let board = NSPasteboard.general
            let hasFile = board.canReadObject(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true])
            let hasImage = board.availableType(from: [.png, .tiff]) != nil && board.string(forType: .string) == nil
            guard hasFile || hasImage else { return event }
            return model.pasteAttachments(from: board, for: target) ? nil : event
        }
    }

    private func removePasteMonitor() {
        if let monitor = pasteMonitor { NSEvent.removeMonitor(monitor) }
        pasteMonitor = nil
    }

    private func reply(to entry: Entry) {
        let quote = String(entry.text.split(separator: "\n").prefix(3).joined(separator: " ").prefix(240))
        draft.wrappedValue = "> " + quote + "\n\n" + draft.wrappedValue
        composing = true
    }
    /// Reactions and deleting a message change this Mac's own chat only, so they are hidden while viewing another computer.
    private var messageActions: MacMessageActions {
        let model = app, desktopModel = desktop, current = bot
        return MacMessageActions(
            reply: { entry in reply(to: entry) },
            react: { entry, emoji in _ = model.setReaction(emoji, for: entry.id) },
            delete: { entry in _ = model.deleteEntry(entry.id) },
            retry: { _ in desktopModel.retry(bot: current, app: model) },
            answer: { text in _ = desktopModel.send(text, to: current, app: model) },
            other: { composing = true })
    }

    private func sendMessage() {
        dictation.stop()
        followLatest = true
        guard !desktop.importingAttachments.contains(bot.id) else { return }
        let files = desktop.attachments[bot.id] ?? []
        let base = draft.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !base.isEmpty || !files.isEmpty else { return }
        let message = MacAppModel.attachmentMessage(base: base, names: files)
        if desktop.send(message, to: bot, app: app) {
            desktop.outgoingDrafts[bot.id] = RecoverableDraft(text: draft.wrappedValue, files: files)
            draft.wrappedValue = ""; desktop.attachments[bot.id] = []; desktop.flushDrafts(); composing = true
        }
    }
}

/// What the hover buttons on a message do. Never compared: a row is redrawn only when its message or its flags change.
struct MacMessageActions: @unchecked Sendable {
    var reply: (Entry) -> Void = { _ in }
    var react: (Entry, String?) -> Void = { _, _ in }
    var delete: (Entry) -> Void = { _ in }
    var retry: (Entry) -> Void = { _ in }
    /// Sends the human's answer to a question card.
    var answer: (String) -> Void = { _ in }
    /// "Something else…" on a question card: puts the cursor in the message box.
    var other: () -> Void = {}
}

struct MacMessageRow: View, Equatable {
    let entry: Entry
    let canReact: Bool
    let isLastBot: Bool
    let isLastUser: Bool
    let canAnswer: Bool
    let sender: Bot?
    let botName: String
    let isGroup: Bool
    let actions: MacMessageActions
    nonisolated static func == (lhs: MacMessageRow, rhs: MacMessageRow) -> Bool {
        lhs.entry == rhs.entry && lhs.canReact == rhs.canReact && lhs.isLastBot == rhs.isLastBot && lhs.isLastUser == rhs.isLastUser
            && lhs.canAnswer == rhs.canAnswer && lhs.sender == rhs.sender && lhs.botName == rhs.botName && lhs.isGroup == rhs.isGroup
    }
    var body: some View {
        MacMessageView(entry: entry, onReply: actions.reply, onReact: canReact ? actions.react : nil, onDelete: canReact ? actions.delete : nil, onRetry: isLastBot ? actions.retry : nil,
                       isLastUser: isLastUser, canAnswer: canAnswer, sender: sender, botName: botName, isGroup: isGroup,
                       onAnswer: actions.answer, onOther: actions.other)
    }
}

struct MacMessageView: View {
    let entry: Entry
    var onReply: ((Entry) -> Void)? = nil
    var onReact: ((Entry, String?) -> Void)? = nil
    var onDelete: ((Entry) -> Void)? = nil
    var onRetry: ((Entry) -> Void)? = nil
    var isLastUser = false
    var canAnswer = false
    /// The Bot that wrote this message when it is not the chat's own Bot (a group member, or a Bot answering a request).
    var sender: Bot? = nil
    var botName = ""
    var isGroup = false
    var onAnswer: ((String) -> Void)? = nil
    var onOther: (() -> Void)? = nil
    @State private var copied = false
    @State private var hovering = false
    @State private var reacting = false
    private static let reactions = ["👍", "👎", "❤️", "😂", "🎉", "🤔"]

    private func copy() {
        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(entry.text, forType: .string)
        copied = true
    }

    /// Copy, react, reply and more: shown under a message while the pointer is over it. The space is always reserved so nothing jumps.
    private var actionRow: some View {
        HStack(spacing: 10) {
            Button { copy() } label: { Image(systemName: copied ? "checkmark" : "doc.on.doc") }.help("Copy")
            if onReact != nil {
                Button { reacting.toggle() } label: { Image(systemName: "face.smiling") }.help("React")
                    .popover(isPresented: $reacting) {
                        HStack(spacing: 6) {
                            ForEach(Self.reactions, id: \.self) { emoji in
                                Button { onReact?(entry, entry.reaction == emoji ? nil : emoji); reacting = false } label: { Text(emoji).font(.system(size: 20)) }.buttonStyle(.plain)
                            }
                        }.padding(10)
                    }
            }
            if onReply != nil { Button { onReply?(entry) } label: { Image(systemName: "arrowshape.turn.up.left") }.help("Reply") }
            if entry.kind == .bot, let onRetry { Button { onRetry(entry) } label: { Image(systemName: "arrow.clockwise") }.help("Retry") }
            Menu {
                Button("Copy text") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(entry.text, forType: .string) }
                Button("Copy as Markdown") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString((entry.kind == .user ? "**You:** " : "") + entry.text, forType: .string) }
                if let onDelete { Divider(); Button("Delete message", role: .destructive) { onDelete(entry) } }
            } label: { Image(systemName: "ellipsis") }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().help("More")
            if entry.kind == .bot, let provider = entry.provider {
                Text(provider).font(.system(size: 11)).foregroundStyle(MacTheme.tertiary).lineLimit(1).help("Answered by \(provider)")
            }
        }
        .buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(MacTheme.secondary)
        .padding(.horizontal, 6).frame(height: 20)
        .opacity(hovering && entry.state != .streaming ? 1 : 0)
        .animation(.easeOut(duration: 0.12), value: hovering)
    }

    private var bubbleColor: Color { entry.kind == .user ? MacTheme.userBubble : MacTheme.panel }

    @ViewBuilder private var senderAvatar: some View {
        if let sender { MacBotAvatar(color: sender.color, size: 28, appearance: sender.appearance) }
        else {
            Image(systemName: "person.crop.circle.fill").font(.system(size: 26)).foregroundStyle(MacTheme.tertiary)
                .frame(width: 28, height: 28).accessibilityHidden(true)
        }
    }

    /// Dots in a bubble while the Bot has not written anything yet, with Grok Bot's status phrase beside it.
    private var thinkingBubble: some View {
        HStack(spacing: 10) {
            MacTypingDots()
                .padding(.horizontal, 16).padding(.vertical, 14)
                .background(MacTheme.panel, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            Text("Thinking it through").font(.system(size: 13)).foregroundStyle(MacTheme.secondary)
        }
    }

    var body: some View {
        if entry.kind == .activity, entry.senderBotID != nil, entry.text.hasPrefix("Message from ") {
            botToBotMessage
        } else if entry.kind == .activity || entry.delivery == "scheduled" {
            MacActivityPill(text: entry.text, routine: entry.delivery == "scheduled").padding(.leading, 2)
        } else {
            bubbleRow
        }
    }

    /// Another Bot asking this Bot something. Shown with the sender's face and a dashed outline: Bots talking, not you.
    private var botToBotMessage: some View {
        let parts = entry.text.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
        let message = parts.count > 1 ? String(parts[1]) : entry.text
        let from = entry.senderName ?? "Another Bot"
        return HStack(alignment: .top, spacing: 10) {
            senderAvatar.padding(.top, 21)
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 5) {
                    Text(from).font(.system(size: 12, weight: .semibold))
                    Image(systemName: "arrow.right").font(.system(size: 9, weight: .bold)).foregroundStyle(MacTheme.tertiary)
                    Text(botName.isEmpty ? "this Bot" : botName).font(.system(size: 12))
                }
                .foregroundStyle(MacTheme.secondary).padding(.leading, 4)
                MacMessageContent(text: message, markdown: true)
                    .font(.system(size: 15)).lineSpacing(5).textSelection(.enabled)
                    .padding(.horizontal, 15).padding(.vertical, 10)
                    .background(MacTheme.panel.opacity(0.45), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(MacTheme.tertiary.opacity(0.6), style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
            }
            Spacer(minLength: 90)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Message from \(from) to \(botName.isEmpty ? "this Bot" : botName): \(message)")
    }

    private var bubbleRow: some View {
        let split: (text: String, prompt: ChoicePrompt?) = entry.kind == .bot ? ChoicePrompt.split(entry.text) : (entry.text, nil)
        let fromOtherBot = entry.kind == .bot && entry.senderBotID != nil
        let thinking = entry.text.isEmpty && entry.state == .streaming
        let isUser = entry.kind == .user
        return HStack(alignment: .top, spacing: 10) {
            if isUser { Spacer(minLength: 90) }
            if fromOtherBot { senderAvatar.padding(.top, 21) }
            VStack(alignment: isUser ? .trailing : .leading, spacing: 5) {
                if fromOtherBot {
                    Text(isGroup ? (entry.senderName ?? "Bot") : "\(entry.senderName ?? "Another Bot") replied")
                        .font(.system(size: 12, weight: .semibold)).foregroundStyle(MacTheme.secondary).padding(.leading, 4)
                }
                if thinking {
                    thinkingBubble
                } else if !split.text.isEmpty {
                    MacMessageContent(text: split.text, markdown: entry.kind == .bot)
                        .font(.system(size: 15.5)).lineSpacing(5).textSelection(.enabled)
                        .padding(.horizontal, 15).padding(.vertical, 10)
                        .background(bubbleColor, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                        .overlay {
                            if entry.state == .failed {
                                RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(MacTheme.danger.opacity(0.45), lineWidth: 1)
                            }
                        }
                        .contextMenu {
                            Button(copied ? "Copied" : "Copy text") { copy() }
                        }
                        .accessibilityIdentifier("conversation-message")
                        .accessibilityLabel("\(isUser ? "You" : "AI reply"): \(entry.text)")
                }
                if let prompt = split.prompt {
                    MacQuestionCard(prompt: prompt, canAnswer: canAnswer, answer: { onAnswer?($0) }, other: { onOther?() })
                }
                if entry.state == .failed {
                    Label("Couldn’t finish", systemImage: "exclamationmark.circle").font(.system(size: 11.5)).foregroundStyle(MacTheme.danger.opacity(0.9)).padding(.horizontal, 6)
                } else if entry.state == .stopped {
                    Text("Stopped").font(.system(size: 11.5)).foregroundStyle(MacTheme.tertiary).padding(.horizontal, 6)
                }
                if let reaction = entry.reaction {
                    Text(reaction).font(.system(size: 14)).padding(.horizontal, 8).padding(.vertical, 3)
                        .background(MacTheme.raised, in: Capsule()).accessibilityLabel("Reaction \(reaction)")
                }
                HStack(spacing: 8) {
                    actionRow
                    if isUser, isLastUser { Text("Delivered").font(.system(size: 11)).foregroundStyle(MacTheme.tertiary) }
                }
            }
            .onHover { inside in hovering = inside; if !inside { copied = false } }
            if !isUser { Spacer(minLength: 90) }
        }
        .frame(maxWidth: .infinity)
    }
}

/// Split fenced blocks before rendering inline Markdown. An unfinished fence remains
/// visible as code while a response is streaming.
private struct MacMessageContent: View {
    let text: String
    let markdown: Bool
    private struct Segment: Identifiable {
        let id: Int
        let code: Bool
        let text: String
    }
    private var segments: [Segment] {
        guard markdown else { return [Segment(id: 0, code: false, text: text)] }
        var result: [Segment] = [], buffer: [String] = [], code = false
        for line in text.components(separatedBy: "\n") {
            if line.hasPrefix("```") {
                if !buffer.isEmpty { result.append(Segment(id: result.count, code: code, text: buffer.joined(separator: "\n"))); buffer = [] }
                code.toggle()
            } else { buffer.append(line) }
        }
        if !buffer.isEmpty { result.append(Segment(id: result.count, code: code, text: buffer.joined(separator: "\n"))) }
        return result
    }
    private func inline(_ value: String) -> AttributedString {
        (try? AttributedString(markdown: value, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(value)
    }
    @ViewBuilder private func markdownLines(_ value: String) -> some View {
        let lines = value.components(separatedBy: "\n")
        VStack(alignment: .leading, spacing: 3) {
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                let stripped = line.trimmingCharacters(in: .whitespaces)
                let hashes = stripped.prefix(while: { $0 == "#" }).count
                if stripped.isEmpty {
                    Color.clear.frame(height: 8)
                } else if (1...6).contains(hashes), stripped.dropFirst(hashes).first == " " {
                    Text(inline(String(stripped.dropFirst(hashes + 1))))
                        .font(.system(size: max(17, 27 - CGFloat(hashes) * 2), weight: .semibold))
                        .fixedSize(horizontal: false, vertical: true)
                } else if stripped.hasPrefix("> ") {
                    HStack(alignment: .top, spacing: 10) {
                        Rectangle().fill(Color.secondary.opacity(0.5)).frame(width: 3)
                        Text(inline(String(stripped.dropFirst(2)))).fixedSize(horizontal: false, vertical: true)
                    }.fixedSize(horizontal: false, vertical: true)
                } else if stripped.hasPrefix("|"), stripped.contains("|") {
                    ScrollView(.horizontal) {
                        Text(stripped).font(.system(.body, design: .monospaced)).fixedSize(horizontal: true, vertical: false)
                    }
                } else if stripped.hasPrefix("- ") || stripped.hasPrefix("* ") {
                    HStack(alignment: .top, spacing: 8) { Text("•"); Text(inline(String(stripped.dropFirst(2)))).fixedSize(horizontal: false, vertical: true) }
                } else {
                    Text(inline(line)).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(segments) { segment in
                if segment.code {
                    VStack(alignment: .leading, spacing: 0) {
                        HStack {
                            Text("Code").font(.system(size: 11, weight: .medium)).foregroundStyle(MacTheme.secondary)
                            Spacer()
                            Button { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(segment.text, forType: .string) } label: {
                                Label("Copy", systemImage: "doc.on.doc").font(.system(size: 11))
                            }.buttonStyle(.plain).foregroundStyle(MacTheme.secondary).help("Copy code")
                        }
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .background(Color.primary.opacity(0.04))
                        ScrollView(.horizontal) {
                            Text(segment.text).font(.system(size: 13, design: .monospaced)).textSelection(.enabled).fixedSize(horizontal: true, vertical: false)
                                .padding(12)
                        }
                    }
                    .background(Color.black.opacity(0.22), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(MacTheme.line, lineWidth: 1))
                } else if markdown {
                    markdownLines(segment.text)
                } else { Text(segment.text).fixedSize(horizontal: false, vertical: true) }
            }
        }
    }
}

/// Observes the actual AppKit scroll view after layout, including on macOS 14.
/// Bounds changes caused by streamed text never turn off the user's follow intent.
struct ChatScrollMonitor: NSViewRepresentable {
    var onUserScroll: (Bool) -> Void
    var onLayout: () -> Void
    func makeNSView(context: Context) -> Probe { Probe() }
    func updateNSView(_ view: Probe, context: Context) {
        view.onUserScroll = onUserScroll; view.onLayout = onLayout
        view.connectAfterLayout()
    }
    static func dismantleNSView(_ view: Probe, coordinator: ()) {
        view.disconnect(); view.onUserScroll = nil; view.onLayout = nil
    }

    @MainActor
    final class Probe: NSView {
        var onUserScroll: ((Bool) -> Void)?
        var onLayout: (() -> Void)?
        private weak var scroll: NSScrollView?
        private var observers: [NSObjectProtocol] = []
        private var events: Any?
        private var userUntil = Date.distantPast
        private var lastDocumentSize = NSSize.zero
        private var lastViewportSize = NSSize.zero
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if window == nil { disconnect() } else { connectAfterLayout() }
        }
        func connectAfterLayout() {
            DispatchQueue.main.async { [weak self] in self?.connect() }
        }
        private func connect() {
            guard window != nil, let parent = enclosingScrollView, scroll !== parent else { return }
            disconnect(); scroll = parent
            parent.contentView.postsBoundsChangedNotifications = true
            parent.contentView.postsFrameChangedNotifications = true
            parent.documentView?.postsFrameChangedNotifications = true
            for (name, object) in [(NSView.boundsDidChangeNotification, parent.contentView as NSView),
                                   (NSView.frameDidChangeNotification, parent.contentView as NSView),
                                   (NSView.frameDidChangeNotification, parent.documentView ?? parent.contentView)] {
                observers.append(NotificationCenter.default.addObserver(forName: name, object: object, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.changed() }
                })
            }
            events = NSEvent.addLocalMonitorForEvents(matching: [.scrollWheel, .leftMouseDown, .leftMouseDragged, .keyDown]) { [weak self] event in
                MainActor.assumeIsolated { self?.userEvent(event) }
                return event
            }
            changed()
        }
        private func userEvent(_ event: NSEvent) {
            guard let scroll, event.window === scroll.window else { return }
            if event.type == .keyDown {
                guard [UInt16(115), 116, 119, 121, 125, 126].contains(event.keyCode), !(window?.firstResponder is NSTextView) else { return }
            } else {
                guard scroll.bounds.contains(scroll.convert(event.locationInWindow, from: nil)) else { return }
            }
            userUntil = Date().addingTimeInterval(0.4)
            DispatchQueue.main.async { [weak self] in self?.reportUserPosition() }
        }
        private func reportUserPosition() {
            guard let scroll, let document = scroll.documentView else { return }
            onUserScroll?(document.isFlipped ? scroll.documentVisibleRect.maxY >= document.bounds.maxY - 80 : scroll.documentVisibleRect.minY <= document.bounds.minY + 80)
        }
        private func changed() {
            guard let scroll, let document = scroll.documentView else { return }
            let resized = document.frame.size != lastDocumentSize || scroll.contentView.bounds.size != lastViewportSize
            lastDocumentSize = document.frame.size; lastViewportSize = scroll.contentView.bounds.size
            if !resized, Date() < userUntil { reportUserPosition() }
            if resized { onLayout?() }
        }
        func disconnect() {
            for token in observers { NotificationCenter.default.removeObserver(token) }
            observers = []
            if let events { NSEvent.removeMonitor(events) }
            events = nil; scroll = nil
            lastDocumentSize = .zero; lastViewportSize = .zero
        }
    }
}

private struct ComposerActionRow: View {
    let title: String
    let icon: String
    let disabled: Bool
    var tint: Color = .primary
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon).font(.system(size: 14, weight: .medium)).frame(width: 20)
                Text(title).font(.system(size: 14))
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10).padding(.vertical, 8)
            .background(hovering && !disabled ? tint.opacity(0.22) : .clear, in: RoundedRectangle(cornerRadius: 8))
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain).disabled(disabled).opacity(disabled ? 0.4 : 1)
        .onHover { hovering = $0 }
    }
}
