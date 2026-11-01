import XCTest
#if os(macOS)
@testable import GrokBotMac
#else
@testable import GrokBot
#endif

final class CLIProtocolTests: XCTestCase {
    func testFreshWorkspaceHasOnlyMainBotAndNoMessages() {
        let value = Workspace.fresh
        XCTAssertEqual(value.bots.count, 1)
        XCTAssertEqual(value.bots.first?.name, "Grok Bot")
        XCTAssertEqual(value.bots.first?.isMain, true)
        XCTAssertTrue(value.entries.isEmpty)
    }

    func testLegacyDemoMigrationKeepsUserNotesAndCustomBots() throws {
        let main = Bot(id: UUID(), name: "Grok Bot", purpose: "A place to bring it all together", color: "white", symbol: "sparkles")
        let school = Bot(id: UUID(), name: "School", purpose: "Make a plan for the week ahead", color: "ochre", symbol: "book.closed")
        let custom = Bot(id: UUID(), name: "My work", purpose: "My notes", color: "pink", symbol: "sparkles")
        var value = Workspace(bots: [main, school, custom], entries: [
            Entry(botID: school.id, kind: .bot, text: "What do you need help with for Wednesday’s Spanish test?"),
            Entry(botID: main.id, kind: .user, text: "Keep my actual note")
        ], schemaVersion: nil)
        value.migrateLegacyDemo()
        XCTAssertEqual(value.bots.map(\.name), ["Grok Bot", "My work"])
        XCTAssertEqual(value.entries.map(\.text), ["Keep my actual note"])
        XCTAssertTrue(value.bots[0].isMain == true)
    }

    func testCodexMessagesReplaceUpdatesAndPreserveSeparateItems() throws {
        var parser = CLIEventParser()
        let lines = [
            #"{"type":"thread.started","thread_id":"thread-1"}"#,
            #"{"type":"item.updated","item":{"id":"a","type":"agent_message","text":"Hel"}}"#,
            #"{"type":"item.completed","item":{"id":"a","type":"agent_message","text":"Hello café 🌙"}}"#,
            #"{"type":"item.completed","item":{"id":"b","type":"agent_message","text":"Second paragraph"}}"#
        ]
        XCTAssertEqual(parser.parse(Data(lines[0].utf8)), [.session("thread-1")])
        for line in lines.dropFirst() { _ = parser.parse(Data(line.utf8)) }
        XCTAssertEqual(parser.text, "Hello café 🌙\n\nSecond paragraph")
    }

    func testMessagesCompatibleProvidersDoNotDuplicateFinalResult() {
        var parser = CLIEventParser()
        _ = parser.parse(Data(#"{"type":"stream_event","event":{"delta":{"type":"text_delta","text":"Hi"}}}"#.utf8))
        _ = parser.parse(Data(#"{"type":"assistant","message":{"content":[{"type":"text","text":"Hi"}]}}"#.utf8))
        _ = parser.parse(Data(#"{"type":"result","result":"Hi","is_error":false,"session_id":"session-1"}"#.utf8))
        XCTAssertEqual(parser.text, "Hi")
        XCTAssertTrue(parser.parse(Data(#"{"type":"result","is_error":true}"#.utf8)).contains(.failed))
    }

    func testOpenCodeAndGeminiEvents() {
        var open = CLIEventParser(), gemini = CLIEventParser()
        XCTAssertTrue(open.parse(Data(#"{"type":"text","sessionID":"ses_123","part":{"id":"p1","text":"OpenCode answer"}}"#.utf8)).contains(.text("OpenCode answer")))
        _ = gemini.parse(Data(#"{"type":"message","role":"assistant","content":"One ","delta":true}"#.utf8))
        _ = gemini.parse(Data(#"{"type":"message","role":"assistant","content":"two","delta":true}"#.utf8))
        XCTAssertEqual(gemini.text, "One two")
        XCTAssertTrue(gemini.parse(Data(#"{"type":"result","status":"error"}"#.utf8)).contains(.failed))
    }

    func testCommandsKeepPromptsOutOfArgumentsAndResumeExplicitSessions() {
        for provider in CLIProvider.allCases {
            let command = CLICommand.chat(provider: provider, prompt: "private prompt; $(echo never)", session: "my-session", promptFile: "/private/prompt.txt")
            XCTAssertFalse(command.arguments.contains(where: { $0.contains("private prompt") }))
            XCTAssertTrue(command.arguments.contains("my-session"))
            XCTAssertFalse(command.arguments.contains(where: { $0.contains("bypass") || $0 == "--yolo" }))
        }
    }
}
