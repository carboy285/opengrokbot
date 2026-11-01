import AppKit
import SwiftUI

struct MacRemoteAccessView: View {
    @ObservedObject var remote: MacRemoteHost
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("iPhone remote control").font(.system(size: 20, weight: .medium))
            Text("Your phone controls this Mac’s Bots, chats, models and running work. No separate phone workspace is created.").foregroundStyle(MacTheme.secondary)
            Picker("Connection", selection: $remote.mode) { ForEach(MacRemoteHost.Mode.allCases) { mode in Text(mode.rawValue).tag(mode) } }
                .disabled(remote.enabled || remote.changing)
                .onChange(of: remote.mode) { _, _ in remote.address = "" }
            if remote.mode == .tailscale {
                Text("Private HTTPS anywhere you go. Install Tailscale on this Mac and your iPhone, sign into the same tailnet, and keep Tailscale connected.").font(.system(size: 13)).foregroundStyle(MacTheme.secondary)
            } else if remote.mode == .funnel {
                Text("Public HTTPS protected by your pairing key. The iPhone does not need Tailscale. Funnel needs authorization in your tailnet; some Mac App Store Tailscale builds do not support it.").font(.system(size: 13)).foregroundStyle(MacTheme.secondary)
            } else if remote.mode == .wifi {
                Text("Use this Mac’s private IP on the same trusted Wi-Fi, or its Tailscale IP. Direct Wi-Fi HTTP is not encrypted. Use Tailscale or an HTTPS proxy when away from home.").font(.system(size: 13)).foregroundStyle(MacTheme.secondary)
            } else {
                Text("Forward your HTTPS proxy to http://127.0.0.1:48291. Enter its public HTTPS base address below.").font(.system(size: 13)).foregroundStyle(MacTheme.secondary)
            }
            HStack {
                Button(remote.enabled ? "Disable remote access" : "Enable remote access") { remote.enabled ? remote.stop() : remote.start() }
                    .disabled(remote.changing).accessibilityIdentifier("remote-access-toggle")
                if remote.changing { ProgressView().controlSize(.small) }
            }
            if remote.enabled {
                TextField("Desktop address, e.g. https://my-mac.tailnet.ts.net:8443", text: $remote.address).textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("remote-host-address")
                HStack {
                    Button("Save address") { remote.saveAddress() }
                    Button("Copy pairing link") { remote.copyLink() }.disabled(remote.pairing == nil).accessibilityIdentifier("remote-copy-link")
                    Button("Revoke phones / new key") { remote.rotateKey() }
                }
                if remote.mode == .tailscale || remote.mode == .funnel {
                    Text(remote.serveCommand).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                    HStack {
                        Button("Set up Tailscale") { remote.configureTailscale() }.disabled(remote.changing)
                        Button("Copy command") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(remote.serveCommand, forType: .string) }
                    }
                }
                Text("Open the pairing link on your iPhone, or paste it into Connect Desktop in the iOS app. The link controls this workspace; share it only with your own devices.").font(.system(size: 13)).foregroundStyle(MacTheme.secondary)
            }
            if let feedback = remote.feedback { Text(feedback).font(.system(size: 13)).foregroundStyle(MacTheme.secondary).textSelection(.enabled) }
            Text("Keep this Mac awake and OpenGrokBot running. Work continues when the phone disconnects. Quitting the desktop app stops the host.").font(.system(size: 13)).foregroundStyle(MacTheme.secondary)
            Link("Tailscale installation and setup", destination: URL(string: "https://tailscale.com/download")!)
        }
    }
}
