import AppKit
import SwiftUI

@main
struct GrokBotMacApp: App {
    @StateObject private var app = AppModel()
    @StateObject private var desktop = MacAppModel()
    @AppStorage("macAppearance") private var appearance = "dark"

    var body: some Scene {
        WindowGroup {
            MacWorkspaceView()
                .environmentObject(app)
                .environmentObject(desktop)
                .preferredColorScheme(appearance == "system" ? nil : (appearance == "dark" ? .dark : .light))
                .frame(minWidth: 860, minHeight: 620)
                .background(MacTheme.canvas)
                .background(WindowConfigurator())
                .onAppear {
                    if !app.previewEnabled { app.enterPreview() }
                    desktop.selectFirst(in: app)
                }
                .alert("Couldn’t complete that action", isPresented: Binding(get: { app.errorMessage != nil }, set: { if !$0 { app.errorMessage = nil } })) {
                    Button("OK") { app.errorMessage = nil }
                } message: { Text(app.errorMessage ?? "") }
        }
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unifiedCompact)
        .defaultSize(width: 1370, height: 940)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Preview Bot…") { desktop.panel = .newBot }.keyboardShortcut("n")
            }
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") { desktop.openSettings() }.keyboardShortcut(",")
            }
            CommandGroup(after: .textEditing) {
                Button("Search Bots") { desktop.showSearch.toggle() }.keyboardShortcut("f")
                Button("Export Conversation…") {
                    if let bot = desktop.selected(in: app) { desktop.exportConversation(bot, app: app) }
                }.keyboardShortcut("e", modifiers: [.command, .shift])
            }
        }
    }
}

private struct WindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        Task { @MainActor [weak view] in
            guard let window = view?.window else { return }
            window.title = "OpenGrokBot"
            window.titlebarAppearsTransparent = true
            window.backgroundColor = NSColor(calibratedWhite: 0.065, alpha: 1)
            window.isMovableByWindowBackground = true
            window.identifier = NSUserInterfaceItemIdentifier("OpenGrokBot.workspace")
        }
        return view
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
}
