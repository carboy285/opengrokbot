import Foundation
import SwiftUI

@MainActor
final class RemoteController: ObservableObject {
    @Published private(set) var online = false
    @Published private(set) var hasSnapshot = false
    @Published private(set) var hostName = "Desktop"
    @Published private(set) var status = "Connect your desktop"
    @Published private(set) var running: Set<UUID> = []
    @Published private(set) var providers: [RemoteProvider] = []
    @Published private(set) var defaultProvider: CLIProvider?
    @Published var showPairing = false
    @Published var pairingDraft = ""
    @Published var busy = false
    @Published var drafts: [UUID:String] = [:]
    @Published var error: String?
    private let client: RemoteHTTPClient
    private let secrets: KeychainSecretStore
    private var connection: RemotePairing?
    private var polling: Task<Void,Never>?
    private var revision: String?
    private var sequence = 0
    private var appliedSequence = 0
    private weak var model: AppModel?
    private var pendingSends: [UUID:(String,UUID)] = [:]

    init(client: RemoteHTTPClient = RemoteHTTPClient(), secrets: KeychainSecretStore = KeychainSecretStore(service: "org.opengrokbot.ios.remote")) { self.client = client; self.secrets = secrets }

    func attach(_ model: AppModel) {
        guard self.model == nil else { return }; self.model = model
        do {
            if let data = try secrets.read(account: "desktop") {
                connection = try JSONDecoder().decode(RemotePairing.self, from: data)
                startPolling()
            }
        } catch { status = "Unlock this iPhone to restore the desktop connection." }
    }
    func receive(_ url: URL) { pairingDraft = url.absoluteString; showPairing = true }
    func connect(link: String) async {
        busy = true; defer { busy = false }
        do {
            let pairing = try RemotePairing(link: link.trimmingCharacters(in: .whitespacesAndNewlines))
            guard let snapshot = try await client.snapshot(pairing, since: nil) else { throw RemoteError.incompatible }
            try secrets.save(JSONEncoder().encode(pairing), account: "desktop")
            polling?.cancel(); connection = pairing; revision = nil; sequence = 0; appliedSequence = 0
            apply(snapshot); showPairing = false; pairingDraft = ""; error = nil
            startPolling()
        } catch { self.error = message(error) }
    }
    func disconnect() {
        polling?.cancel(); polling = nil; connection = nil; revision = nil
        online = false; hasSnapshot = false; running = []; providers = []
        model?.applyRemoteSnapshot(Workspace()); model?.leavePreview()
        try? secrets.delete(account: "desktop"); status = "Connect your desktop"
    }
    func setActive(_ active: Bool) {
        if active { if connection != nil { startPolling() } }
        else { polling?.cancel(); polling = nil; online = false }
    }
    private func startPolling() {
        polling?.cancel()
        guard connection != nil else { return }
        polling = Task {
            var failures = 0
            while !Task.isCancelled {
                do { try await refresh(); failures = 0 }
                catch {
                    if Task.isCancelled { return }
                    online = false; failures += 1; status = message(error)
                    if case RemoteError.unauthorized = error { showPairing = true; return }
                }
                try? await Task.sleep(for: .milliseconds(failures == 0 ? 700 : min(15000, failures * 2000)))
            }
        }
    }
    private func refresh(force: Bool = false) async throws {
        guard let pairing = connection else { return }
        sequence += 1; let request = sequence
        let result = try await client.snapshot(pairing, since: force ? nil : revision)
        try Task.checkCancellation()
        guard connection == pairing, request >= appliedSequence else { return }
        appliedSequence = request
        if let result { apply(result) }
        online = true; status = "Connected to \(hostName)"
    }
    private func apply(_ snapshot: RemoteSnapshot) {
        revision = snapshot.revision; hostName = snapshot.hostName; running = Set(snapshot.running)
        providers = snapshot.providers; defaultProvider = snapshot.defaultProvider
        model?.applyRemoteSnapshot(snapshot.workspace); hasSnapshot = true; online = true; status = "Connected to \(hostName)"
    }
    @discardableResult
    func command(_ command: RemoteCommand) async -> Bool {
        guard online, let pairing = connection else { error = "Reconnect to your desktop before changing the workspace."; return false }
        do {
            _ = try await client.fetch(pairing, path: "/v1/command", command: command)
            try? await refresh(force: true)
            return true
        } catch { self.error = message(error); return false }
    }
    func send(_ text: String, bot: Bot) async -> Bool {
        let id = pendingSends[bot.id].flatMap { $0.0 == text ? $0.1 : nil } ?? UUID()
        pendingSends[bot.id] = (text,id)
        let accepted = await command(RemoteCommand(requestID: id, action: "send", botID: bot.id, text: text))
        if accepted { pendingSends[bot.id] = nil }; return accepted
    }
    func models(_ provider: CLIProvider) async -> [AvailableCLIModel] {
        guard let pairing = connection, let data = try? await client.fetch(pairing, path: "/v1/models", query: [URLQueryItem(name: "provider", value: provider.rawValue)]) else { return [] }
        return (try? JSONDecoder().decode([AvailableCLIModel].self, from: data)) ?? []
    }
    func files(_ bot: Bot) async -> [RemoteFile] {
        guard let pairing = connection, let data = try? await client.fetch(pairing, path: "/v1/files", query: [URLQueryItem(name: "bot", value: bot.id.uuidString)]) else { return [] }
        return (try? JSONDecoder().decode([RemoteFile].self, from: data)) ?? []
    }
    private func message(_ error: Error) -> String { (error as? RemoteError)?.errorDescription ?? RemoteError.unavailable.errorDescription! }
}
