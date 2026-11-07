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

/// "Ask a Bot": sends a request to one of your Bots by name (blank means your main Bot) and opens the chat.
/// Works from Siri, the Shortcuts app, the Action Button, and the share sheet in Shortcuts.
struct AskBotIntent: AppIntent {
    static var title: LocalizedStringResource { "Ask a Bot" }
    static var description: IntentDescription { IntentDescription("Sends a request to one of your OpenGrokBot Bots and opens the chat.") }
    static var openAppWhenRun: Bool { true }

    @Parameter(title: "Request") var request: String
    @Parameter(title: "Bot name", description: "Leave blank for your main Bot.") var botName: String?

    static var parameterSummary: some ParameterSummary { Summary("Ask \(\.$botName) \(\.$request)") }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let text = String(request.trimmingCharacters(in: .whitespacesAndNewlines).prefix(8000))
        guard !text.isEmpty else { return .result(dialog: "There was nothing to send.") }
        UserDefaults.standard.set(text, forKey: "pendingAskText")
        UserDefaults.standard.set(String((botName ?? "").trimmingCharacters(in: .whitespacesAndNewlines).prefix(80)), forKey: "pendingAskBot")
        return .result(dialog: "Sending that to your Bot.")
    }
}

struct OpenGrokBotShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: AskBotIntent(),
                    phrases: ["Ask \(.applicationName)", "Ask my Bot in \(.applicationName)"],
                    shortTitle: "Ask a Bot",
                    systemImageName: "text.bubble")
        AppShortcut(intent: StartVoiceIntent(),
                    phrases: ["Talk to \(.applicationName)", "Start voice mode in \(.applicationName)"],
                    shortTitle: "Talk to Bot",
                    systemImageName: "waveform")
    }
}
