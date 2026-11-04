#if os(macOS)
import XCTest
@testable import GrokBotMac

final class ComposioMockProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (Int, String))?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let (status, body) = try Self.handler!(request)
            client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: ["Content-Type":"application/json"])!, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(body.utf8)); client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}
final class MacComposioTests: XCTestCase {
    func testProjectSessionAndOAuthUseDocumentedRoutes() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ComposioMockProtocol.self]
        let transport = URLSession(configuration: configuration)
        defer { transport.invalidateAndCancel(); ComposioMockProtocol.handler = nil }
        ComposioMockProtocol.handler = { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "x-api-key"), "test-project-key")
            XCTAssertEqual(request.url?.host, "backend.composio.dev")
            switch request.url!.path {
            case "/api/v3.1/tool_router/session":
                XCTAssertEqual(request.httpMethod, "POST")
                let data: Data
                if let body = request.httpBody { data = body }
                else {
                    let stream = request.httpBodyStream!; stream.open(); defer { stream.close() }
                    var result = Data(), buffer = [UInt8](repeating: 0, count: 4096)
                    while stream.hasBytesAvailable { let n = stream.read(&buffer, maxLength: buffer.count); if n <= 0 { break }; result.append(contentsOf: buffer.prefix(n)) }; data = result
                }
                let body = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String:Any])
                XCTAssertEqual(body["user_id"] as? String, "device-unique-user")
                XCTAssertEqual((body["toolkits"] as? [String:[String]])?["enable"], ["github"])
                return (201, #"{"session_id":"trs_fixture","mcp":{"url":"https://connect.composio.dev/mcp/fixture"}}"#)
            case "/api/v3.1/tool_router/session/trs_fixture/toolkits":
                return (200, #"{"items":[{"slug":"github","name":"GitHub","enabled":true,"is_no_auth":false,"connected_account":{"status":"ACTIVE"}}],"next_cursor":null}"#)
            case "/api/v3.1/tool_router/session/trs_fixture/link":
                return (200, #"{"redirect_url":"https://connect.composio.dev/link/fixture","connected_account_id":"ca_fixture","link_token":"lt_fixture"}"#)
            default: XCTFail("Unexpected route"); return (404,"{}")
            }
        }
        let client = ComposioClient(key: "test-project-key", transport: transport)
        let session = try await client.create(userID: "device-unique-user", toolkits: ["github"])
        let toolkits = try await client.toolkits(sessionID: session.session_id)
        XCTAssertTrue(try XCTUnwrap(toolkits.first).connected)
        let link = try await client.link(sessionID: session.session_id, toolkit: "github")
        XCTAssertEqual(link.host, "connect.composio.dev")
    }
    func testBundledHelperAndAllProviderConfigsKeepCapabilitiesOutOfDiskAndArguments() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let capability = "https://connect.composio.dev/mcp/private-test-capability"
        for provider in CLIProvider.allCases {
            let config = try ComposioCLIConfiguration.make(provider: provider, directory: root, sessionURL: capability)
            defer { config.cleanup() }
            XCTAssertEqual(config.environment["OPENGROKBOT_COMPOSIO_MCP_URL"], capability)
            XCTAssertFalse(config.arguments.joined().contains(capability))
            // JSON's optional escaped slash is invalid in a TOML basic string.
            if provider == .codex { XCTAssertFalse(config.arguments.joined().contains("\\/")) }
            let files = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey])!
            for case let file as URL in files {
                if try file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true {
                    let body = try String(contentsOf: file, encoding: .utf8)
                    XCTAssertFalse(body.contains(capability))
                    if file.pathExtension == "toml" { XCTAssertFalse(body.contains("\\/")) }
                }
            }
            config.cleanup()
        }
    }

    func testRejectsCredentialRedirectAndRedactsServiceErrors() async {
        for url in ["http://connect.composio.dev/x", "https://composio.dev.evil.example/x", "https://user:secret@composio.dev/x", "https://composio.dev:8443/x"] { XCTAssertNil(ComposioClient.trustedURL(url)) }
        let configuration = URLSessionConfiguration.ephemeral; configuration.protocolClasses = [ComposioMockProtocol.self]
        let transport = URLSession(configuration: configuration)
        defer { transport.invalidateAndCancel(); ComposioMockProtocol.handler = nil }
        ComposioMockProtocol.handler = { _ in (401, "secret-project-key must not appear") }
        do { _ = try await ComposioClient(key: "secret-project-key", transport: transport).create(userID: "unique", toolkits: ["github"]); XCTFail("Must fail") }
        catch { XCTAssertFalse(error.localizedDescription.contains("secret-project-key")) }
    }
}

