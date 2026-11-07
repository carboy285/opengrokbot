import SwiftUI

struct MacNewBotView: View {
    @EnvironmentObject private var app: AppModel
    @EnvironmentObject private var desktop: MacAppModel
    @State private var name = ""
    @State private var purpose = ""
    @State private var color = "purple"
    @State private var importNote: String?
    @FocusState private var nameFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack { Text("Create a Bot").font(.system(size: 24, weight: .medium)); Spacer(); closeButton }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(BotTemplate.all) { template in
                        Button { name = template.name; purpose = template.purpose; color = template.color } label: {
                            Label(template.name, systemImage: template.symbol).font(.system(size: 12)).padding(.horizontal, 12).padding(.vertical, 7)
                                .background(MacTheme.raised, in: Capsule())
                        }.buttonStyle(.plain).help(template.purpose)
                    }
                    Button { if let shared = BotSharing.choose() { name = shared.name; purpose = shared.purpose; color = shared.color } else { importNote = "That file is not a shared Bot." } } label: {
                        Label("Import a shared Bot…", systemImage: "square.and.arrow.down").font(.system(size: 12)).padding(.horizontal, 12).padding(.vertical, 7)
                            .overlay(Capsule().stroke(MacTheme.secondary.opacity(0.5)))
                    }.buttonStyle(.plain)
                }.padding(.vertical, 4)
            }.padding(.top, 14)
            if let importNote { Text(importNote).font(.system(size: 12)).foregroundStyle(MacTheme.secondary) }
            Spacer()
            MacBotAvatar(color: color, size: 90).padding(.bottom, 25)
            VStack(alignment: .leading, spacing: 12) {
                Text("Name").foregroundStyle(MacTheme.secondary)
                TextField("Give your Bot a name", text: $name).focused($nameFocused)
                    .textFieldStyle(.plain).font(.system(size: 20)).padding(16).background(MacTheme.raised, in: RoundedRectangle(cornerRadius: 14))
                Text("What should it help with?").foregroundStyle(MacTheme.secondary).padding(.top, 8)
                TextField("A short description", text: $purpose, axis: .vertical)
                    .textFieldStyle(.plain).lineLimit(3...5).padding(16).background(MacTheme.raised, in: RoundedRectangle(cornerRadius: 14))
                HStack(spacing: 16) {
                    ForEach(["purple", "pink", "ochre", "white"], id: \.self) { choice in
                        Button { color = choice } label: {
                            Circle().fill(MacTheme.botColor(choice)).frame(width: 25, height: 25)
                                .padding(5).overlay(Circle().stroke(color == choice ? .white : .clear, lineWidth: 1))
                        }.buttonStyle(.plain).accessibilityLabel("\(choice) avatar").accessibilityAddTraits(color == choice ? [.isSelected] : [])
                    }
                    Spacer()
                }.padding(.top, 6)
            }.frame(maxWidth: 500)
            Spacer()
            HStack {
                Text("Creates a Bot with its own AI CLI conversation.").font(.system(size: 12)).foregroundStyle(MacTheme.secondary)
                Spacer()
                MacPillButton(title: "Create Bot", prominent: true) {
                    if app.addBot(name: name, purpose: purpose, color: color) {
                        desktop.selectedID = app.workspace.bots.last?.id
                        desktop.panel = nil
                    }
                }.disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }.padding(34).onAppear { nameFocused = true }
    }

    private var closeButton: some View {
        Button { desktop.panel = nil } label: { Image(systemName: "xmark").font(.system(size: 19)).frame(width: 34, height: 34) }
            .buttonStyle(.plain).help("Close").accessibilityLabel("Close new Bot")
    }
}
