import SwiftUI

struct MacIntegrationView: View {
    @EnvironmentObject private var app: AppModel
    @EnvironmentObject private var desktop: MacAppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 26) {
            HStack {
                Text("Connection").font(.system(size: 26, weight: .medium))
                Spacer()
                Button { desktop.panel = nil; desktop.importFeedback = nil } label: { Image(systemName: "xmark").font(.system(size: 19)).frame(width: 34, height: 34) }.buttonStyle(.plain)
            }
            Spacer()
            HStack(spacing: 17) {
                MacBotAvatar(size: 60)
                VStack(alignment: .leading, spacing: 8) {
                    Text("Not connected").font(.system(size: 27, weight: .medium))
                    Text("Your workspace is running locally.").foregroundStyle(MacTheme.secondary)
                }
            }
            Text(desktop.importFeedback ?? "You can create preview Bots, keep local notes, and use the device vault. Messages, example handoffs, and the apps catalog are offline. No task runs or account changes are made in Grok Bot.")
                .font(.system(size: 17)).lineSpacing(6)
            VStack(alignment: .leading, spacing: 12) {
                Label("Real sign-in and service access are not implemented", systemImage: "person.crop.circle.badge.exclamationmark")
                Text("The 0.78.1 installer has not been inspected. Its authentication, transport, streaming, and approval contracts need to be verified before this client can use them.")
                    .foregroundStyle(MacTheme.secondary).lineSpacing(5)
                Text("The project includes scripts/inspect-dmg.sh to inspect your local copy on macOS. A saved server URL or a generic model API key cannot supply the missing Bot protocol.")
                    .font(.system(size: 13)).foregroundStyle(MacTheme.secondary).lineSpacing(4)
            }.padding(22).background(MacTheme.raised, in: RoundedRectangle(cornerRadius: 18))
            HStack {
                Link("Official Grok Bot setup ↗", destination: URL(string: "https://docs.x.ai/grok-bot/get-started")!)
                Spacer()
                MacPillButton(title: "Back to workspace", prominent: true) { desktop.panel = nil; desktop.importFeedback = nil }
            }
            Spacer()
        }.padding(42).frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
