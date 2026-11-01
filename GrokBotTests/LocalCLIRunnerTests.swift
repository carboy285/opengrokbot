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

}
#endif
