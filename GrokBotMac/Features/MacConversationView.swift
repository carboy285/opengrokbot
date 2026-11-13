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
    @ObservedObject private var voiceHub = MacVoiceHub.shared
    /// The message a search or pin jumped to, highlighted for a moment.
    @State private var highlighted: UUID?
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
                        let lastUserID = messages.last(where: { $0.kind == .user && $0.delivery != "scheduled" && $0.delivery != "proactive" })?.id
                        // A question card can be answered while nothing has been said after it.
                        let lastTalkID = messages.last(where: { $0.kind != .activity })?.id
                        let bots = app.workspace.bots
                        ForEach(messages) { entry in
                            // Equatable rows: a streaming reply redraws only the message that changed, not every message in the chat.
                            row(entry, lastBotID: lastBotID, lastUserID: lastUserID, lastTalkID: lastTalkID, bots: bots).equatable()
                                .background(highlighted == entry.id ? MacTheme.working.opacity(0.14) : .clear, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                                .id(entry.id)
                        }
                        if messages.isEmpty { emptyConversation.padding(.top, 120) }
                        Color.clear.frame(height: 1).id("bottom")
                    }
                    .padding(.horizontal, 24).padding(.top, 88).padding(.bottom, 20)
                    .frame(maxWidth: 780).frame(maxWidth: .infinity)
                    .background(ChatScrollMonitor(onUserScroll: { nearBottom in followLatest = nearBottom },
                        onLayout: { if followLatest { scrollToLatest(proxy) } }))
                }
                .task(id: bot.id) { followLatest = true; scrollToLatest(proxy); jump(proxy) }
                .onChange(of: desktop.jumpTo) { _, _ in jump(proxy) }
                .onChange(of: app.entries(for: bot).last) { _, _ in
                    if followLatest { scrollToLatest(proxy) }
                }
                .onDisappear { scrollTask?.cancel() }

            }
            composer
        }
        // 0.9.4: messages fade out under the header so the Bot's name and model never sit on top of text.
        .overlay(alignment: .top) {
            LinearGradient(stops: [.init(color: MacTheme.canvas, location: 0), .init(color: MacTheme.canvas, location: 0.55), .init(color: MacTheme.canvas.opacity(0), location: 1)],
                           startPoint: .top, endPoint: .bottom)
                .frame(height: 84).allowsHitTesting(false).accessibilityHidden(true)
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
        .overlay(alignment: .topLeading) {
            // Pinned messages in this chat (0.9.5): pick one to jump to it.
            let pins = app.entries(for: bot).filter { $0.pinned == true }
            if !pins.isEmpty {
                Menu {
                    ForEach(pins) { pin in
                        Button(String(FollowUps.split(ChoicePrompt.split(pin.text).text).text.prefix(60))) { desktop.jumpTo = pin.id }
                    }
                } label: {
                    Label("\(pins.count)", systemImage: "pin.fill").font(.system(size: 11.5, weight: .medium)).foregroundStyle(MacTheme.secondary)
                        .padding(.horizontal, 10).padding(.vertical, 6).background(MacTheme.panel.opacity(0.7), in: Capsule())
                }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().help("Pinned messages")
                .padding(.top, 14).padding(.leading, 18)
            }
        }
        .background(MacTheme.canvas)
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
                // 0.9.4: dictation and send / voice read as one control.
                HStack(spacing: 2) {
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
                .padding(.leading, 4).padding(.trailing, 2).padding(.vertical, 2)
                .background(Color.primary.opacity(0.06), in: Capsule())
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
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                ForEach(FollowUps.starters(name: bot.name, purpose: bot.purpose), id: \.self) { idea in
                    MacStarterCard(text: idea) { draft.wrappedValue = idea; sendMessage() }
                }
            }
            .frame(maxWidth: 560).padding(.top, 14)
        }.frame(maxWidth: .infinity)
    }

    /// Scrolls to a message found by search or a pin, and highlights it briefly.
    private func jump(_ proxy: ScrollViewProxy) {
        guard let target = desktop.jumpTo, app.entries(for: bot).contains(where: { $0.id == target }) else { return }
        desktop.jumpTo = nil; followLatest = false
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 150_000_000)
            withAnimation(.easeOut(duration: 0.25)) { proxy.scrollTo(target, anchor: .center) }
            highlighted = target
            try? await Task.sleep(nanoseconds: 1_800_000_000)
            withAnimation(.easeOut(duration: 0.4)) { if highlighted == target { highlighted = nil } }
        }
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

    /// Voice mode lives in the window (MacVoiceHub), so it keeps going when you open another Bot.
    private func startVoice() { voiceHub.start(bot: bot, desktop: desktop, app: app) }

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
            ComposerActionRow(title: "Export as Markdown…", icon: "square.and.arrow.up", disabled: false, tint: tint) {
                showActions = false
                DispatchQueue.main.async { desktop.exportConversation(bot, app: app) }
            }
            ComposerActionRow(title: "Export as PDF…", icon: "doc.richtext", disabled: false, tint: tint) {
                showActions = false
                DispatchQueue.main.async { desktop.exportConversation(bot, app: app, pdf: true) }
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
            other: { composing = true },
            edit: { entry in
                guard !desktopModel.runningBots.contains(current.id) else { return }
                let list = model.entries(for: current)
                guard let start = list.firstIndex(where: { $0.id == entry.id }) else { return }
                for later in list[start...].reversed() { _ = model.deleteEntry(later.id) }
                draft.wrappedValue = entry.text; composing = true
            },
            pin: { entry in _ = model.setPinned(entry.pinned != true, for: entry.id) })
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
    /// Puts your latest message back in the box and removes it and what came after (0.9.5).
    var edit: (Entry) -> Void = { _ in }
    /// Pins or unpins a message (0.9.5).
    var pin: (Entry) -> Void = { _ in }
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
                       onAnswer: actions.answer, onOther: actions.other, onEdit: canReact && isLastUser ? actions.edit : nil, onPin: canReact ? actions.pin : nil)
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
    var onEdit: ((Entry) -> Void)? = nil
    var onPin: ((Entry) -> Void)? = nil
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
            if entry.kind == .user, let onEdit { Button { onEdit(entry) } label: { Image(systemName: "pencil") }.help("Edit and resend") }
            if entry.kind == .bot, let onRetry { Button { onRetry(entry) } label: { Image(systemName: "arrow.clockwise") }.help("Retry") }
            Menu {
                Button("Copy text") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(entry.text, forType: .string) }
                Button("Copy as Markdown") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString((entry.kind == .user ? "**You:** " : "") + entry.text, forType: .string) }
                ShareLink("Share…", item: FollowUps.split(ChoicePrompt.split(entry.text).text).text)
                if let onPin { Button(entry.pinned == true ? "Unpin" : "Pin message") { onPin(entry) } }
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
        } else if entry.delivery == "proactive" {
            // An automatic heads-up check (from the Windows app): show its short label, never the prompt with email text.
            MacActivityPill(text: entry.label ?? "Automatic check").padding(.leading, 2)
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
        let choice: (text: String, prompt: ChoicePrompt?) = entry.kind == .bot ? ChoicePrompt.split(entry.text) : (entry.text, nil)
        // Follow-up chips (0.9.5): the Bot's suggested next requests, under the latest reply only.
        let follow: (text: String, suggestions: [String]) = entry.kind == .bot ? FollowUps.split(choice.text) : (choice.text, [])
        let split: (text: String, prompt: ChoicePrompt?) = (follow.text, choice.prompt)
        let fromOtherBot = entry.kind == .bot && entry.senderBotID != nil
        let thinking = entry.text.isEmpty && entry.state == .streaming
        let isUser = entry.kind == .user
        return HStack(alignment: .top, spacing: 10) {
            if isUser { Spacer(minLength: 90) }
            if fromOtherBot { senderAvatar.padding(.top, 21) }
            VStack(alignment: isUser ? .trailing : .leading, spacing: 5) {
                if let tag = entry.headsUp, entry.kind == .bot { MacHeadsUpTag(tag: tag, date: entry.date) }
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
                } else if canAnswer, !follow.suggestions.isEmpty {
                    MacFollowUps(suggestions: follow.suggestions) { onAnswer?($0) }
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
                    if entry.pinned == true { Image(systemName: "pin.fill").font(.system(size: 10)).foregroundStyle(MacTheme.attention).help("Pinned").accessibilityLabel("Pinned") }
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

/// Split fenced blocks before rendering Markdown. An unfinished fence remains visible as code while a response is streaming.
/// 0.9.5: numbered and nested lists, real tables, syntax-highlighted code and inline images.
private struct MacMessageContent: View {
    let text: String
    let markdown: Bool
    private struct Segment: Identifiable {
        let id: Int
        let code: Bool
        let language: String
        let text: String
    }
    private var segments: [Segment] {
        guard markdown else { return [Segment(id: 0, code: false, language: "", text: text)] }
        var result: [Segment] = [], buffer: [String] = [], code = false, language = ""
        for line in text.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") {
                if !buffer.isEmpty { result.append(Segment(id: result.count, code: code, language: language, text: buffer.joined(separator: "\n"))); buffer = [] }
                if !code { language = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces).lowercased() }
                code.toggle()
            } else { buffer.append(line) }
        }
        if !buffer.isEmpty { result.append(Segment(id: result.count, code: code, language: language, text: buffer.joined(separator: "\n"))) }
        return result
    }
    private func inline(_ value: String) -> AttributedString {
        (try? AttributedString(markdown: value, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(value)
    }

    /// Lines grouped into blocks so a table is drawn as one grid.
    private enum Block: Identifiable {
        case line(Int, String)
        case table(Int, header: [String], rows: [[String]])
        var id: Int { switch self { case .line(let id, _), .table(let id, _, _): id } }
    }
    private static func cells(_ line: String) -> [String] {
        var value = line.trimmingCharacters(in: .whitespaces)
        if value.hasPrefix("|") { value.removeFirst() }
        if value.hasSuffix("|") { value.removeLast() }
        return value.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
    }
    private static func isSeparator(_ line: String) -> Bool {
        let value = line.trimmingCharacters(in: .whitespaces)
        return value.contains("-") && value.allSatisfy { "|:- ".contains($0) }
    }
    private func blocks(_ value: String) -> [Block] {
        let lines = value.components(separatedBy: "\n")
        var result: [Block] = [], index = 0
        while index < lines.count {
            let line = lines[index], trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("|"), index + 1 < lines.count, Self.isSeparator(lines[index + 1]) {
                let header = Self.cells(line)
                var rows: [[String]] = []
                index += 2
                while index < lines.count, lines[index].trimmingCharacters(in: .whitespaces).hasPrefix("|") { rows.append(Self.cells(lines[index])); index += 1 }
                result.append(.table(result.count, header: header, rows: rows))
                continue
            }
            result.append(.line(result.count, line)); index += 1
        }
        return result
    }

    @ViewBuilder private func lineView(_ line: String) -> some View {
        let stripped = line.trimmingCharacters(in: .whitespaces)
        let indent = CGFloat(line.prefix(while: { $0 == " " }).count / 2) * 16
        let hashes = stripped.prefix(while: { $0 == "#" }).count
        let numbered = stripped.range(of: "^\\d{1,3}[.)] ", options: .regularExpression)
        if stripped.isEmpty {
            Color.clear.frame(height: 6)
        } else if (1...6).contains(hashes), stripped.dropFirst(hashes).first == " " {
            Text(inline(String(stripped.dropFirst(hashes + 1))))
                .font(.system(size: max(16, 22 - CGFloat(hashes) * 1.5), weight: .semibold))
                .padding(.top, 4).fixedSize(horizontal: false, vertical: true)
        } else if stripped.hasPrefix("> ") {
            HStack(alignment: .top, spacing: 10) {
                Rectangle().fill(Color.secondary.opacity(0.5)).frame(width: 3)
                Text(inline(String(stripped.dropFirst(2)))).foregroundStyle(Color.primary.opacity(0.82)).fixedSize(horizontal: false, vertical: true)
            }.fixedSize(horizontal: false, vertical: true)
        } else if stripped.hasPrefix("!["), let image = MacInlineImage.parse(stripped) {
            image
        } else if let numbered {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(String(stripped[numbered]).trimmingCharacters(in: .whitespaces)).foregroundStyle(MacTheme.secondary).monospacedDigit()
                Text(inline(String(stripped[numbered.upperBound...]))).fixedSize(horizontal: false, vertical: true)
            }.padding(.leading, indent)
        } else if stripped.hasPrefix("- ") || stripped.hasPrefix("* ") || stripped.hasPrefix("+ ") {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(indent > 0 ? "◦" : "•").foregroundStyle(MacTheme.secondary)
                Text(inline(String(stripped.dropFirst(2)))).fixedSize(horizontal: false, vertical: true)
            }.padding(.leading, indent)
        } else if stripped.count >= 3, stripped.allSatisfy({ "-*_".contains($0) }) {
            Divider().padding(.vertical, 4)
        } else {
            Text(inline(line)).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func table(header: [String], rows: [[String]]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            Grid(alignment: .leading, horizontalSpacing: 0, verticalSpacing: 0) {
                GridRow {
                    ForEach(Array(header.enumerated()), id: \.offset) { _, cell in
                        Text(inline(cell)).font(.system(size: 13, weight: .semibold)).padding(.horizontal, 11).padding(.vertical, 7)
                    }
                }
                .background(Color.primary.opacity(0.05))
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    Divider().gridCellUnsizedAxes(.horizontal)
                    GridRow {
                        ForEach(Array(row.enumerated()), id: \.offset) { _, cell in
                            Text(inline(cell)).font(.system(size: 13)).padding(.horizontal, 11).padding(.vertical, 7)
                        }
                    }
                }
            }
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(MacTheme.line, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(segments) { segment in
                if segment.code {
                    VStack(alignment: .leading, spacing: 0) {
                        HStack {
                            Text(segment.language.isEmpty ? "Code" : segment.language).font(.system(size: 11, weight: .medium)).foregroundStyle(MacTheme.secondary)
                            Spacer()
                            Button { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(segment.text, forType: .string) } label: {
                                Label("Copy", systemImage: "doc.on.doc").font(.system(size: 11))
                            }.buttonStyle(.plain).foregroundStyle(MacTheme.secondary).help("Copy code")
                        }
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .background(Color.primary.opacity(0.04))
                        ScrollView(.horizontal) {
                            Text(CodeHighlight.attributed(segment.text)).font(.system(size: 13, design: .monospaced)).textSelection(.enabled).fixedSize(horizontal: true, vertical: false)
                                .padding(12)
                        }
                    }
                    .background(Color.black.opacity(0.22), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(MacTheme.line, lineWidth: 1))
                } else if markdown {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(blocks(segment.text)) { block in
                            switch block {
                            case .line(_, let line): lineView(line)
                            case .table(_, let header, let rows): table(header: header, rows: rows)
                            }
                        }
                    }
                } else { Text(segment.text).fixedSize(horizontal: false, vertical: true) }
            }
        }
    }
}

