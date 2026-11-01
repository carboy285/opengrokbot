import SwiftUI

struct PairDesktopView: View {
    @EnvironmentObject private var remote: RemoteController
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack { Spacer(); BotAvatar(size: 72); Spacer() }.padding(.vertical)
                    Text("Control your desktop Bots").font(.title2.weight(.medium))
                    Text("Your Mac or Windows app runs the AI. This iPhone opens the same workspace and controls its chats, models and running work.")
                }
                Section("1 · Enable remote access on desktop") {
                    Text("Open Settings → Computer → iPhone remote control in the desktop app. Choose Tailscale, Funnel, Wi-Fi, or your HTTPS proxy, then enable access.")
                    Text("Tailscale private access needs the Tailscale app connected to the same tailnet on both devices. Funnel works over public HTTPS without Tailscale on the phone.").font(.footnote).foregroundStyle(.secondary)
                }
                Section("2 · Paste its pairing link") {
                    TextField("opengrokbot://pair?host=…#…", text: $remote.pairingDraft, axis: .vertical)
                        .textInputAutocapitalization(.never).autocorrectionDisabled().privacySensitive()
                        .accessibilityIdentifier("desktop-pairing-link")
                    Button(remote.busy ? "Connecting…" : "Connect to desktop") { Task { await remote.connect(link: remote.pairingDraft) } }
                        .disabled(remote.busy || remote.pairingDraft.isEmpty).accessibilityIdentifier("connect-desktop")
                } footer: { Text("Pair only with your own desktop. A pairing link is a workspace password. Direct Wi-Fi HTTP is unencrypted; use trusted Wi-Fi, private Tailscale, or HTTPS.") }
                if let error = remote.error { Section { Text(error).foregroundStyle(.secondary) } }
                Section { Text("The host must be awake with OpenGrokBot running. Closing or disconnecting the phone does not stop desktop work.").font(.footnote).foregroundStyle(.secondary) }
            }.navigationTitle("Connect Desktop").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}

struct RemoteConnectionBanner: View {
    @EnvironmentObject private var remote: RemoteController
    var body: some View {
        Button { remote.showPairing = true } label: {
            HStack(spacing: 7) {
                Circle().fill(remote.online ? .green : .orange).frame(width: 5,height: 5)
                Text(remote.status).font(.caption).lineLimit(2)
                Spacer(); Image(systemName: "desktopcomputer")
            }.foregroundStyle(.secondary).padding(.horizontal,20).padding(.vertical,8)
        }.buttonStyle(.plain)
    }
}
