import AppKit
import SwiftUI

@MainActor
final class ComposioModel: ObservableObject {
    @Published var configured = false
    @Published var busy = false
    @Published var feedback: String?
    @Published var toolkits: [ComposioToolkit] = []
    @Published var selected: Set<String> = []
    private let store = KeychainSecretStore(service: "org.opengrokbot.composio")
    private var session: ComposioSession?
    private var key: String?
    private var generation = 0
    var connectedCount: Int { toolkits.filter(\.connected).count }
    static let choices: [(slug: String, name: String)] = [("github","GitHub"),("gmail","Gmail"),("googledrive","Google Drive"),("googlecalendar","Google Calendar"),("slack","Slack"),("notion","Notion"),("linear","Linear"),("figma","Figma")]

    init() {
        do {
            if let data = try store.read(account: "configuration") {
                let value = try JSONDecoder().decode(Configuration.self, from: data)
                guard ComposioClient.trustedURL(value.session.mcp.url) != nil else { throw ComposioError.invalidResponse }
                key = value.key; session = value.session; selected = Set(value.toolkits); configured = true
            }
        } catch { feedback = "Composio configuration could not be read from Keychain. Unlock your Mac and reopen Connect Apps." }
    }
    private struct Configuration: Codable { let key: String; let session: ComposioSession; let toolkits: [String] }
    private func client(_ key: String) -> ComposioClient { ComposioClient(key: key) }

    func connect(projectKey: String) {
        let clean = projectKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !busy, !clean.isEmpty, clean.count < 4096, !clean.contains(where: { $0.isWhitespace || $0.isNewline }), !selected.isEmpty else { feedback = "Enter a project key and choose at least one tool."; return }
        busy = true; feedback = nil
        let requested = selected.sorted(), requestGeneration = generation
        var userID = UserDefaults.standard.string(forKey: "composioUserID")
        if userID == nil { userID = "opengrokbot-" + UUID().uuidString; UserDefaults.standard.set(userID, forKey: "composioUserID") }
        let identity = userID!
        Task {
            defer { busy = false }
            do {
                let created = try await client(clean).create(userID: identity, toolkits: requested)
                guard generation == requestGeneration else { return }
                do { try store.save(JSONEncoder().encode(Configuration(key: clean, session: created, toolkits: requested)), account: "configuration") }
                catch { throw ComposioError.storage }
                key = clean; session = created; configured = true
                toolkits = try await client(clean).toolkits(sessionID: created.session_id)
                feedback = "Project connected. Authorize the apps you want below, then refresh after returning from your browser."
            } catch { feedback = Self.message(error) }
        }
    }
    func refresh() {
        guard !busy, let key, let session else { return }
        busy = true; feedback = nil
        let requestGeneration = generation
        Task {
            defer { busy = false }
            do { let items = try await client(key).toolkits(sessionID: session.session_id); guard generation == requestGeneration else { return }; toolkits = items }
            catch { feedback = Self.message(error) }
        }
    }
    func authorize(_ toolkit: ComposioToolkit) {
        guard !busy, let key, let session, toolkit.enabled else { return }
        busy = true; feedback = nil
        let requestGeneration = generation
        Task {
            defer { busy = false }
            do {
                let url = try await client(key).link(sessionID: session.session_id, toolkit: toolkit.slug)
                guard generation == requestGeneration else { return }
                NSWorkspace.shared.open(url)
                feedback = "Finish authorizing \(toolkit.name) in your browser, then select Refresh connections."
            } catch { feedback = Self.message(error) }
        }
    }
    func disconnect() {
        guard !busy else { return }
        do { try store.delete(account: "configuration"); generation += 1; key = nil; session = nil; configured = false; toolkits = []; feedback = "Project removed from this Mac. To revoke connected accounts, use your Composio dashboard." }
        catch { feedback = Self.message(error) }
    }
    /// Only a session capability reaches the CLI, never the project-wide key.
    func mcpURL() throws -> String? {
        guard configured else { return nil }
        guard let session, ComposioClient.trustedURL(session.mcp.url) != nil else { throw ComposioError.missing }
        return session.mcp.url
    }
    static func message(_ error: Error) -> String {
        (error as? ComposioError)?.errorDescription ?? "Composio could not be reached. Check your connection and try again."
    }
}