@MainActor
private final class ApprovalLog {
    var items: [(title: String, detail: String, authenticate: Bool)] = []
}

@MainActor
final class MacConnectionsTests: XCTestCase {
    private func uniqueLogins() -> SecureLoginStore {
        SecureLoginStore(store: KeychainSecretStore(service: "org.opengrokbot.tests.logins." + UUID().uuidString))
    }
    private let bot = Bot(id: UUID(), name: "Fantasy", purpose: "Help with my league", color: "white", symbol: "sparkles")

    // MARK: Catalog
    func testCatalogHasUniqueAppsAndSearchesNamesAndCategories() {
        let slugs = ComposioCatalog.apps.map(\.slug)
        XCTAssertEqual(Set(slugs).count, slugs.count)
        XCTAssertTrue(ComposioCatalog.recommended.allSatisfy { ComposioCatalog.app($0) != nil })
        XCTAssertEqual(ComposioModel.choices.count, ComposioCatalog.apps.count)
        XCTAssertEqual(ComposioCatalog.filter(query: "google", category: nil).map(\.slug).sorted(), ["googlecalendar", "googledocs", "googledrive", "googlesheets"])
        XCTAssertEqual(ComposioCatalog.filter(query: "", category: "Design").map(\.slug), ["figma", "canva", "miro"])
        XCTAssertEqual(ComposioCatalog.filter(query: "git", category: "Code").map(\.slug), ["github", "gitlab"])
        XCTAssertTrue(ComposioCatalog.filter(query: "zzz", category: nil).isEmpty)
        for original in ["github", "gmail", "googledrive", "googlecalendar", "slack", "notion", "linear", "figma"] { XCTAssertTrue(ComposioCatalog.verifiedSlugs.contains(original)) }
    }

    func testRejectedAppsFallBackToKnownGoodOnes() {
        let plan = ComposioCatalog.fallback(for: ["github", "jira", "figma"])
        XCTAssertEqual(plan?.use, ["github", "figma"])
        XCTAssertEqual(plan?.skipped, ["jira"])
        XCTAssertNil(ComposioCatalog.fallback(for: ["github", "figma"]), "Nothing to drop, so no retry")
        XCTAssertNil(ComposioCatalog.fallback(for: ["jira"]), "Nothing known-good to retry with")
        XCTAssertTrue(ComposioModel.skippedNote(["jira"]).contains("Jira"))
        XCTAssertEqual(ComposioModel.skippedNote([]), "")
    }

    // MARK: Pure text helpers
    func testAttributedBodyDecodingAndTextHelpers() {
        var blob = Data("junk NSString".utf8); blob.append(contentsOf: [0x01, 0x94, 0x84, 0x01, 0x2b, 5]); blob.append(Data("hello".utf8))
        XCTAssertEqual(AppleText.decodeAttributedBody(blob), "hello")
        let long = String(repeating: "a", count: 300)
        var wide = Data("NSString".utf8); wide.append(contentsOf: [0x01, 0x94, 0x84, 0x01, 0x2b, 0x81, 0x2c, 0x01]); wide.append(Data(long.utf8))
        XCTAssertEqual(AppleText.decodeAttributedBody(wide)?.count, 300)
        var truncated = Data("NSString".utf8); truncated.append(contentsOf: [0x01, 0x94, 0x84, 0x01, 0x2b, 50]); truncated.append(Data("short".utf8))
        XCTAssertNil(AppleText.decodeAttributedBody(truncated))
        XCTAssertNil(AppleText.decodeAttributedBody(Data("no marker".utf8)))
        XCTAssertEqual(AppleText.collapse("a   b\t c\n\n  d "), "a b c\nd")
        XCTAssertEqual(AppleText.clip("abcdef", limit: 3), "abc\n[truncated]")
        XCTAssertEqual(AppleText.clip("abc", limit: 3), "abc")
        XCTAssertEqual(AppleText.messageDate(1_000_000_000_000_000).timeIntervalSinceReferenceDate, 1_000_000, accuracy: 0.001)
        XCTAssertEqual(AppleText.messageDate(1000).timeIntervalSinceReferenceDate, 1000, accuracy: 0.001)
        XCTAssertEqual(AppleText.parseDate("2026-11-12T15:00:00-06:00")?.timeIntervalSince1970, 1794517200)
        XCTAssertNotNil(AppleText.parseDate("2026-11-12T15:00:00"))
        XCTAssertNotNil(AppleText.parseDate("2026-11-12"))
        XCTAssertNil(AppleText.parseDate("next tuesday"))
        XCTAssertNil(AppleText.parseDate(nil))
    }

