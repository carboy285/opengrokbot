import SwiftUI

struct MacIntegrationView: View {
    @EnvironmentObject private var desktop: MacAppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 25) {
            HStack {
                Text("Local AI").font(.system(size: 27, weight: .medium))
                Spacer()
                Button { desktop.panel = nil; desktop.importFeedback = nil } label: { Image(systemName: "xmark").frame(width: 34, height: 34) }.buttonStyle(.plain)
            }
            Spacer()
            MacBotAvatar(size: 72)
            Text(desktop.statusText).font(.system(size: 24, weight: .medium))
            Text(desktop.importFeedback ?? "Messages go to the AI CLI installed on this Mac. It uses its own login, model, and permission settings. OpenGrokBot is free; provider usage and limits follow your CLI account.")
                .font(.system(size: 18)).lineSpacing(6)
            ForEach(desktop.installedCLIs) { cli in
                HStack { Label(cli.provider.name, systemImage: "terminal"); Spacer(); Text(cli.version).foregroundStyle(MacTheme.secondary) }
            }
            HStack {
                MacPillButton(title: "Open setup", prominent: true) { desktop.panel = .setup }
                MacPillButton(title: "Scan again") { desktop.refreshCLIs() }.disabled(desktop.scanningCLIs)
            }
            Spacer()
        }.padding(42)
    }
}
