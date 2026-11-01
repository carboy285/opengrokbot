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
}
#endif
