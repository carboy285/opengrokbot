import XCTest
#if os(macOS)
@testable import GrokBotMac
#else
@testable import GrokBot
#endif

final class AppModelTests: XCTestCase {
    private func temporaryStore() -> WorkspaceStore {
        WorkspaceStore(url: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("preview.json"))
    }

    @MainActor
    func testNotesStayLocalAndSurviveRelaunch() throws {
        let store = temporaryStore()
        defer { try? FileManager.default.removeItem(at: store.url.deletingLastPathComponent()) }
        let model = AppModel(store: store)
        XCTAssertFalse(model.previewEnabled)
        XCTAssertTrue(model.workspace.bots.isEmpty)
        model.enterPreview()
        let bot = try XCTUnwrap(model.workspace.bots.first)
        XCTAssertTrue(model.addNote("  Study fractions  ", to: bot))
        XCTAssertEqual(model.entries(for: bot).last?.text, "Study fractions")
        XCTAssertEqual(model.entries(for: bot).last?.kind, .user)
        XCTAssertFalse(model.addNote("   ", to: bot))
        model.leavePreview()
        XCTAssertFalse(model.addNote("Not in preview", to: bot))
        let relaunched = AppModel(store: store)
        relaunched.enterPreview()
        XCTAssertEqual(relaunched.workspace, model.workspace)
    }

    @MainActor
    func testDeletionRemovesConversationEntries() throws {
        let store = temporaryStore()
        defer { try? FileManager.default.removeItem(at: store.url.deletingLastPathComponent()) }
        let model = AppModel(store: store)
        model.enterPreview()
        let bot = try XCTUnwrap(model.workspace.bots.first)
        model.removeBot(bot)
        XCTAssertFalse(model.workspace.bots.contains(where: { $0.id == bot.id }))
        XCTAssertTrue(model.entries(for: bot).isEmpty)
    }

    @MainActor
    func testSaveFailureDoesNotDiscardNoteOrMutateWorkspace() throws {
        let store = temporaryStore()
        defer { try? FileManager.default.removeItem(at: store.url.deletingLastPathComponent()) }
        let model = AppModel(store: store)
        model.enterPreview()
        let bot = try XCTUnwrap(model.workspace.bots.first)
        let before = model.workspace
        // A directory at the file path reliably prevents atomic file replacement.
        try FileManager.default.createDirectory(at: store.url, withIntermediateDirectories: true)
        XCTAssertFalse(model.addNote("Keep this draft", to: bot))
        XCTAssertEqual(model.workspace, before)
        XCTAssertNotNil(model.errorMessage)
    }
}
