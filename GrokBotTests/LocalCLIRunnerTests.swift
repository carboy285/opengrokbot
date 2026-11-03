#if os(macOS)
import XCTest
@testable import GrokBotMac

final class LocalCLIRunnerTests: XCTestCase {
    func testActualSubprocessStreamsUnicodeAndUsesExplicitResume() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let executable = root.appendingPathComponent("codex-fixture")
        let script = """
        #!/bin/sh
        printf '%s\\n' "$@" > arguments.txt
        cat > received-prompt.txt
        printf '%s\\n' '{"type":"thread.started","thread_id":"test-session"}'
        printf '%s\\n' '{"type":"item.completed","item":{"id":"m1","type":"agent_message","text":"Hello café 🌙"}}'
        """
        try script.write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
        let cli = InstalledCLI(provider: .codex, path: executable.path, version: "fixture")
        var events: [CLIEvent] = []
        for try await event in LocalCLIRun.stream(cli: cli, prompt: "Keep this off argv", session: "test-session", directory: root) { events.append(event) }
        XCTAssertTrue(events.contains(.session("test-session")))
        XCTAssertTrue(events.contains(.text("Hello café 🌙")))
        let arguments = try String(contentsOf: root.appendingPathComponent("arguments.txt"), encoding: .utf8)
        XCTAssertTrue(arguments.contains("resume\ntest-session"))
        XCTAssertFalse(arguments.contains("Keep this off argv"))
        XCTAssertEqual(try String(contentsOf: root.appendingPathComponent("received-prompt.txt"), encoding: .utf8), "Keep this off argv")
    }
    func testInstallationScannerFindsExplicitExecutable() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let executable = root.appendingPathComponent("codex-fixture")
        try "#!/bin/sh\nprintf 'codex-cli fixture\\n'\n".write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions:0o755], ofItemAtPath: executable.path)
        let captured = CLIInstallationScanner.capture(path: executable.path, arguments: ["--version"])
        XCTAssertEqual(captured.exit, 0)
        XCTAssertTrue(captured.text.contains("codex-cli fixture"))
        let found = CLIInstallationScanner.scan(overrides: ["codex":executable.path])
        XCTAssertEqual(found.first(where: { $0.provider == .codex })?.path, executable.path)
    }

    func testStopWaitsForOwnedSubprocessAndReportsStopped() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let executable = root.appendingPathComponent("slow-cli")
        let script = """
        #!/bin/sh
        cat >/dev/null
        printf '%s\\n' '{"type":"item.completed","item":{"id":"a","type":"agent_message","text":"Partial reply"}}'
        exec sleep 30
        """
        try script.write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions:0o755], ofItemAtPath: executable.path)
        let run = LocalCLIRun()
        var received = false
        let started = Date()
        do {
            for try await event in run.events(cli: InstalledCLI(provider: .codex, path: executable.path, version: "fixture"), prompt: "test", session: nil, directory: root) {
                if case .text = event { received = true; run.cancel() }
            }
            XCTFail("Stopped processes must not complete successfully")
        } catch { XCTAssertEqual(error as? CLIError, .stopped) }
        XCTAssertTrue(received)
        XCTAssertLessThan(Date().timeIntervalSince(started), 15)
    }

    @MainActor
    func testChatCreatesSpecialistAndReturnsOnlyItsSelectedModelReply() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let app = AppModel(store: WorkspaceStore(url: root.appendingPathComponent("workspace.json")))
        app.enterPreview()
        let desktop = MacAppModel()
        defer {
            desktop.stopAll(immediately: true)
            for bot in app.workspace.bots { try? FileManager.default.removeItem(at: desktop.workingDirectory(for: bot)) }
            try? FileManager.default.removeItem(at: root)
        }
        let executable = root.appendingPathComponent("codex-team-fixture")
        let create = "Creating a specialist.\n```opengrokbot-action\n{\"action\":\"create_bot\",\"name\":\"Travel\",\"purpose\":\"Plan trips without booking\"}\n```\n```opengrokbot-action\n{\"action\":\"message_bot\",\"to\":\"Travel\",\"text\":\"Suggest a weekend trip\"}\n```"
        func event(_ text: String) throws -> String {
            let data = try JSONSerialization.data(withJSONObject: ["type":"item.completed", "item":["id":"reply", "type":"agent_message", "text":text]])
            return String(decoding: data, as: UTF8.self).replacingOccurrences(of: "'", with: "'\\''")
        }
        let script = """
        #!/bin/sh
        printf '%s\\n' "$@" >> '\(root.path)/arguments.txt'
        prompt=$(cat)
        case "$prompt" in
          'You are Travel.'*) printf '%s\\n' '\(try event("Specialist weekend plan"))' ;;
          *) printf '%s\\n' '\(try event(create))' ;;
        esac
        """
        try script.write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions:0o755], ofItemAtPath: executable.path)
        desktop.installedCLIs = [InstalledCLI(provider: .codex, path: executable.path, version: "fixture"), InstalledCLI(provider: .claude, path: "/does/not/run", version: "fixture")]
        desktop.selectedCLIID = desktop.installedCLIs[0].id
        let main = try XCTUnwrap(app.workspace.bots.first)
        let config = BotAIConfiguration(providers: [BotAIProvider(provider: .codex, model: "chosen-model"), BotAIProvider(provider: .claude, model: "never-called")], activeProvider: .codex, replyMode: .all)
        XCTAssertTrue(app.setAIConfiguration(config, for: main))
        XCTAssertTrue(desktop.send("Make Travel and ask for a trip", to: try XCTUnwrap(app.workspace.bots.first), app: app))
        for _ in 0..<100 {
            if app.workspace.teamMessages?.first?.status == .complete { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        XCTAssertEqual(app.workspace.teamMessages?.first?.status, .complete)
        let travel = try XCTUnwrap(app.workspace.bots.first { $0.name == "Travel" })
        XCTAssertEqual(travel.aiConfiguration?.activeProvider, .codex)
        XCTAssertEqual(app.entries(for: main).last?.senderBotID, travel.id)
        XCTAssertEqual(app.entries(for: main).last?.text, "Specialist weekend plan")
        XCTAssertEqual(desktop.providersToRun(for: travel).count, 1)
        let arguments = try String(contentsOf: root.appendingPathComponent("arguments.txt"), encoding: .utf8)
        XCTAssertEqual(arguments.components(separatedBy: "--model\nchosen-model").count - 1, 2)
        XCTAssertFalse(arguments.contains("never-called"))
    }


    func testAPIKeysAreValidatedMaskedAndMappedToTheRightVariables() throws {
        XCTAssertEqual(ProviderAPIKeys.normalized("  sk-ant-abcdef123456\n"), "sk-ant-abcdef123456")
        XCTAssertNil(ProviderAPIKeys.normalized("short"))
        XCTAssertNil(ProviderAPIKeys.normalized("two words in a key"))
        XCTAssertNil(ProviderAPIKeys.normalized("sk-abcdef\n123456"))
        XCTAssertNil(ProviderAPIKeys.normalized("sk-abcdef123456🔑"))
        XCTAssertEqual(ProviderAPIKeys.masked("sk-ant-abcdef123456"), "••••3456")
        XCTAssertEqual(ProviderAPIKeys.info(for: .claude)?.variables, ["ANTHROPIC_API_KEY"])
        XCTAssertEqual(ProviderAPIKeys.info(for: .grok)?.variables, ["XAI_API_KEY"])
        XCTAssertEqual(ProviderAPIKeys.info(for: .gemini)?.variables, ["GEMINI_API_KEY"])
        XCTAssertEqual(ProviderAPIKeys.info(for: .codex)?.variables, ["CODEX_API_KEY", "OPENAI_API_KEY"])
        XCTAssertNil(ProviderAPIKeys.info(for: .opencode))
    }

    func testSavedAPIKeyReachesOnlyThatCLIsEnvironmentNeverItsArguments() async throws {
        let store = KeychainSecretStore(service: "org.opengrokbot.tests.provider-keys." + UUID().uuidString)
        defer { for provider in CLIProvider.allCases { try? ProviderAPIKeys.remove(provider, store: store) } }
        XCTAssertTrue(ProviderAPIKeys.environment(for: .claude, store: store).isEmpty)
        XCTAssertFalse(try ProviderAPIKeys.save("not a key", for: .claude, store: store))
        XCTAssertFalse(try ProviderAPIKeys.save("sk-ant-abcdef123456", for: .opencode, store: store))
        XCTAssertTrue(try ProviderAPIKeys.save("sk-ant-test-key-123456", for: .claude, store: store))
        XCTAssertEqual(ProviderAPIKeys.environment(for: .claude, store: store), ["ANTHROPIC_API_KEY": "sk-ant-test-key-123456"])
        XCTAssertTrue(ProviderAPIKeys.environment(for: .grok, store: store).isEmpty)

        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let executable = root.appendingPathComponent("claude-fixture")
        let script = """
        #!/bin/sh
        printf '%s\\n' "$@" > arguments.txt
        printf '%s' "$ANTHROPIC_API_KEY" > anthropic-key.txt
        cat > received-prompt.txt
        printf '%s\\n' '{"type":"result","result":"ok","session_id":"s1"}'
        """
        try script.write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
        let cli = InstalledCLI(provider: .claude, path: executable.path, version: "fixture")
        for try await _ in LocalCLIRun.stream(cli: cli, prompt: "hello", session: nil, directory: root, keys: store) {}
        XCTAssertEqual(try String(contentsOf: root.appendingPathComponent("anthropic-key.txt"), encoding: .utf8), "sk-ant-test-key-123456")
        XCTAssertFalse(try String(contentsOf: root.appendingPathComponent("arguments.txt"), encoding: .utf8).contains("sk-ant"))
        XCTAssertFalse(try String(contentsOf: root.appendingPathComponent("received-prompt.txt"), encoding: .utf8).contains("sk-ant"))

        try ProviderAPIKeys.remove(.claude, store: store)
        XCTAssertTrue(ProviderAPIKeys.environment(for: .claude, store: store).isEmpty)
    }

}
#endif
