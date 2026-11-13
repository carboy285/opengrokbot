#if os(macOS)
import XCTest
@testable import GrokBotMac

final class MacRemoteHostTests: XCTestCase {
    @MainActor
    func testRealControllerPairsConfiguresSendsOnceAndObservesDesktopReply() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        let suite = "org.opengrokbot.remote-test." + UUID().uuidString
        let preferences = try XCTUnwrap(UserDefaults(suiteName:suite))
        let secrets = KeychainSecretStore(service:suite)
        let app = AppModel(store:WorkspaceStore(url:root.appendingPathComponent("workspace.json")));app.enterPreview()
        let desktop = MacAppModel()
        let host = MacRemoteHost(preferences:preferences,account:CloudAccount(kind:"host",secrets:secrets))
        defer {
            host.stop();desktop.stopAll(immediately:true);try? secrets.delete(account:"session")
            preferences.removePersistentDomain(forName:suite)
            for bot in app.workspace.bots { try? FileManager.default.removeItem(at:desktop.workingDirectory(for:bot)) }
            try? FileManager.default.removeItem(at:root)
        }
        let executable = root.appendingPathComponent("fixture")
        try "#!/bin/sh\ncat >/dev/null\nprintf '%s\\n' '{\"type\":\"item.completed\",\"item\":{\"id\":\"reply\",\"type\":\"agent_message\",\"text\":\"Reply on the desktop\"}}'\n".write(to:executable,atomically:true,encoding:.utf8)
        try FileManager.default.setAttributes([.posixPermissions:0o755],ofItemAtPath:executable.path)
        desktop.installedCLIs=[InstalledCLI(provider:.codex,path:executable.path,version:"fixture")];desktop.selectedCLIID=desktop.installedCLIs[0].id
        host.attach(app:app,desktop:desktop)
        func call(_ command: RemoteCommand? = nil, target: String = "/v1/state") async throws -> RemoteHostResponse {
            await host.dispatch(RemoteHostRequest(method:command == nil ? "GET":"POST",target:command == nil ? target:"/v1/command",body:try command.map { try JSONEncoder().encode($0) } ?? Data()))
        }
        let first = try CloudCoding.decoder().decode(RemoteSnapshot.self,from:await call().body)
        XCTAssertEqual(first.workspace.bots.count,1);XCTAssertTrue(first.workspace.entries.isEmpty);XCTAssertTrue((first.workspace.sessions ?? [:]).isEmpty)
        let unchanged = try await call(target:"/v1/state?since=" + first.revision)
        XCTAssertEqual(unchanged.status,204)
        let bot = try XCTUnwrap(first.workspace.bots.first)
        let config = BotAIConfiguration(providers:[BotAIProvider(provider:.codex,model:"remote-model")],activeProvider:.codex)
        _ = try await call(RemoteCommand(action:"configure_bot",botID:bot.id,configuration:config))
        let command = RemoteCommand(action:"send",botID:bot.id,text:"From my phone 🌎")
        _ = try await call(command)
        _ = try await call(command)
        for _ in 0..<100 { if app.entries(for:bot).last?.state == .complete { break };try await Task.sleep(for:.milliseconds(20)) }
        let result = try CloudCoding.decoder().decode(RemoteSnapshot.self,from:await call().body)
        XCTAssertEqual(result.workspace.entries.filter{$0.kind == .user}.count,1)
        XCTAssertEqual(result.workspace.entries.last?.text,"Reply on the desktop")
        XCTAssertEqual(app.workspace.bots.first?.aiConfiguration?.providers.first?.model,"remote-model")
    }
}