    // MARK: Secure logins
    func testSecureLoginSitesMustMatchExactlyOrBeSubdomains() {
        XCTAssertEqual(SecureLoginStore.host(from: "https://Secure.ESPN.com/login?x=1"), "secure.espn.com")
        XCTAssertNil(SecureLoginStore.host(from: "http://espn.com"))
        XCTAssertNil(SecureLoginStore.host(from: "https://user:pw@espn.com"))
        XCTAssertNil(SecureLoginStore.host(from: "https://localhost"))
        XCTAssertNil(SecureLoginStore.host(from: "javascript:alert(1)"))
        XCTAssertTrue(SecureLoginStore.matches(loginHost: "espn.com", pageHost: "www.espn.com"))
        XCTAssertTrue(SecureLoginStore.matches(loginHost: "espn.com", pageHost: "espn.com"))
        XCTAssertFalse(SecureLoginStore.matches(loginHost: "espn.com", pageHost: "espn.com.evil.example"))
        XCTAssertFalse(SecureLoginStore.matches(loginHost: "espn.com", pageHost: "notespn.com"))
    }

    func testSecureLoginStoreKeepsPasswordsOutOfTheIndexAndValidatesInput() throws {
        let store = uniqueLogins()
        let login = try store.add(label: "ESPN", url: "https://www.espn.com/login", username: "me@example.com", password: "hunter2-password")
        defer { try? store.remove(login.id); try? store.store.delete(account: "index") }
        XCTAssertEqual(store.list(), [login])
        XCTAssertEqual(store.password(for: login.id), "hunter2-password")
        let index = try XCTUnwrap(try store.store.read(account: "index"))
        XCTAssertFalse(String(decoding: index, as: UTF8.self).contains("hunter2"))
        XCTAssertThrowsError(try store.add(label: "espn", url: "https://www.espn.com", username: "x", password: "y"), "Names are unique, ignoring case")
        XCTAssertThrowsError(try store.add(label: "Other", url: "http://insecure.example.com", username: "x", password: "y"))
        XCTAssertThrowsError(try store.add(label: "", url: "https://example.com", username: "x", password: "y"))
        XCTAssertThrowsError(try store.add(label: "Other", url: "https://example.com", username: "", password: "y"))
        XCTAssertThrowsError(try store.add(label: "Other", url: "https://example.com", username: "x", password: ""))
        XCTAssertEqual(store.list().count, 1)
        try store.remove(login.id)
        XCTAssertTrue(store.list().isEmpty)
        XCTAssertNil(store.password(for: login.id))
    }

