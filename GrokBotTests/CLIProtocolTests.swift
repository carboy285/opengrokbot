import XCTest
#if os(macOS)
@testable import GrokBotMac
#else
@testable import GrokBot
#endif

final class CLIProtocolTests: XCTestCase {
    func testFailureClassificationDoesNotExposeStderr() {
        let secret = "private-token-and-conversation"
        let cases: [(String, CLIError)] = [("HTTP 429 rate limit", .rateLimited), ("unknown model", .invalidModel), ("authentication failed", .notLoggedIn), ("connection refused", .network), ("unexpected error", .failed(3))]
        for (diagnostic, expected) in cases {
            let result = CLIError.classify(stderr: diagnostic + " " + secret, exitCode: 3)
            XCTAssertEqual(result, expected)
            XCTAssertFalse((result.errorDescription ?? "").contains(secret))
        }
    }
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

    func testMigrationPreservesAuthoredRepliesInEditedLegacyHistory() {
        let main = Bot(id: UUID(), name: "Grok Bot", purpose: "A place to bring it all together", color: "white", symbol: "sparkles")
        var value = Workspace(bots: [main], entries: [
            Entry(botID: main.id, kind: .bot, text: "Your week is coming together. Edited legacy history."),
            Entry(botID: main.id, kind: .user, text: "Sure"),
            Entry(botID: main.id, kind: .user, text: "What’s on your plate right now?")
        ], schemaVersion: nil)
        value.migrateLegacyDemo()
        XCTAssertEqual(value.entries.count, 3)
        XCTAssertEqual(value.entries[1].text, "Sure")
        XCTAssertEqual(value.entries[2].text, "What’s on your plate right now?")
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

    func testSpecificModelsArePassedAsArgumentsForEveryProvider() {
        for provider in CLIProvider.allCases where !provider.isLocalServer {
            let command = CLICommand.chat(provider: provider, prompt: "private", session: "saved-session", promptFile: "/private/prompt.txt", model: "provider/specific-model")
            let index = command.arguments.firstIndex(of: "--model")!
            XCTAssertEqual(command.arguments[index + 1], "provider/specific-model")
            XCTAssertEqual(command.arguments.filter { $0 == "--model" }.count, 1)
            XCTAssertFalse(command.arguments.contains("private"))
        }
    }

    func testProviderConfigurationPersistsMultipleSelectionsAndModels() throws {
        var bot = Workspace.fresh.bots[0]
        bot.aiConfiguration = BotAIConfiguration(providers: [BotAIProvider(provider: .codex, model: "model-a"), BotAIProvider(provider: .claude, model: "model-b")], activeProvider: .claude, replyMode: .all)
        let restored = try JSONDecoder().decode(Bot.self, from: JSONEncoder().encode(bot))
        XCTAssertEqual(restored.aiConfiguration, bot.aiConfiguration)
    }

    func testCommandsKeepPromptsOutOfArgumentsAndResumeExplicitSessions() {
        for provider in CLIProvider.allCases where !provider.isLocalServer {
            let command = CLICommand.chat(provider: provider, prompt: "private prompt; $(echo never)", session: "my-session", promptFile: "/private/prompt.txt")
            XCTAssertFalse(command.arguments.contains(where: { $0.contains("private prompt") }))
            XCTAssertTrue(command.arguments.contains("my-session"))
            XCTAssertFalse(command.arguments.contains(where: { $0.contains("bypass") || $0 == "--yolo" }))
        }
    }

    func testLocalModelServersNeverBuildAProcessCommandAndCodexCanThinkLessForVoice() {
        for provider in CLIProvider.allCases where provider.isLocalServer {
            XCTAssertTrue(CLICommand.chat(provider: provider, prompt: "private", session: nil).arguments.isEmpty)
        }
        let fast = CLICommand.chat(provider: .codex, prompt: "x", session: nil, fast: true).arguments
        XCTAssertEqual(fast.prefix(5), ["exec", "--sandbox", "read-only", "-c", "model_reasoning_effort=low"])
        XCTAssertEqual(BotTeamwork.voiceModel(provider: .claude, chatModel: "opus", custom: nil), "haiku")
        XCTAssertEqual(BotTeamwork.voiceModel(provider: .codex, chatModel: "gpt-x", custom: nil), "gpt-x")
        XCTAssertEqual(BotTeamwork.voiceModel(provider: .ollama, chatModel: "llama3.2", custom: "qwen3:4b"), "qwen3:4b")
    }

    func testCodexAnswerPiecesStreamAndFinalTextWins() {
        var parser = CLIEventParser()
        var texts: [String] = []
        for line in [#"{"type":"item.agent_message.delta","item_id":"m1","delta":"Hello"}"#,
                     #"{"type":"item.agent_message.delta","item_id":"m1","delta":" there."}"#,
                     #"{"type":"item.completed","item":{"id":"m1","type":"agent_message","text":"Hello there!"}}"#] {
            for case .text(let value) in parser.parse(Data(line.utf8)) { texts.append(value) }
        }
        XCTAssertEqual(texts, ["Hello", "Hello there.", "Hello there!"])
        XCTAssertNil(CLIEventParser.agentDelta(type: "item.reasoning.delta", value: ["delta": "thinking"]))
    }
}
