import AppKit
import SwiftUI

struct MacConversationView: View {
    let bot: Bot
    @EnvironmentObject private var app: AppModel
    @EnvironmentObject private var desktop: MacAppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("spellChecking") private var spellChecking = true
    @FocusState private var composing: Bool

    private var draft: Binding<String> {
        Binding(get: { desktop.drafts[bot.id] ?? "" }, set: { desktop.drafts[bot.id] = $0 })
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 25) {
                        ForEach(app.entries(for: bot)) { entry in
                            MacMessageView(entry: entry).id(entry.id)
                        }
                        if app.entries(for: bot).isEmpty { emptyConversation.padding(.top, 120) }
                        Color.clear.frame(height: 1).id("bottom")
                    }
                    .padding(.horizontal, 24).padding(.top, 85).padding(.bottom, 24)
                    .frame(maxWidth: 1040).frame(maxWidth: .infinity)
                }
                .onChange(of: app.entries(for: bot).count) { _, _ in
                    withAnimation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 1)) { proxy.scrollTo("bottom", anchor: .bottom) }
                }
            }
            composer
        }
        .overlay(alignment: .top) {
            HStack(spacing: 11) {
                MacBotAvatar(color: bot.color, size: 27)
                Text(bot.name).font(.system(size: 18, weight: .medium)).lineLimit(1)
            }
            .padding(.horizontal, 15).padding(.vertical, 10)
            .glassChrome(in: Capsule(), interactive: false)
            .padding(.top, 12)
        }
        .background(MacTheme.canvas)
    }

    private var composer: some View {
        VStack(spacing: 8) {
            HStack(alignment: .bottom, spacing: 11) {
                Menu {
                    Button("Export conversation…") { desktop.exportConversation(bot, app: app) }
                    Divider()
                    Button("Attachment status…") {
                        desktop.importFeedback = "File attachments are not implemented yet. You can paste text into a message; the selected CLI will receive it."
                        desktop.panel = .integration
                    }
                } label: {
                    Image(systemName: "plus").font(.system(size: 25, weight: .light)).frame(width: 38, height: 38)
                        .background(Color.white.opacity(0.06), in: Circle())
                }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().help("Conversation actions")
                TextField("Message \(bot.name)", text: draft, axis: .vertical)
                    .textFieldStyle(.plain).font(.system(size: 18)).lineLimit(1...7)
                    .disableAutocorrection(!spellChecking).focused($composing)
                    .padding(.vertical, 9)
                    .accessibilityIdentifier("chat-input").accessibilityLabel("Message for \(bot.name)")
                if desktop.runningBots.contains(bot.id) {
                    Button { desktop.stop(botID: bot.id) } label: { Image(systemName: "stop.fill").frame(width: 38, height: 38) }.buttonStyle(.plain).help("Stop response")
                } else if !draft.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Button { sendMessage() } label: {
                        Image(systemName: "arrow.up").font(.system(size: 19, weight: .semibold)).foregroundStyle(.black)
                            .frame(width: 38, height: 38).background(.white, in: Circle())
                    }.buttonStyle(.plain).disabled(!desktop.canChat).keyboardShortcut(.return, modifiers: .command)
                        .help("Send message (⌘Return)").accessibilityLabel("Send message")
                } else {
                    Image(systemName: "mic").font(.system(size: 21)).foregroundStyle(MacTheme.secondary)
                        .frame(width: 36, height: 38).help("Voice input is not available in this version")
                    Image(systemName: "waveform").font(.system(size: 21, weight: .bold)).foregroundStyle(.black)
                        .frame(width: 38, height: 38).background(.white, in: Circle())
                        .help("Voice chat is not available in this version")
                }
            }
            .padding(9).glassChrome(in: RoundedRectangle(cornerRadius: 31))
            HStack(spacing: 9) {
                if desktop.scanningCLIs { ProgressView().controlSize(.mini) }
                if desktop.installedCLIs.isEmpty {
                    Button("Set up an AI CLI") { desktop.panel = .setup }.buttonStyle(.link)
                } else {
                    Picker("AI CLI", selection: Binding(get: { desktop.selectedCLIID }, set: { desktop.chooseCLI($0) })) {
                        ForEach(desktop.installedCLIs) { cli in Text(cli.provider.name).tag(cli.id) }
                    }.labelsHidden().frame(width: 140).controlSize(.mini).disabled(!desktop.runningBots.isEmpty)
                }
                Spacer()
                if desktop.runningBots.contains(bot.id) {
                    ProgressView().controlSize(.mini)
                    Text("Working…")
                    Button("Stop") { desktop.stop(botID: bot.id) }.buttonStyle(.link)
                } else { Text("⌘Return to send · Uses your CLI account") }
            }.font(.system(size: 11)).foregroundStyle(MacTheme.secondary)
            if let error = desktop.runErrors[bot.id] {
                HStack { Text(error).font(.system(size: 11)); Spacer(); Button("Retry") { desktop.retry(bot: bot, app: app) } }.foregroundStyle(MacTheme.secondary)
            }
        }.padding(.horizontal, 20).padding(.bottom, 12).padding(.top, 8)
    }

    private var emptyConversation: some View {
        VStack(spacing: 18) {
            MacBotAvatar(color: bot.color, size: 70)
            Text(bot.name).font(.system(size: 24, weight: .medium))
            Text(bot.purpose).foregroundStyle(MacTheme.secondary)
            Text("Send your first message to start chatting with your selected local AI CLI.")
                .font(.system(size: 13)).foregroundStyle(MacTheme.secondary)
        }.frame(maxWidth: .infinity)
    }

    private func sendMessage() {
        if desktop.send(draft.wrappedValue, to: bot, app: app) { draft.wrappedValue = ""; composing = true }
    }
}

private struct MacMessageView: View {
    let entry: Entry
    @State private var copied = false

    var body: some View {
        if entry.kind == .activity {
            HStack(spacing: 7) {
                Text(entry.text.components(separatedBy: " · ").first ?? entry.text)
                MacBotAvatar(color: "ochre", size: 17)
                Text("School")
            }.font(.system(size: 14)).foregroundStyle(MacTheme.secondary)
                .frame(maxWidth: .infinity).padding(.vertical, 2)
                .accessibilityLabel("Activity: \(entry.text)")
        } else {
            HStack(alignment: .top) {
                if entry.kind == .user { Spacer(minLength: 90) }
                Text(entry.text.isEmpty && entry.state == .streaming ? "Thinking…" : entry.text)
                    .font(.system(size: 18)).lineSpacing(6).textSelection(.enabled)
                    .padding(.horizontal, 16).padding(.vertical, 12)
                    .background(entry.kind == .user ? MacTheme.userBubble : MacTheme.panel, in: RoundedRectangle(cornerRadius: entry.kind == .user ? 24 : 23))
                    .overlay(RoundedRectangle(cornerRadius: 23).stroke(Color.white.opacity(0.025), lineWidth: 1))
                    .contextMenu {
                        Button(copied ? "Copied" : "Copy text") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(entry.text, forType: .string)
                            copied = true
                        }
                    }
                    .accessibilityIdentifier("conversation-message")
                    .accessibilityLabel("\(entry.kind == .user ? "You" : "AI reply"): \(entry.text)")
                if entry.kind == .bot { Spacer(minLength: 90) }
            }.frame(maxWidth: .infinity)
        }
    }
}
