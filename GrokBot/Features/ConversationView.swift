import SwiftUI

struct ConversationView: View {
    let bot: Bot
    @EnvironmentObject private var model: AppModel
    @State private var draft = ""
    @FocusState private var composing: Bool
    @State private var info = false

    var body: some View {
        VStack(spacing: 0) {
            PreviewBanner()
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 20) {
                        if model.entries(for: bot).isEmpty {
                            VStack(spacing: 16) {
                                BotAvatar(color: bot.color, size: 70)
                                Text("A fresh conversation").font(.title2.weight(.medium))
                                Text("Set up an AI CLI in the Mac or Windows app. A desktop host connection is required for iPhone chat.")
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
                Button { info = true } label: { HStack(spacing: 10) { BotAvatar(color: bot.color, size: 24); Text(bot.name).font(.headline).lineLimit(1) } }.accessibilityLabel("Bot details for \(bot.name)")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { info = true } label: { Image(systemName: "info.circle").frame(width: 44, height: 44) }.accessibilityLabel("Connection details")
            }
        }
        .sheet(isPresented: $info) {
            NavigationStack {
                VStack(spacing: 24) {
                    BotAvatar(color: bot.color, size: 80)
                    Text(bot.name).font(.title)
                    Text(bot.purpose).foregroundStyle(.secondary)
                    StatusCard(title: "Desktop host needed", detail: "iOS cannot run desktop AI CLIs. This build does not yet include the host connection needed to relay messages from your iPhone.", symbol: "desktopcomputer")
                    NavigationLink("Desktop setup guide") { IntegrationView() }
                    Spacer()
                }.padding(24).padding(.top, 30)
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { info = false } } }
            }.presentationDetents([.medium, .large])
        }
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .bottom, spacing: 12) {
                Text("Connect a desktop host to chat").foregroundStyle(.secondary).padding(.vertical, 12)
                Spacer()
                Button { info = true } label: { Image(systemName: "desktopcomputer").frame(width: 44, height: 44) }.accessibilityLabel("Desktop setup guide")
            }.padding(8).padding(.leading, 14).glassChrome(in: RoundedRectangle(cornerRadius: 28))
            Text("Use the Mac or Windows app for local CLI chat").font(.caption2).foregroundStyle(.secondary).frame(maxWidth: .infinity)
        }.padding(.horizontal, 16).padding(.vertical, 10).background(Palette.background)
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
