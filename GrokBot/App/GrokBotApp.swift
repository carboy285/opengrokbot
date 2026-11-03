import AppIntents
import SwiftUI
import UserNotifications

@main
struct GrokBotApp: App {
    @StateObject private var model = AppModel()
    @StateObject private var remote = RemoteController()
    @Environment(\.scenePhase) private var phase
    @AppStorage("appearance") private var appearance = "light"

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model).environmentObject(remote)
                .onAppear { remote.attach(model); UNUserNotificationCenter.current().delegate = NotificationPresenter.shared }
                .onOpenURL { remote.receive($0) }
                .onChange(of: phase) { _, phase in
                    if phase == .active { remote.setActive(true) }
                    else if phase == .background { remote.setActive(false) }
                }
                .sheet(isPresented: $remote.showConnection) { ConnectDesktopView().environmentObject(remote) }
                .alert("Desktop request failed", isPresented: Binding(get: { remote.error != nil && !remote.showConnection }, set: { if !$0 { remote.error = nil } })) { Button("OK") { remote.error = nil } } message: { Text(remote.error ?? "") }
                .preferredColorScheme(appearance == "system" ? nil : (appearance == "dark" ? .dark : .light))
                .tint(.primary)
                .alert("Couldn’t save", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
                    Button("OK") { model.errorMessage = nil }
                } message: { Text(model.errorMessage ?? "") }
        }
    }
}

/// "Talk to OpenGrokBot": opens the app in hands-free voice mode with your main Bot.
/// Add it to the Action Button, Lock Screen or Control Center from the Shortcuts app.
struct StartVoiceIntent: AppIntent {
    static var title: LocalizedStringResource { "Talk to my Bot" }
    static var description: IntentDescription { IntentDescription("Opens OpenGrokBot in hands-free voice mode with your main Bot.") }
    static var openAppWhenRun: Bool { true }

    @MainActor
    func perform() async throws -> some IntentResult {
        UserDefaults.standard.set(true, forKey: "pendingVoiceStart")
        return .result()
    }
}

struct OpenGrokBotShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: StartVoiceIntent(),
                    phrases: ["Talk to \(.applicationName)", "Start voice mode in \(.applicationName)"],
                    shortTitle: "Talk to Bot",
                    systemImageName: "waveform")
    }
}
