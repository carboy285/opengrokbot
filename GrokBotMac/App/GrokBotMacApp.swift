import AppKit
import Combine
import SwiftUI

@main
struct GrokBotMacApp: App {
    @StateObject private var app = AppModel(deferSaves: true)
    @StateObject private var desktop = MacAppModel()
    @AppStorage("macAppearance") private var appearance = "dark"

    var body: some Scene {
        WindowGroup {
            MacWorkspaceView()
                .environmentObject(desktop.gateway?.model ?? app)
                .environmentObject(desktop)
                .preferredColorScheme(appearance == "system" ? nil : (appearance == "dark" ? .dark : .light))
                .frame(minWidth: 860, minHeight: 620)
                .background(MacTheme.canvas)
                .background(WindowConfigurator())
                .onAppear {
                    if !app.previewEnabled { app.enterPreview() }
                    // Open-source voice (Kokoro + Whisper) runs in the Mac app; voice mode finds it here.
                    LocalVoice.backend = MacLocalVoiceEngine.shared
                    // Option-Space anywhere starts voice with the open Bot (or the main one), and stops it again.
                    let model = desktop, workspace = app
                    MacGlobalHotKey.shared.action = {
                        let hub = MacVoiceHub.shared
                        if hub.isOn { hub.stop(); return }
                        NSApp.activate(ignoringOtherApps: true)
                        guard model.gateway == nil, let bot = model.selected(in: workspace) ?? workspace.workspace.bots.first(where: { $0.isMain == true }) ?? workspace.workspace.bots.first else { return }
                        model.selectedID = bot.id
                        hub.start(bot: bot, desktop: model, app: workspace)
                    }
                    MacGlobalHotKey.shared.register()
                    desktop.remote.attach(app: app, desktop: desktop)
                    MacIntentHub.shared.attach(app: app, desktop: desktop)
                    desktop.localApp = app
                    desktop.selectFirst(in: app)
                    desktop.startScheduler(app: app)
                    desktop.refreshCLIs()
                    Task { await desktop.updates.check(automatically: true) }
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
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in desktop.flushDrafts(); desktop.stopAll(immediately: true) }
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in app.flushSaves() }
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in app.flushSaves() }
                // These only refresh status text, so a burst of changes (a heartbeat, a download tick) redraws the app at most once a second.
                .onReceive(desktop.updates.objectWillChange.throttle(for: .seconds(1), scheduler: DispatchQueue.main, latest: true)) { _ in desktop.objectWillChange.send() }
                .onReceive(desktop.remote.objectWillChange.throttle(for: .seconds(1), scheduler: DispatchQueue.main, latest: true)) { _ in desktop.objectWillChange.send() }
                .alert("Allow this device to use your Bots?", isPresented: Binding(
                    get: { desktop.remote.pendingPhoneApproval != nil },
                    set: { if !$0 { desktop.remote.pendingPhoneApproval = nil } }
                ), presenting: desktop.remote.pendingPhoneApproval) { phone in
                    Button("Approve device") { desktop.remote.approve(phone, allowed: true) }
                    Button("Not now", role: .cancel) { desktop.remote.pendingPhoneApproval = nil }
                } message: { phone in
                    Text("\(phone.name) is signed in to your account. Compare this fingerprint with the one shown on the viewing device before approving:\n\n\(phone.fingerprint)\n\nApproval lets this device view your Bots and chats and run work on this Mac.")
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
                Button("New Bot…") { desktop.panel = .newBot }.keyboardShortcut("n")
            }
            CommandGroup(after: .sidebar) {
                Button("Computers…") { desktop.copyingBot = nil; desktop.copyNotice = nil; desktop.panel = .computers }.keyboardShortcut("k", modifiers: [.command, .option])
            }
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") { desktop.openSettings() }.keyboardShortcut(",")
            }
            CommandGroup(after: .textEditing) {
                Button("Search Bots") { desktop.showPalette.toggle() }.keyboardShortcut("f")
                Button("Search Bots and Actions…") { desktop.showPalette = true }.keyboardShortcut("k")
                Button("Next Bot") { desktop.cycleBot(1, app: app) }.keyboardShortcut("]", modifiers: [.command, .shift])
                Button("Previous Bot") { desktop.cycleBot(-1, app: app) }.keyboardShortcut("[", modifiers: [.command, .shift])
                Button("Export Conversation…") {
                    if let bot = desktop.selected(in: app) { desktop.exportConversation(bot, app: app) }
                }.keyboardShortcut("e", modifiers: [.command, .shift])
            }
        }

        MenuBarExtra("OpenGrokBot", systemImage: "sparkles") {
            MacQuickAskView().environmentObject(app).environmentObject(desktop)
        }
        .menuBarExtraStyle(.window)
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
