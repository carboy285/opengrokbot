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
                                Text("Write a local note to explore this layout. Real agent responses require a verified integration.")
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
                HStack(spacing: 10) { BotAvatar(color: bot.color, size: 24); Text(bot.name).font(.headline).lineLimit(1) }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { info = true } label: { Image(systemName: "info.circle").frame(width: 44, height: 44) }.accessibilityLabel("Preview details")
            }
        }
        .sheet(isPresented: $info) {
            NavigationStack {
                VStack(spacing: 24) {
                    BotAvatar(color: bot.color, size: 80)
                    Text(bot.name).font(.title)
                    Text(bot.purpose).foregroundStyle(.secondary)
                    StatusCard(title: "Offline preview", detail: "Notes are saved locally. Example Bot messages and handoffs are fixtures, not live activity. No tools, approvals, or agents execute.", symbol: "iphone.slash")
                    Spacer()
                }.padding(24).padding(.top, 30)
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { info = false } } }
            }.presentationDetents([.medium, .large])
        }
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .bottom, spacing: 12) {
                TextField("Write a local note", text: $draft, axis: .vertical)
                    .lineLimit(1...6).padding(.vertical, 12).focused($composing)
                    .accessibilityLabel("Local preview note")
                Button {
                    if model.addNote(draft, to: bot) { draft = "" }
                } label: {
                    Image(systemName: "arrow.up").font(.headline).frame(width: 44, height: 44)
                        .background(Color.primary, in: Circle()).foregroundStyle(Palette.background)
                }
                .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityLabel("Save local note")
            }.padding(8).padding(.leading, 14).glassChrome(in: RoundedRectangle(cornerRadius: 28))
            Text("Saved on this iPhone · No message is sent").font(.caption2).foregroundStyle(.secondary).frame(maxWidth: .infinity)
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
                    if entry.kind == .bot { Text("EXAMPLE").font(.caption2.weight(.semibold)).foregroundStyle(.secondary).tracking(1) }
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