/// Keyword, string, comment and number colours for code in replies. Language-agnostic; mirrors markdown-core.mjs.
enum CodeHighlight {
    private static let keywords: Set<String> = Set("abstract and as async await break case catch class const continue def default defer del do elif else enum export extends false final finally fn for from func function go guard if impl import in interface is lambda let match mut new nil none not null or package pass private protected pub public raise return self static struct super switch this throw true try type typeof undefined use var void where while with yield".split(separator: " ").map(String.init))
    private static let pattern = try? NSRegularExpression(pattern: #"(//[^\n]*|#[^\n]*|/\*[\s\S]*?\*/|--[^\n]*)|("(?:\\.|[^"\\\n])*"|'(?:\\.|[^'\\\n])*'|`(?:\\.|[^`\\])*`)|\b(\d+(?:\.\d+)?)\b|\b([A-Za-z_][A-Za-z0-9_]*)\b"#)

    static func attributed(_ code: String) -> AttributedString {
        guard let pattern else { return AttributedString(code) }
        var result = AttributedString()
        var last = code.startIndex
        let whole = NSRange(code.startIndex..., in: code)
        for match in pattern.matches(in: code, range: whole) {
            guard let range = Range(match.range, in: code) else { continue }
            if range.lowerBound > last { result += AttributedString(String(code[last..<range.lowerBound])) }
            var piece = AttributedString(String(code[range]))
            if match.range(at: 1).location != NSNotFound { piece.foregroundColor = Color(hex: 0x7F8590) }
            else if match.range(at: 2).location != NSNotFound { piece.foregroundColor = Color(hex: 0x9FD27C) }
            else if match.range(at: 3).location != NSNotFound { piece.foregroundColor = Color(hex: 0xF78C6C) }
            else if keywords.contains(String(code[range])) { piece.foregroundColor = Color(hex: 0xC792EA) }
            result += piece
            last = range.upperBound
        }
        if last < code.endIndex { result += AttributedString(String(code[last...])) }
        return result
    }
}

/// An image line in a reply: a web image, or a picture the Bot saved in OpenGrokBot's own folders.
struct MacInlineImage: View {
    let alt: String
    let source: String

