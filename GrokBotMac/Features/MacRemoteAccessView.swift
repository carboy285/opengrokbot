import SwiftUI
import AppKit

struct MacRemoteAccessView: View {
    @ObservedObject var remote: MacRemoteHost
    var body: some View {
        VStack(alignment:.leading,spacing:20) {
            Text("iPhone remote control").font(.system(size:20,weight:.medium))
            Text("Sign in on both devices. Your iPhone controls this Mac’s Bots, chats and models wherever you go.").foregroundStyle(MacTheme.secondary)
            CloudSignInView(account:remote.account)
            if let notice = remote.pinSyncNotice { Text(notice).font(.caption).foregroundStyle(.secondary) }
            Label(remote.connectionState, systemImage: remote.enabled ? "antenna.radiowaves.left.and.right" : "iphone.slash").font(.headline)
            if remote.account.signedIn {
                Toggle("Allow phone access",isOn:Binding(get:{remote.enabled},set: { $0 ? remote.start():remote.stop() }))
                    .accessibilityIdentifier("remote-access-toggle")
                if let local = remote.account.localDevice {
                    Text("This Mac · " + local.fingerprint).font(.system(.caption,design:.monospaced)).textSelection(.enabled)
                }
                Text("Your devices").font(.headline)
                if remote.account.controllers.isEmpty { Text("Sign in on your iPhone to make it appear here.").foregroundStyle(.secondary) }
                ForEach(remote.account.controllers) { phone in
                    HStack {
                        VStack(alignment:.leading,spacing:5) {
                            Label(phone.name,systemImage:"iphone")
                            Text(phone.fingerprint).font(.system(.caption,design:.monospaced)).textSelection(.enabled)
                            Text(remote.account.approved(phone) ? "Approved":"Compare this fingerprint with the phone before approving.").font(.caption).foregroundStyle(.secondary)
                        }; Spacer()
                        Button(remote.account.approved(phone) ? "Revoke":"Approve device") { remote.approve(phone,allowed:!remote.account.approved(phone)) }
                    }.padding(.vertical,8)
                }
                if let feedback = remote.feedback { Text(feedback).font(.callout).foregroundStyle(.secondary) }
                HStack {
                    Button("Reconnect now") { remote.reconnect() }
                    Button("Copy diagnostics") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(remote.diagnostics, forType: .string) }
                }
                if let date = remote.lastHeartbeat { Text("Last reached the account service \(date.formatted(date: .omitted, time: .standard)).").font(.caption).foregroundStyle(.secondary) }
            }
            Text("Keep this Mac awake with OpenGrokBot running. Work continues if the phone disconnects. Commands and replies are encrypted between approved devices; Supabase relays them temporarily.").font(.callout).foregroundStyle(MacTheme.secondary)
        }
    }
}
