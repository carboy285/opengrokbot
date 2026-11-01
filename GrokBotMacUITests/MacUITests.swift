import Foundation
import XCTest

final class MacUITests: XCTestCase {
    @MainActor
    private func application(setup: Bool) throws -> (XCUIApplication, URL) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let executable = directory.appendingPathComponent("codex-fixture")
        let script = """
        #!/bin/sh
        if [ "$1" = "--version" ]; then printf 'codex-cli fixture\\n'; exit 0; fi
        if [ "$1" = "login" ]; then exit 0; fi
        cat >/dev/null
        printf '%s\\n' '{"type":"thread.started","thread_id":"ui-test-session"}'
        printf '%s\\n' '{"type":"item.completed","item":{"id":"reply","type":"agent_message","text":"CLI fixture reply"}}'
        """
        try script.write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
        let app = XCUIApplication()
        app.launchArguments = ["-localCLISetupComplete", setup ? "NO" : "YES", "--opengrokbot-test-cli", executable.path, "--opengrokbot-test-data", directory.appendingPathComponent("data").path, "--opengrokbot-test-setup", setup ? "1" : "0"]
        app.launchEnvironment = ["OPENGROKBOT_TEST_SETUP":setup ? "1" : "0", "OPENGROKBOT_TEST_CODEX_PATH":executable.path, "OPENGROKBOT_TEST_WORKSPACE_DIR":directory.appendingPathComponent("data").path]
        return (app, directory)
    }

    @MainActor
    func testFreshWorkspaceAndRealCLIProcessReply() throws {
        let (app, directory) = try application(setup: false)
        defer { app.terminate(); try? FileManager.default.removeItem(at: directory) }
        app.launch()
        defer { dumpLaunchDiagnostics() }
        XCTAssertTrue(app.buttons["Search Bots"].waitForExistence(timeout: 15))
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "label CONTAINS 'Soccer'")).firstMatch.exists)
        XCTAssertEqual(app.descendants(matching: .any).matching(identifier: "conversation-message").count, 0)
        capture(app, name: "macos-workspace")
        let input = app.descendants(matching: .any).matching(identifier: "chat-input").firstMatch
        XCTAssertTrue(input.waitForExistence(timeout: 10))
        input.click(); app.typeText("Hello from the UI test")
        let send = app.buttons["Send message"]
        XCTAssertTrue(send.waitForExistence(timeout: 10))
        XCTAssertTrue(send.isEnabled, app.debugDescription)
        send.click()
        let reply = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS 'CLI fixture reply'")).firstMatch
        XCTAssertTrue(reply.waitForExistence(timeout: 15), app.debugDescription)
        capture(app, name: "macos-cli-chat")
        input.click(); app.typeText("A second message")
        app.typeKey(.return, modifierFlags: .command)
        let replies = app.descendants(matching: .any).matching(identifier: "conversation-message").matching(NSPredicate(format: "label CONTAINS 'AI reply: CLI fixture reply'"))
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "count >= 2"), object: replies)], timeout: 15), .completed, app.debugDescription)
        app.buttons["Connect apps"].click()
        XCTAssertTrue(app.staticTexts["Connect Apps"].waitForExistence(timeout: 5))
        capture(app, name: "macos-connect-apps")
        app.typeKey(.escape, modifierFlags: [])
        app.typeKey(",", modifierFlags: .command)
        XCTAssertTrue(app.staticTexts["Account"].waitForExistence(timeout: 5))
        capture(app, name: "macos-settings")
    }

    @MainActor
    func testGuidedSetupWithInstalledCLI() throws {
        let (app, directory) = try application(setup: true)
        defer { app.terminate(); try? FileManager.default.removeItem(at: directory) }
        app.launch()
        defer { dumpLaunchDiagnostics() }
        XCTAssertTrue(app.staticTexts["A free app for your AI CLIs"].waitForExistence(timeout: 15), app.debugDescription)
        capture(app, name: "macos-setup")
        app.buttons["Continue"].click()
        XCTAssertTrue(app.staticTexts["Choose an AI CLI"].waitForExistence(timeout: 5))
        app.buttons["Continue"].click()
        XCTAssertTrue(app.staticTexts["Already installed"].waitForExistence(timeout: 10))
        app.buttons["Continue"].click()
        app.buttons["Check sign-in"].click()
        XCTAssertTrue(app.staticTexts["Codex is signed in and ready."].waitForExistence(timeout: 15))
        app.buttons["Continue"].click()
        XCTAssertTrue(app.secureTextFields["composio-project-key"].waitForExistence(timeout: 5))
        capture(app, name: "macos-composio-setup")
        app.buttons["Continue to chat"].click()
        app.buttons["Start chatting"].click()
        XCTAssertTrue(app.buttons["Search Bots"].waitForExistence(timeout: 5))
    }

    private func dumpLaunchDiagnostics() {
        let files = (try? FileManager.default.contentsOfDirectory(at: URL(fileURLWithPath: "/tmp"), includingPropertiesForKeys: nil)) ?? []
        for file in files where file.lastPathComponent.hasPrefix("opengrokbot-ui-") {
            print("LAUNCH DIAGNOSTICS: \((try? String(contentsOf: file, encoding: .utf8)) ?? "unreadable")")
        }
    }

    @MainActor
    private func capture(_ app: XCUIApplication, name: String) {
        Thread.sleep(forTimeInterval: 0.5)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
