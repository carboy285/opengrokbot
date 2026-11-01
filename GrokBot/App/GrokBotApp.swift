import SwiftUI

@main
struct GrokBotApp: App {
    @StateObject private var model = AppModel()
    @StateObject private var remote = RemoteController()
    @Environment(\.scenePhase) private var phase
    @AppStorage("appearance") private var appearance = "system"

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model).environmentObject(remote)
                .onAppear { remote.attach(model) }
                .onOpenURL { remote.receive($0) }
                .onChange(of: phase) { _, phase in remote.setActive(phase == .active) }
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
