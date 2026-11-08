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
    static let choices: [(slug: String, name: String)] = ComposioCatalog.apps.map { ($0.slug, $0.name) }
    /// Apps the current Composio session was actually created with. `selected` may differ while the user is choosing.
    @Published private(set) var applied: Set<String> = []
    var hasPendingChanges: Bool { configured && !selected.isEmpty && selected != applied }

    init() {
        do {
            if let data = try store.read(account: "configuration") {
                let value = try JSONDecoder().decode(Configuration.self, from: data)
                guard ComposioClient.trustedURL(value.session.mcp.url) != nil else { throw ComposioError.invalidResponse }
                key = value.key; session = value.session; selected = Set(value.toolkits); applied = Set(value.toolkits); configured = true
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
        let identity = installationUserID()
        Task {
            defer { busy = false }
            do {
                let created = try await createSession(key: clean, userID: identity, requested: requested)
                guard generation == requestGeneration else { return }
                do { try store.save(JSONEncoder().encode(Configuration(key: clean, session: created.session, toolkits: created.used)), account: "configuration") }
                catch { throw ComposioError.storage }
                key = clean; session = created.session; configured = true; selected = Set(created.used); applied = Set(created.used)
                toolkits = try await client(clean).toolkits(sessionID: created.session.session_id)
                feedback = "Project connected. Authorize the apps you want below, then refresh after returning from your browser." + Self.skippedNote(created.skipped)
            } catch { feedback = Self.message(error) }
        }
    }

    /// Adds or changes apps for an already-connected project with the saved key. Existing authorizations stay.
    func applySelection() {
        guard !busy, configured, let key, !selected.isEmpty else { feedback = "Choose at least one app."; return }
        busy = true; feedback = nil
        let requested = selected.sorted(), requestGeneration = generation, identity = installationUserID()
        Task {
            defer { busy = false }
            do {
                let created = try await createSession(key: key, userID: identity, requested: requested)
                guard generation == requestGeneration else { return }
                do { try store.save(JSONEncoder().encode(Configuration(key: key, session: created.session, toolkits: created.used)), account: "configuration") }
                catch { throw ComposioError.storage }
                session = created.session; selected = Set(created.used); applied = Set(created.used)
                toolkits = try await client(key).toolkits(sessionID: created.session.session_id)
                feedback = "Apps updated. Authorize any new ones below." + Self.skippedNote(created.skipped)
            } catch { feedback = Self.message(error) }
        }
    }

    /// The saved project key and the apps it was set up with, for copying to another computer.
    func exportConfiguration() -> (key: String, toolkits: [String])? {
        guard configured, let key else { return nil }
        return (key, applied.sorted())
    }

    /// Sets up this Mac with a project key and user ID copied from another computer, so both share the same authorized apps.
    /// Returns a short phrase describing the result.
    func adopt(projectKey: String, userID: String, toolkits: [String]) async -> String {
        guard !busy else { return "connectors were not changed (setup is already running here)" }
        UserDefaults.standard.set(userID, forKey: "composioUserID")
        busy = true; feedback = nil
        defer { busy = false }
        let requestGeneration = generation
        do {
            let created = try await createSession(key: projectKey, userID: userID, requested: toolkits.sorted())
            guard generation == requestGeneration else { return "connectors were not changed" }
            do { try store.save(JSONEncoder().encode(Configuration(key: projectKey, session: created.session, toolkits: created.used)), account: "configuration") }
            catch { throw ComposioError.storage }
            key = projectKey; session = created.session; configured = true; selected = Set(created.used); applied = Set(created.used)
            self.toolkits = try await client(projectKey).toolkits(sessionID: created.session.session_id)
            return "connectors (\(created.used.count) apps)"
        } catch { return "connectors could not be set up (\(Self.message(error)))" }
    }

    private func installationUserID() -> String {
        if let existing = UserDefaults.standard.string(forKey: "composioUserID") { return existing }
        let created = "opengrokbot-" + UUID().uuidString
        UserDefaults.standard.set(created, forKey: "composioUserID")
        return created
    }

    /// Composio's own search toolkit is always added to a session so Bots can look things up without opening a browser. It needs no sign-in.
    /// If Composio rejects the request (an app it does not recognize), retry once with only the known-good apps.
    private func createSession(key: String, userID: String, requested: [String]) async throws -> (session: ComposioSession, used: [String], skipped: [String]) {
        let withSearch = requested + (requested.contains(ComposioSearch.toolkit) ? [] : [ComposioSearch.toolkit])
        do { return (try await client(key).create(userID: userID, toolkits: withSearch), requested, []) }
        catch ComposioError.status(let code) where (400...499).contains(code) && ![401, 403, 429].contains(code) {
            do {
                // Maybe only the search toolkit was refused.
                return (try await client(key).create(userID: userID, toolkits: requested), requested, [])
            } catch ComposioError.status(let again) where (400...499).contains(again) && ![401, 403, 429].contains(again) {
                guard let plan = ComposioCatalog.fallback(for: requested) else { throw ComposioError.status(again) }
                return (try await client(key).create(userID: userID, toolkits: plan.use), plan.use, plan.skipped)
            }
        }
    }

    /// Searches the web through Composio. Returns nil when no Composio project is set up here (the caller then falls back to the Bot's browser).
    func webSearch(_ query: String) async throws -> [WebSearchHit]? {
        guard configured, let key else { return nil }
        let identity = installationUserID(), client = client(key)
        do { return try await client.webSearch(query, userID: identity) }
        catch let failure as ComposioSearch.Failure { throw CloudError.message(ComposioSearch.message(failure)) }
    }

    static func skippedNote(_ skipped: [String]) -> String {
        guard !skipped.isEmpty else { return "" }
        let names = skipped.map { ComposioCatalog.app($0)?.name ?? $0 }.joined(separator: ", ")
        return " Composio did not accept: \(names). Those were skipped."
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
        do { try store.delete(account: "configuration"); generation += 1; key = nil; session = nil; configured = false; toolkits = []; applied = []; feedback = "Project removed from this Mac. To revoke connected accounts, use your Composio dashboard." }
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
