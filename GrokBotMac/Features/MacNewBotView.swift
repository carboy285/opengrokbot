import SwiftUI

/// A small dialog: a live preview, a name, a shape and a colour. Description and templates are optional and tucked below.
struct MacNewBotView: View {
    @EnvironmentObject private var app: AppModel
    @EnvironmentObject private var desktop: MacAppModel
    @State private var name = ""
    @State private var purpose = ""
    @State private var shape = BotAvatarShape.hexagon
    @State private var color = "purple"
    @State private var showTemplates = false
    @State private var importNote: String?
    @FocusState private var nameFocused: Bool

    private let colors = ["purple", "pink", "red", "orange", "amber", "green", "teal", "blue", "gray", "black"]
    private var cleanName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        VStack(spacing: 18) {
            HStack {
                Text("Create a Bot").font(.system(size: 22, weight: .medium))
                Spacer()
                Button { desktop.panel = nil } label: { Image(systemName: "xmark").font(.system(size: 16)).frame(width: 32, height: 32) }
                    .buttonStyle(.plain).help("Close").accessibilityLabel("Close new Bot")
            }
            CustomBotAvatar(appearance: BotAppearance(shape: shape, color: color), size: 100).padding(.top, 2)
            TextField("Name your Bot", text: $name).focused($nameFocused)
                .textFieldStyle(.plain).font(.system(size: 18)).padding(14).background(MacTheme.raised, in: RoundedRectangle(cornerRadius: 14))
                .onSubmit(create)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    LazyVGrid(columns: Array(repeating: GridItem(.fixed(58), spacing: 8), count: 5), spacing: 8) {
                        ForEach(BotAvatarShape.allCases, id: \.self) { option in
                            Button { shape = option } label: {
                                CustomBotAvatar(appearance: BotAppearance(shape: option, color: color), size: 42).frame(width: 54, height: 54)
                                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(shape == option ? Color.primary : .clear, lineWidth: 2))
                            }.buttonStyle(.plain).accessibilityLabel(option.label + " shape").accessibilityAddTraits(shape == option ? [.isSelected] : [])
                        }
                    }.frame(maxWidth: .infinity)
                    LazyVGrid(columns: Array(repeating: GridItem(.fixed(36), spacing: 14), count: 5), spacing: 12) {
                        ForEach(colors, id: \.self) { option in
                            Button { color = option } label: {
                                Circle().fill(AvatarArtwork.color(option)).frame(width: 28, height: 28).padding(4)
                                    .overlay(Circle().stroke(color == option ? Color.primary : .clear, lineWidth: 2))
                            }.buttonStyle(.plain).accessibilityLabel(option + " color").accessibilityAddTraits(color == option ? [.isSelected] : [])
                        }
                    }.frame(maxWidth: .infinity)
                    DisclosureGroup("Start from a template or add a description", isExpanded: $showTemplates) {
                        VStack(alignment: .leading, spacing: 10) {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(BotTemplate.all) { template in
                                        Button { name = template.name; purpose = template.purpose; if colors.contains(template.color) { color = template.color } } label: {
                                            Label(template.name, systemImage: template.symbol).font(.system(size: 12)).padding(.horizontal, 12).padding(.vertical, 7).background(MacTheme.raised, in: Capsule())
                                        }.buttonStyle(.plain).help(template.purpose)
                                    }
                                    Button { if let shared = BotSharing.choose() { name = shared.name; purpose = shared.purpose; if colors.contains(shared.color) { color = shared.color } } else { importNote = "That file is not a shared Bot." } } label: {
                                        Label("Import a shared Bot…", systemImage: "square.and.arrow.down").font(.system(size: 12)).padding(.horizontal, 12).padding(.vertical, 7)
                                            .overlay(Capsule().stroke(MacTheme.secondary.opacity(0.5)))
                                    }.buttonStyle(.plain)
                                }
                            }
                            TextField("What should it help with? (optional)", text: $purpose, axis: .vertical)
                                .textFieldStyle(.plain).lineLimit(2...4).padding(12).background(MacTheme.raised, in: RoundedRectangle(cornerRadius: 12))
                            if let importNote { Text(importNote).font(.system(size: 12)).foregroundStyle(MacTheme.secondary) }
                        }.padding(.top, 8)
                    }.font(.system(size: 13)).foregroundStyle(MacTheme.secondary)
                }.padding(.horizontal, 4)
            }
            HStack {
                Spacer()
                MacPillButton(title: "Cancel") { desktop.panel = nil }
                MacPillButton(title: "Create", prominent: true, action: create).disabled(cleanName.isEmpty)
            }
        }.padding(26).onAppear { nameFocused = true }
    }

    private func create() {
        guard !cleanName.isEmpty else { return }
        if let gateway = desktop.gateway {
            let remoteColor = ["white", "purple", "pink", "ochre"].contains(color) ? color : "purple"
            Task { if await gateway.create(name: cleanName, purpose: purpose, color: remoteColor) { desktop.selectedID = nil; desktop.panel = nil } }
        } else if app.addBot(name: cleanName, purpose: purpose, color: color) {
            if let created = app.workspace.bots.last(where: { $0.name == cleanName }) { _ = app.setAppearance(BotAppearance(shape: shape, color: color), for: created) }
            desktop.selectedID = app.workspace.bots.last?.id
            desktop.panel = nil
        } else { importNote = "Use a name no other Bot has."; showTemplates = true }
    }
}
