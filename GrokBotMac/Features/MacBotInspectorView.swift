import AppKit
import SwiftUI

private enum BotInspectorTab: String, CaseIterable, Identifiable {
    case details = "Details", library = "Library", computer = "Computer"
    var id: String { rawValue }
}

/// A persistent companion to the conversation, rather than a modal over it.
struct MacBotInspectorView: View {
    let bot: Bot
    @EnvironmentObject private var app: AppModel
    @EnvironmentObject private var desktop: MacAppModel
    @State private var tab = BotInspectorTab.details
    @State private var files: [URL] = []
    @State private var fileError: String?

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Spacer()
                ShareLink(item: desktop.conversationText(for: bot, app: app)) {
                    Image(systemName: "square.and.arrow.up").font(.system(size: 19))
                        .frame(width: 42, height: 42).glassChrome(in: Circle())
                }.buttonStyle(.plain).accessibilityLabel("Share conversation").help("Share conversation")
                MacCircleButton(symbol: "xmark", label: "Close bot details") { desktop.showBotInspector = false }
            }.padding(18)
            ScrollView {
                VStack(spacing: 0) {
                    MacBotAvatar(color: bot.color, size: 86).padding(.top, 14)
                    Text(bot.name).font(.system(size: 24, weight: .medium))
                        .multilineTextAlignment(.center).textSelection(.enabled)
                        .padding(.horizontal, 24).padding(.top, 30)
                    HStack(spacing: 4) {
                        ForEach(BotInspectorTab.allCases) { item in
                            Button { tab = item; if item == .library { refreshFiles() } } label: {
                                Text(item.rawValue).font(.system(size: 16))
                                    .foregroundStyle(tab == item ? Color.primary : MacTheme.secondary)
                                    .padding(.horizontal, 13).padding(.vertical, 9)
                                    .background(tab == item ? MacTheme.panel : .clear, in: Capsule())
                            }.buttonStyle(.plain)
                                .accessibilityIdentifier("bot-inspector-tab-\(item.rawValue.lowercased())")
                                .accessibilityAddTraits(tab == item ? [.isSelected] : [])
                        }
                    }.padding(.top, 30).padding(.bottom, 46)
                    switch tab {
                    case .details: details
                    case .library: library
                    case .computer: computer
                    }
                }.frame(maxWidth: .infinity).padding(.bottom, 30)
            }
        }
        .frame(maxHeight: .infinity).background(MacTheme.canvas)
        .accessibilityIdentifier("bot-inspector")
        .onChange(of: desktop.runningBots) { _, running in if !running.contains(bot.id), tab == .library { refreshFiles() } }
    }

    private var details: some View {
        VStack(spacing: 28) {
            MacBotProviderSettingsView(bot: bot)
            if bot.isMain != true, !bot.purpose.isEmpty {
                Text(bot.purpose).font(.system(size: 16)).textSelection(.enabled)
            }
            Text("This Bot has no scheduled routines.")
                .font(.system(size: 17)).foregroundStyle(MacTheme.secondary)
        }.multilineTextAlignment(.center).padding(.horizontal, 34).padding(.top, 7)
    }

    private var library: some View {
        VStack(spacing: 18) {
            if files.isEmpty {
                Image(systemName: "doc.text").font(.system(size: 30, weight: .light)).foregroundStyle(MacTheme.secondary)
                Text("No files yet").font(.system(size: 18, weight: .medium))
                Text("Files created in this Bot’s working folder appear here.")
                    .font(.system(size: 14)).foregroundStyle(MacTheme.secondary).multilineTextAlignment(.center)
            } else {
                ForEach(files, id: \.path) { file in
                    Button { NSWorkspace.shared.activateFileViewerSelecting([file]) } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "doc.text").font(.system(size: 22))
                            Text(file.lastPathComponent).font(.system(size: 14)).lineLimit(2).multilineTextAlignment(.leading)
                            Spacer()
                            Image(systemName: "arrow.up.right").foregroundStyle(MacTheme.secondary)
                        }.padding(15).background(MacTheme.panel, in: RoundedRectangle(cornerRadius: 14))
                    }.buttonStyle(.plain).help("Show \(file.lastPathComponent) in Finder")
                }
            }
            if let fileError { Text(fileError).font(.caption).foregroundStyle(MacTheme.secondary) }
            HStack {
                Button("Refresh") { refreshFiles() }
                Button("Open folder") { desktop.openWorkingDirectory(for: bot) }
            }.controlSize(.small).padding(.top, 6)
        }.padding(.horizontal, 28)
    }

    private var computer: some View {
        VStack(spacing: 18) {
            Image(systemName: "desktopcomputer").font(.system(size: 34, weight: .light)).foregroundStyle(MacTheme.secondary)
            Text("Runs on this Mac").font(.system(size: 18, weight: .medium))
            if let cli = desktop.selectedCLI {
                Label(cli.provider.name, systemImage: "terminal").font(.system(size: 15))
                Text(desktop.runningBots.contains(bot.id) ? "Working…" : "Ready").font(.system(size: 13)).foregroundStyle(MacTheme.secondary)
            } else {
                Text("Choose an AI CLI to start chatting.").font(.system(size: 14)).foregroundStyle(MacTheme.secondary)
            }
            Text("Each Bot keeps its own working folder on this Mac.")
                .font(.system(size: 14)).foregroundStyle(MacTheme.secondary).multilineTextAlignment(.center)
            Button("AI CLI setup") { desktop.panel = .setup }
            Button("Open working folder") { desktop.openWorkingDirectory(for: bot) }
        }.padding(.horizontal, 28)
    }

    private func refreshFiles() {
        let directory = desktop.workingDirectory(for: bot)
        guard FileManager.default.fileExists(atPath: directory.path) else { files = []; fileError = nil; return }
        do {
            files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles])
                .filter { (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true }
                .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
            fileError = nil
        } catch { files = []; fileError = "The files could not be read. Try opening the folder in Finder." }
    }
}
