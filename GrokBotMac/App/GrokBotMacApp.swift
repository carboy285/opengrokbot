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
                    desktop.remote.attach(app: app, desktop: desktop)
                    desktop.selectFirst(in: app)
                    desktop.refreshCLIs()
                    #if DEBUG
                    if let setup = ProcessInfo.processInfo.environment["OPENGROKBOT_TEST_SETUP"] ?? WorkspaceStore.testArgument("--opengrokbot-test-setup") { desktop.panel = setup == "1" ? .setup : nil }
                    else if !UserDefaults.standard.bool(forKey: "localCLISetupComplete") { desktop.panel = .setup }
                    #else
                    if !UserDefaults.standard.bool(forKey: "localCLISetupComplete") { desktop.panel = .setup }
                    #endif
                }
                .onOpenURL { url in
                    if url.scheme == "opengrokbot", url.host == "auth" { desktop.openSettings(.computer) }
                }
                .onChange(of: desktop.installedCLIs) { _, _ in desktop.deliverQueuedMessages(app: app) }
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in desktop.stopAll(immediately: true) }
                .alert("Couldn’t complete that action", isPresented: Binding(get: { app.errorMessage != nil }, set: { if !$0 { app.errorMessage = nil } })) {
                    Button("OK") { app.errorMessage = nil }
                } message: { Text(app.errorMessage ?? "") }
        }
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unifiedCompact)
        .defaultSize(width: 1370, height: 940)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Bot…") { desktop.panel = .newBot }.keyboardShortcut("n")
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
