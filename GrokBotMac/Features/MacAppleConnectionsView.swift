import SwiftUI

/// Mac-only page: which Apple apps your Bots may look at. Everything starts off.
struct MacAppleConnectionsView: View {
    @EnvironmentObject private var desktop: MacAppModel
    @ObservedObject private var apple = AppleConnections.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 12) {
                Button { desktop.panel = .apps } label: { Image(systemName: "chevron.left").frame(width: 38, height: 38) }
                    .buttonStyle(.plain).accessibilityLabel("Back to Connect Apps")
                Text("Apple Connections").font(.system(size: 25, weight: .medium))
                Spacer()
                Button { desktop.panel = nil } label: { Image(systemName: "xmark").frame(width: 38, height: 38) }
                    .buttonStyle(.plain).accessibilityLabel("Close Apple Connections")
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Let your Bots look at your Apple apps").font(.system(size: 18, weight: .medium))
                        Text("Each app is off until you turn it on, and macOS asks you to allow it. Turn an app off at any time. Bots can read what you enable, and can add calendar events or reminders only after you approve each one. They cannot send messages or email, or delete anything.")
                            .font(.system(size: 14)).lineSpacing(4).foregroundStyle(MacTheme.secondary)
                        Text("What a Bot reads becomes part of its conversation and is sent to the AI provider you chose for that Bot, like anything else you type. Turn on only what you are comfortable sharing with that provider.")
                            .font(.system(size: 13)).lineSpacing(4).foregroundStyle(.orange)
                    }.padding(20).frame(maxWidth: .infinity, alignment: .leading).background(MacTheme.raised, in: RoundedRectangle(cornerRadius: 16))
                    ForEach(AppleService.allCases) { service in row(service) }
                }.frame(maxWidth: 780, alignment: .leading).padding(.vertical, 6).frame(maxWidth: .infinity)
            }
        }.padding(36).onAppear { apple.refreshAccess() }
    }

    private func row(_ service: AppleService) -> some View {
        let on = apple.isEnabled(service)
        let status = apple.access[service] ?? .notDetermined
        return HStack(alignment: .top, spacing: 14) {
            Image(systemName: service.symbol).font(.system(size: 18)).frame(width: 42, height: 42)
                .background(MacTheme.panel, in: RoundedRectangle(cornerRadius: 11))
            VStack(alignment: .leading, spacing: 5) {
                Text(service.title).font(.system(size: 16, weight: .medium))
                Text(service.summary).font(.system(size: 13)).lineSpacing(3).foregroundStyle(MacTheme.secondary)
                if on { statusLine(service, status) }
            }
            Spacer(minLength: 12)
            Toggle(service.title, isOn: Binding(get: { apple.isEnabled(service) }, set: { apple.setEnabled(service, $0) }))
                .labelsHidden().toggleStyle(.switch).accessibilityLabel("Let Bots use \(service.title)")
        }.padding(18).background(MacTheme.raised, in: RoundedRectangle(cornerRadius: 16))
    }

    @ViewBuilder private func statusLine(_ service: AppleService, _ status: AppleAccess) -> some View {
        HStack(spacing: 10) {
            Image(systemName: status == .granted ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .foregroundStyle(status == .granted ? Color.green : Color.orange)
            Text(statusText(service, status)).font(.system(size: 12)).foregroundStyle(MacTheme.secondary)
            if status != .granted, status != .unavailable {
                MacPillButton(title: service == .messages ? "Open Full Disk Access" : "Allow access") { Task { await apple.requestAccess(service) } }
            }
        }
    }

    private func statusText(_ service: AppleService, _ status: AppleAccess) -> String {
        if (service == .mail || service == .notes), status == .notDetermined { return "macOS asks the first time a Bot uses it" }
        return status.label
    }
}