    // MARK: Device actions
    func testAppleConnectionsStartOffAndPersistTheirChoice() throws {
        let suite = "org.opengrokbot.tests.apple." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite)); defer { defaults.removePersistentDomain(forName: suite) }
        XCTAssertTrue(AppleConnections(defaults: defaults).enabled.isEmpty)
        defaults.set(true, forKey: "appleConnection.mail")
        let apple = AppleConnections(defaults: defaults)
        XCTAssertTrue(apple.isEnabled(.mail))
        XCTAssertFalse(apple.isEnabled(.messages))
        apple.setEnabled(.mail, false)
        XCTAssertFalse(AppleConnections(defaults: defaults).isEnabled(.mail))
    }

    func testBotActionsForMacToolsParseAndAreRouted() {
        let parsed = BotTeamwork.parse("Checking.\n```opengrokbot-action\n{\"action\":\"apple_calendar\",\"days\":3}\n```").actions
        XCTAssertEqual(parsed.first?.days, 3)
        XCTAssertTrue(MacDeviceActions.actionNames.contains("apple_calendar"))
        XCTAssertTrue(MacDeviceActions.actionNames.contains("secure_login"))
        XCTAssertFalse(MacDeviceActions.actionNames.contains("vm_exec"))
    }

    func testDisabledServicesAndWritesAreRefusedWithoutPrompting() async throws {
        let suite = "org.opengrokbot.tests.apple." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite)); defer { defaults.removePersistentDomain(forName: suite) }
        let approval = MacApproval(), log = ApprovalLog()
        approval.handler = { title, detail, authenticate in log.items.append((title, detail, authenticate)); return true }
        let actions = MacDeviceActions(apple: AppleConnections(defaults: defaults), approval: approval, logins: uniqueLogins())
        XCTAssertEqual(actions.promptNote(), "", "Nothing is on, so prompts stay small")
        for name in ["apple_calendar", "apple_reminders", "apple_contacts", "apple_mail", "apple_notes", "apple_messages"] {
            let result = await actions.run(BotAction(action: name, text: "x"), bot: bot, unattended: false)
            XCTAssertTrue(result.contains("turned off"), name)
        }
        let reminder = await actions.run(BotAction(action: "apple_add_reminder", text: "Call the plumber"), bot: bot, unattended: false)
        XCTAssertTrue(reminder.contains("off or not allowed"))
        let event = await actions.run(BotAction(action: "apple_add_event", name: "Dentist", at: "2026-11-12T15:00:00-06:00"), bot: bot, unattended: false)
        XCTAssertTrue(event.contains("off or not allowed"))
        XCTAssertTrue(log.items.isEmpty, "A disabled service never prompts")
        let unknown = await actions.run(BotAction(action: "apple_send_email"), bot: bot, unattended: false)
        XCTAssertEqual(unknown, "Unsupported Mac action.")
    }

    func testSecureLoginNeedsApprovalWithAuthenticationAndNeverExposesThePassword() async throws {
        let suite = "org.opengrokbot.tests.apple." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite)); defer { defaults.removePersistentDomain(forName: suite) }
        let logins = uniqueLogins()
        let saved = try logins.add(label: "ESPN", url: "https://www.espn.com/login", username: "me@example.com", password: "correct-horse-battery")
        defer { try? logins.remove(saved.id); try? logins.store.delete(account: "index") }
        let approval = MacApproval(), log = ApprovalLog()
        approval.handler = { title, detail, authenticate in log.items.append((title, detail, authenticate)); return false }
        let actions = MacDeviceActions(apple: AppleConnections(defaults: defaults), approval: approval, logins: logins)

        let note = actions.promptNote()
        XCTAssertTrue(note.contains("ESPN (www.espn.com)"))
        XCTAssertFalse(note.contains("correct-horse-battery"))
        XCTAssertFalse(note.contains("me@example.com"), "Even the username stays out of the prompt")

        let declined = await actions.run(BotAction(action: "secure_login", name: "ESPN", url: "https://www.espn.com/login"), bot: bot, unattended: false)
        XCTAssertTrue(declined.contains("declined"))
        XCTAssertFalse(declined.contains("correct-horse-battery"))
        XCTAssertEqual(log.items.count, 1)
        XCTAssertTrue(log.items[0].authenticate, "Signing in requires Touch ID or the Mac password")
        XCTAssertTrue(log.items[0].detail.contains("me@example.com"))
        XCTAssertFalse(log.items[0].detail.contains("correct-horse-battery"))

        let lookalike = await actions.run(BotAction(action: "secure_login", name: "ESPN", url: "https://www.espn.com.evil.example/login"), bot: bot, unattended: false)
        XCTAssertTrue(lookalike.contains("No saved secure login matches"))
        let unattended = await actions.run(BotAction(action: "secure_login", name: "ESPN", url: "https://www.espn.com/login"), bot: bot, unattended: true)
        XCTAssertTrue(unattended.contains("unattended"))
        let insecure = await actions.run(BotAction(action: "secure_login", name: "ESPN", url: "http://www.espn.com/login"), bot: bot, unattended: false)
        XCTAssertTrue(insecure.contains("https"))
        XCTAssertEqual(log.items.count, 1, "Only the genuine request ever prompted")
    }
}
#endif
