import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Approved viewers receive a still image, not a desktop-control session.
struct CloudBrowserView: View {
    let botID: UUID
    @ObservedObject var remote: RemoteController
    @Environment(\.dismiss) private var dismiss
    @State private var address = "https://duckduckgo.com"
    @State private var preview: RemoteBrowserPreview?
    @State private var feedback = "The browser runs locally on the hosting computer. Refresh to see its current page."
    @State private var busy = false
    var body: some View {
        VStack(spacing: 14) {
            HStack { Text("Bot’s local browser").font(.headline); Spacer(); Button("Done") { dismiss() } }
            Text("Visible on \(remote.hostName). This is a page preview; use the browser window on the host to type, click or sign in.").font(.caption).foregroundStyle(.secondary)
            HStack {
                TextField("https://example.com", text: $address).textFieldStyle(.roundedBorder)
                Button("Open on host") {
                    busy = true
                    Task { if await remote.command(RemoteCommand(action: "open_browser", botID: botID, text: address)) { feedback = "Opened on the host. Refresh after the page loads." }; busy = false }
                }.disabled(busy || !remote.online)
            }
            HStack { Button("Refresh preview") { refresh() }.disabled(busy || !remote.online); if busy { ProgressView().controlSize(.small) }; Spacer() }
            Text(feedback).font(.caption).foregroundStyle(.secondary)
            if let preview {
                Text(preview.title).font(.subheadline); Text(preview.url).font(.caption).textSelection(.enabled)
                ScrollView {
                    if let data = preview.imageData {
                        #if os(macOS)
                        if let image = NSImage(data: data) { Image(nsImage: image).resizable().scaledToFit() }
                        #else
                        if let image = UIImage(data: data) { Image(uiImage: image).resizable().scaledToFit() }
                        #endif
                    } else { Text("Open this Bot’s browser on the host, then refresh here.").foregroundStyle(.secondary) }
                }
            }
            Spacer(minLength: 0)
        }.padding(20).frame(minWidth: 300, minHeight: 350).task { refresh() }
    }
    private func refresh() {
        guard !busy else { return }; busy = true
        Task {
            do { preview = try await remote.browserPreview(botID); feedback = "Preview updated. Refresh again to follow changes." }
            catch { feedback = error.localizedDescription }
            busy = false
        }
    }
}