/// Heads-ups (0.9.6): the rules that decide what deserves a message.
final class HeadsUpRulesTests: XCTestCase {
    private let utc: Calendar = { var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: "UTC")!; return calendar }()
    private func event(_ id: String, _ start: Double, _ end: Double, allDay: Bool = false, declined: Bool = false) -> HeadsUpEvent {
        HeadsUpEvent(id: id, title: id, start: Date(timeIntervalSince1970: start), end: Date(timeIntervalSince1970: end), allDay: allDay, declined: declined, link: nil)
    }

    func testQuietHoursWrapPastMidnight() {
        let late = Date(timeIntervalSince1970: 23 * 3600), morning = Date(timeIntervalSince1970: 8 * 3600)
        XCTAssertTrue(HeadsUpRules.inQuietHours(late, on: true, start: 22 * 60, end: 7 * 60, calendar: utc))
        XCTAssertFalse(HeadsUpRules.inQuietHours(morning, on: true, start: 22 * 60, end: 7 * 60, calendar: utc))
        XCTAssertFalse(HeadsUpRules.inQuietHours(late, on: false, start: 22 * 60, end: 7 * 60, calendar: utc))
    }

    func testRemindersFireOnceInsideTheLeadWindow() {
        let now = Date(timeIntervalSince1970: 10_000)
        let events = [event("soon", 10_480, 12_000), event("later", 14_000, 15_000), event("declined", 10_300, 11_000, declined: true), event("day", 9_000, 90_000, allDay: true)]
        let due = HeadsUpRules.dueReminders(events, lead: 10, now: now, reminded: [])
        XCTAssertEqual(due.map(\.id), ["soon"])
        XCTAssertTrue(HeadsUpRules.dueReminders(events, lead: 10, now: now, reminded: [HeadsUpRules.key(due[0])]).isEmpty)
        XCTAssertTrue(HeadsUpRules.reminderText(due[0], now: now).contains("starts in 8 min"))
    }

    func testOverlapsSkipBackToBackAndRepeat() {
        let now = Date(timeIntervalSince1970: 0)
        let events = [event("a", 3_600, 7_200), event("b", 5_400, 9_000), event("c", 9_000, 10_800)]
        let found = HeadsUpRules.overlaps(events, now: now, known: [])
        XCTAssertEqual(found.count, 1)
        XCTAssertEqual([found[0].first.id, found[0].second.id], ["a", "b"])
        XCTAssertTrue(HeadsUpRules.overlaps(events, now: now, known: [found[0].key]).isEmpty)
    }

    func testBriefIsDueOnceADayInsideItsWindow() {
        let eight = Date(timeIntervalSince1970: 8 * 3600 + 300), evening = Date(timeIntervalSince1970: 19 * 3600)
        XCTAssertTrue(HeadsUpRules.briefDue(now: eight, at: 8 * 60, lastBrief: "", calendar: utc))
        XCTAssertFalse(HeadsUpRules.briefDue(now: eight, at: 8 * 60, lastBrief: HeadsUpRules.dayKey(eight, calendar: utc), calendar: utc))
        XCTAssertFalse(HeadsUpRules.briefDue(now: evening, at: 8 * 60, lastBrief: "", calendar: utc))
    }

    func testMailKeysIgnoreSnippetsAndAutomatedSendersStayQuiet() {
        let first = HeadsUpRules.mailItems("Mon | Ana Ruiz <ana@example.com> | Lease | Please sign\n---\n")
        let later = HeadsUpRules.mailItems("Mon | Ana Ruiz <ana@example.com> | Lease | \n---\n")
        XCTAssertEqual(first.first?.key, later.first?.key)
        XCTAssertTrue(HeadsUpRules.isFromPerson("Ana Ruiz <ana@example.com>"))
        XCTAssertFalse(HeadsUpRules.isFromPerson("Shop <no-reply@shop.example>"))
        XCTAssertEqual(HeadsUpRules.senderName("\"Ana Ruiz\" <ana@example.com>"), "Ana Ruiz")
        XCTAssertTrue(HeadsUpRules.emailText(first).contains("Ana Ruiz: Lease"))
    }

    func testHeadsUpEntriesDecodeTheWindowsShape() throws {
        let json = #"{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","botID":"6F9619FF-8B86-D011-B42D-00C04FC964FE","kind":"bot","text":"Standup soon","date":0,"headsUp":{"kind":"meeting","title":"Standup"},"label":"x"}"#
        let entry = try JSONDecoder().decode(Entry.self, from: Data(json.utf8))
        XCTAssertEqual(entry.headsUp, HeadsUpTag(kind: "meeting", title: "Standup"))
        XCTAssertEqual(entry.label, "x")
    }
}
#endif
