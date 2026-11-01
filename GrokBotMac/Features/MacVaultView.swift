import AppKit
import SwiftUI

private struct VaultItem: Identifiable, Codable {
    let id: UUID
    let title: String
}

struct MacVaultView: View {
    @State private var items: [VaultItem] = []
    @State private var title = ""
    @State private var secret = ""
    @State private var feedback: String?
    @State private var revealed: UUID?
    @State private var revealedText = ""
    @State private var deleting: VaultItem?
    private let keychain = KeychainSecretStore(service: "org.opengrokbot.mac.device-vault")
    private let metadataKey = "macVaultItemIndex"

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(spacing: 14) {
                Image(systemName: "lock.square").font(.system(size: 34, weight: .light)).foregroundStyle(MacTheme.secondary)
                VStack(alignment: .leading, spacing: 7) {
                    Text("Device vault").font(.system(size: 23, weight: .medium))
                    Text("Secure notes on this Mac").foregroundStyle(MacTheme.secondary)
                }
            }
            Text("Values are stored in your macOS Keychain. This is a local vault: Grok Bot cannot access it, and nothing is synced to its cloud Vault.")
                .font(.system(size: 14)).lineSpacing(5).foregroundStyle(MacTheme.secondary)
            if items.isEmpty {
                HStack(spacing: 12) {
                    Image(systemName: "key").font(.system(size: 24)).foregroundStyle(MacTheme.secondary)
                    Text("No secure notes yet").foregroundStyle(MacTheme.secondary)
                }.frame(maxWidth: .infinity, alignment: .leading).padding(24).background(MacTheme.panel, in: RoundedRectangle(cornerRadius: 17))
            } else {
                VStack(spacing: 1) {
                    ForEach(items) { item in
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(spacing: 12) {
                                Image(systemName: "key.fill").foregroundStyle(MacTheme.secondary)
                                Text(item.title).font(.system(size: 16))
                                Spacer()
                                Button(revealed == item.id ? "Hide" : "Reveal") { toggleReveal(item) }.buttonStyle(.link)
                                Button { deleting = item } label: { Image(systemName: "trash").frame(width: 28, height: 28) }.buttonStyle(.plain).help("Delete secure note")
                            }
                            if revealed == item.id {
                                Text(revealedText).font(.system(.body, design: .monospaced)).textSelection(.enabled)
                                    .privacySensitive().padding(12).frame(maxWidth: .infinity, alignment: .leading)
                                    .background(MacTheme.raised, in: RoundedRectangle(cornerRadius: 10))
                            }
                        }.padding(18).background(MacTheme.panel)
                    }
                }.clipShape(RoundedRectangle(cornerRadius: 17))
            }
            VStack(alignment: .leading, spacing: 14) {
                Text("Add a secure note").font(.system(size: 17, weight: .medium))
                TextField("Label (visible in the local index)", text: $title).textFieldStyle(.roundedBorder)
                SecureField("Secret value", text: $secret).textFieldStyle(.roundedBorder).privacySensitive()
                HStack {
                    Text("Device only · Not shared with Bots").font(.system(size: 11)).foregroundStyle(MacTheme.secondary)
                    Spacer()
                    MacPillButton(title: "Save to Keychain", prominent: true) { save() }
                        .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || secret.isEmpty)
                }
            }.padding(20).background(MacTheme.panel, in: RoundedRectangle(cornerRadius: 17))
            if let feedback { Text(feedback).font(.system(size: 13)).foregroundStyle(MacTheme.secondary) }
        }
        .onAppear { loadIndex() }
        .onDisappear { revealed = nil; revealedText = ""; secret = "" }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in revealed = nil; revealedText = ""; secret = "" }
        .confirmationDialog("Delete this secure note from the Mac’s Keychain?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            Button("Delete secure note", role: .destructive) { if let item = deleting { remove(item) }; deleting = nil }
        }
    }

    private func loadIndex() {
        guard let data = UserDefaults.standard.data(forKey: metadataKey) else { return }
        do { items = try JSONDecoder().decode([VaultItem].self, from: data) }
        catch { feedback = "The local vault index could not be read. Existing Keychain items were not changed." }
    }

    private func persistIndex() {
        if let data = try? JSONEncoder().encode(items) { UserDefaults.standard.set(data, forKey: metadataKey) }
    }

    private func save() {
        let item = VaultItem(id: UUID(), title: title.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !item.title.isEmpty, !secret.isEmpty else { return }
        do {
            try keychain.save(Data(secret.utf8), account: item.id.uuidString)
            items.append(item)
            persistIndex()
            title = ""; secret = ""
            feedback = "Saved in this Mac’s Keychain. No Bot has access."
        } catch { feedback = "The Keychain could not save this note. Unlock your Mac and try again." }
    }

    private func toggleReveal(_ item: VaultItem) {
        if revealed == item.id { revealed = nil; revealedText = ""; return }
        do {
            guard let data = try keychain.read(account: item.id.uuidString), let value = String(data: data, encoding: .utf8) else {
                feedback = "This item could not be found in the Keychain."; return
            }
            revealedText = value; revealed = item.id
        } catch { feedback = "The Keychain is unavailable. Unlock your Mac and try again." }
    }

    private func remove(_ item: VaultItem) {
        do {
            try keychain.delete(account: item.id.uuidString)
            items.removeAll { $0.id == item.id }
            persistIndex()
            if revealed == item.id { revealed = nil; revealedText = "" }
            feedback = "Secure note deleted."
        } catch { feedback = "The Keychain could not delete this note. Try again after unlocking your Mac." }
    }
}
