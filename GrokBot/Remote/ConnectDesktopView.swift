import SwiftUI

struct ConnectDesktopView: View {
    @EnvironmentObject private var remote: RemoteController
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack { Spacer(); BotAvatar(size:72); Spacer() }.padding(.vertical)
                    Text("Your Bots, wherever you go").font(.title2.weight(.medium))
                    Text("Your computer runs the AI. Sign in with the same account on both devices, then approve this phone on your Mac. Your Bots load automatically when one Mac is available.")
                }
                Section { CloudSignInView(account:remote.account) }
                if remote.account.signedIn {
                    if let phone = remote.account.localDevice {
                        Section("This phone’s fingerprint") { Text(phone.fingerprint).font(.system(.body,design:.monospaced)); Text("Match this fingerprint in Mac Settings → Computer before choosing Approve phone.").font(.footnote).foregroundStyle(.secondary) }
                    }
                    Section("Your computers") {
                        if remote.account.hosts.isEmpty { Text("No computers yet. Sign in on your Mac and turn on Allow phone access in Settings → Computer.") }
                        ForEach(remote.account.hosts) { host in
                            Button { remote.select(host) } label: {
                                HStack {
                                    Image(systemName:"desktopcomputer")
                                    VStack(alignment:.leading,spacing:5) { Text(host.name); Text(host.online ? "Online":"Offline · keep the desktop awake").font(.caption).foregroundStyle(.secondary); Text(host.fingerprint).font(.system(.caption,design:.monospaced)).foregroundStyle(.secondary) }
                                    Spacer(); Image(systemName:"chevron.right").foregroundStyle(.secondary)
                                }
                            }.disabled(!host.online)
                        }
                    }
                    Section { Text(remote.status).font(.footnote).foregroundStyle(.secondary) }
                }
                if let error = remote.error { Section { Text(error).foregroundStyle(.red) } }
                Section { Text("Commands and replies are encrypted between devices. Your chats and CLI credentials stay on the computer. Keep it awake with OpenGrokBot running; phone disconnections do not stop its work.").font(.footnote).foregroundStyle(.secondary) }
            }.navigationTitle("Connect Desktop").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement:.confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}
struct RemoteConnectionBanner: View {
    @EnvironmentObject private var remote: RemoteController
    var body: some View {
        Button { remote.showConnection = true } label: {
            HStack(spacing:7) { Circle().fill(remote.online ? .green:.orange).frame(width:5,height:5); Text(remote.status).font(.caption).lineLimit(2); Spacer(); Image(systemName:"desktopcomputer") }.foregroundStyle(.secondary).padding(.horizontal,20).padding(.vertical,8)
        }.buttonStyle(.plain)
    }
}
