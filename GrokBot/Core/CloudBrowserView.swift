import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Approved viewers receive a still image, not a desktop-control session.
struct CloudBrowserView: View {
    var isVM = false
    let botID: UUID
    @ObservedObject var remote: RemoteController
    @Environment(\.dismiss) private var dismiss
    @State private var address = "https://duckduckgo.com"
    @State private var preview: RemoteBrowserPreview?
    @State private var feedback = "The browser runs locally on the hosting computer. Refresh to see its current page."
    @State private var busy = false
    @State private var live = true
    var body: some View {
        VStack(spacing: 14) {
            HStack { Text(isVM ? "Bot’s local Linux VM" : "Bot’s local browser").font(.headline); Spacer(); Button("Done") { dismiss() } }
            Text("Hosted on \(remote.hostName). The view refreshes about every three seconds. Keyboard and mouse interaction stays on the host.").font(.caption).foregroundStyle(.secondary)
            HStack {
                if !isVM { TextField("https://example.com", text: $address).textFieldStyle(.roundedBorder) }
                Button(isVM ? "Open VM on host" : "Open browser on host") {
                    busy = true
                    Task { if await remote.command(RemoteCommand(action: isVM ? "open_vm" : "open_browser", botID: botID, text: isVM ? nil : address)) { feedback = "Opened on the host. Refresh after the page loads." }; busy = false }
                }.disabled(busy || !remote.online)
            }
            Toggle("Auto-refresh view", isOn: $live)
            HStack { Button("Refresh now") { refresh() }.disabled(busy || !remote.online); if busy { ProgressView().controlSize(.small) }; Spacer() }
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
                    } else { Text("Open this Bot’s browser or VM on the host, then refresh here.").foregroundStyle(.secondary) }
                }
            }
            Spacer(minLength: 0)
        }.padding(20).frame(minWidth: 300, minHeight: 350).task(id: live) {
            refresh()
            while live && !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(3)); try Task.checkCancellation() } catch { return }
                refresh()
            }
        }
        .onChange(of: remote.hasSnapshot) { _, available in if !available { preview = nil; dismiss() } }
    }
    private func refresh() {
        guard !busy else { return }; busy = true
        Task {
            do { preview = try await remote.browserPreview(botID, vm: isVM); feedback = "View updated." }
            catch { feedback = error.localizedDescription }
            busy = false
        }
    }
}