    static func parse(_ line: String) -> MacInlineImage? {
        guard let altEnd = line.range(of: "]("), line.hasSuffix(")") else { return nil }
        let alt = String(line[line.index(line.startIndex, offsetBy: 2)..<altEnd.lowerBound])
        let source = String(line[altEnd.upperBound..<line.index(before: line.endIndex)]).trimmingCharacters(in: .whitespaces)
        return source.isEmpty ? nil : MacInlineImage(alt: alt, source: source)
    }

    /// Only files inside ~/Library/Application Support/OpenGrokBot are shown; nothing else on the Mac is read.
    private var localImage: NSImage? {
        let path = source.hasPrefix("file://") ? (URL(string: source)?.path ?? "") : source
        let allowed = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/OpenGrokBot").standardizedFileURL.path
        let resolved = URL(fileURLWithPath: path).standardizedFileURL.path
        guard resolved.hasPrefix(allowed + "/"), ["png", "jpg", "jpeg", "gif", "webp", "heic"].contains(URL(fileURLWithPath: resolved).pathExtension.lowercased()) else { return nil }
        return NSImage(contentsOfFile: resolved)
    }

    var body: some View {
        if source.hasPrefix("https://"), let url = URL(string: source) {
            AsyncImage(url: url) { image in image.resizable().scaledToFit() } placeholder: { Text(alt.isEmpty ? "Loading image…" : alt).foregroundStyle(MacTheme.secondary) }
                .frame(maxWidth: 420, maxHeight: 320, alignment: .leading)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        } else if let image = localImage {
            Image(nsImage: image).resizable().scaledToFit()
                .frame(maxWidth: 420, maxHeight: 320, alignment: .leading)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .accessibilityLabel(alt.isEmpty ? "Image" : alt)
        } else {
            Text(alt.isEmpty ? "Image" : alt).italic().foregroundStyle(MacTheme.secondary)
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

/// Tap-to-send follow-ups under the latest reply, like ChatGPT's suggestions.
struct MacFollowUps: View {
    let suggestions: [String]
    let send: (String) -> Void
    @State private var hovered: String?
    var body: some View {
        HStack(spacing: 8) {
            ForEach(suggestions, id: \.self) { suggestion in
                Button { send(suggestion) } label: {
                    HStack(spacing: 6) {
                        Text(suggestion).font(.system(size: 13)).lineLimit(1)
                        Image(systemName: "arrow.up.right").font(.system(size: 9, weight: .bold)).foregroundStyle(MacTheme.tertiary)
                    }
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .background(hovered == suggestion ? MacTheme.raised : MacTheme.panel.opacity(0.55), in: Capsule())
                    .overlay(Capsule().stroke(MacTheme.line, lineWidth: 1))
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .onHover { inside in hovered = inside ? suggestion : (hovered == suggestion ? nil : hovered) }
            }
        }
        .accessibilityElement(children: .contain).accessibilityLabel("Suggested follow-ups")
    }
}

/// An idea to start an empty chat with.
struct MacStarterCard: View {
    let text: String
    let action: () -> Void
    @State private var hovering = false
    var body: some View {
        Button(action: action) {
            Text(text).font(.system(size: 13.5)).multilineTextAlignment(.leading).frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14).padding(.vertical, 13)
                .background(hovering ? MacTheme.panel : MacTheme.panel.opacity(0.55), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(MacTheme.line, lineWidth: 1))
                .contentShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain).onHover { hovering = $0 }
    }
}
