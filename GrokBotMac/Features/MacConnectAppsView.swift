import SwiftUI

struct MacConnectAppsView: View {
    @EnvironmentObject private var desktop: MacAppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack {
                Text("Connect Apps").font(.system(size: 25, weight: .medium))
                Spacer()
                Button { desktop.panel = nil } label: { Image(systemName: "xmark").frame(width: 38, height: 38) }.buttonStyle(.plain).accessibilityLabel("Close Connect Apps")
            }
            ScrollView { MacComposioSetupView(service: desktop.composio).frame(maxWidth: 780, alignment: .leading).padding(.vertical, 15).frame(maxWidth: .infinity) }
        }.padding(36)
    }
}
