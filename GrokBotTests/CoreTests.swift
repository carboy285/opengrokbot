import XCTest
#if os(macOS)
@testable import GrokBotMac
#else
@testable import GrokBot
#endif

final class CoreTests: XCTestCase {
    func testConnectionDraftRejectsUnsafeOrigins() {
        for address in ["https://user:secret@example.com", "https://example.com?token=secret", "https://example.com/#secret", "https://example.com/api", "not a URL", "https://example.com:0", "https://example.com:65536"] {
            XCTAssertThrowsError(try ConnectionDraft(address: address), address)
        }
        XCTAssertThrowsError(try ConnectionDraft(address: "http://example.com")) { error in
            XCTAssertEqual(error as? IntegrationError, .insecureAddress)
        }
    }

    func testConnectionDraftRejectsPhoneLoopback() {
        for address in ["https://localhost", "https://LOCALHOST.", "https://test.localhost", "https://127.0.0.1", "https://127.9.1.1", "https://[::1]", "https://0.0.0.0"] {
            XCTAssertThrowsError(try ConnectionDraft(address: address), address)
        }
    }

    func testValidOriginIsOnlyADraft() throws {
        let draft = try ConnectionDraft(address: " https://bot.example:8443/ ")
        XCTAssertEqual(draft.origin.absoluteString, "https://bot.example:8443/")
        XCTAssertFalse(UnverifiedHarnessClient().capabilities.canConnect)
        XCTAssertNil(UnverifiedHarnessClient().capabilities.verifiedVersion)
    }

    func testUnverifiedClientNeverReportsConnectionSuccess() async {
        do { try await UnverifiedHarnessClient().connect(); XCTFail("Unverified integration must fail closed") }
        catch { XCTAssertEqual(error as? IntegrationError, .protocolUnverified) }
    }

    func testPersistenceRoundTripAndMissingFile() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = WorkspaceStore(url: directory.appendingPathComponent("workspace.json"))
        XCTAssertNil(try store.load())
        let workspace = Workspace.preview
        try store.save(workspace)
        XCTAssertEqual(try store.load(), workspace)
        try Data("broken".utf8).write(to: store.url)
        XCTAssertThrowsError(try store.load())
        XCTAssertEqual(try String(contentsOf: store.url, encoding: .utf8), "broken")
    }
}
