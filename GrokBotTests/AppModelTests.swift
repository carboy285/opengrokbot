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
    func testRoutineHistoryPersistsAndInterruptedRunsAreRecovered() throws {
        let store = temporaryStore()
        defer { try? FileManager.default.removeItem(at: store.url.deletingLastPathComponent()) }
        let model = AppModel(store: store); model.enterPreview()
        let bot = try XCTUnwrap(model.workspace.bots.first)
        var routine = BotSchedule(name: "Morning", text: "Summarize my notes", nextRun: ISO8601DateFormatter().string(from: Date().addingTimeInterval(3600)), recurrence: "daily", timezone: "UTC")
        routine.lastResult = "running"
        routine.history = [RoutineRun(id: UUID(), date: ISO8601DateFormatter().string(from: Date()), status: "running")]
        XCTAssertTrue(model.createSchedule(routine, botID: bot.id))
        let reopened = AppModel(store: store); reopened.enterPreview()
        let restored = try XCTUnwrap(reopened.workspace.bots.first?.schedules?.first)
        XCTAssertEqual(restored.lastResult, "interrupted")
        XCTAssertEqual(restored.history?.first?.status, "interrupted")
        let again = AppModel(store: store); again.enterPreview()
        XCTAssertEqual(again.workspace.bots.first?.schedules?.first?.lastResult, "interrupted")
    }

    @MainActor
    func testDetailsPreserveMemoryAndRejectDuplicateNames() throws {
        let store = temporaryStore()
        defer { try? FileManager.default.removeItem(at: store.url.deletingLastPathComponent()) }
        let model = AppModel(store: store); model.enterPreview()
        XCTAssertTrue(model.addBot(name: "Research", purpose: "Help", color: "purple"))
        let bot = try XCTUnwrap(model.workspace.bots.last)
        XCTAssertFalse(model.updateDetails(bot, name: "Grok Bot", purpose: "Help", memory: []))
        XCTAssertTrue(model.updateDetails(bot, name: "Research", purpose: "Find sources", memory: ["Remember my preferences"]))
        let reopened = AppModel(store: store); reopened.enterPreview()
        XCTAssertEqual(reopened.workspace.bots.last?.memory, ["Remember my preferences"])
        XCTAssertEqual(reopened.workspace.bots.last?.purpose, "Find sources")
    }

    @MainActor
    func testActivityDoesNotChangeRecentBotOrder() throws {
        let store = temporaryStore()
        defer { try? FileManager.default.removeItem(at: store.url.deletingLastPathComponent()) }
        let model = AppModel(store: store); model.enterPreview()
        XCTAssertTrue(model.addBot(name: "Second", purpose: "Help", color: "purple"))
        let first = try XCTUnwrap(model.workspace.bots.first), second = try XCTUnwrap(model.workspace.bots.last)
        XCTAssertTrue(model.touchBot(second.id))
        model.activity("Reply arrived", for: first.id)
        XCTAssertEqual(model.recentlyUsed(model.workspace.bots).first?.id, second.id)
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
        XCTAssertTrue(model.addBot(name: "My Bot", purpose: "Help", color: "purple"))
        let bot = try XCTUnwrap(model.workspace.bots.last)
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
