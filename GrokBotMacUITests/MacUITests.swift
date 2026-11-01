import Foundation
import XCTest

final class MacUITests: XCTestCase {
    @MainActor
    private func application(setup: Bool) throws -> (XCUIApplication, URL) {
        // The UI runner is sandboxed; the application must not execute a fixture inside its container.
        let directory = URL(fileURLWithPath: "/tmp/opengrokbot-app-ui-" + UUID().uuidString)
        let executable = try XCTUnwrap(Bundle(for: MacUITests.self).url(forResource: "codex-fixture", withExtension: "sh"))
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: executable.path))
        let app = XCUIApplication()
        app.launchArguments = ["-ApplePersistenceIgnoreState", "YES", "-NSQuitAlwaysKeepsWindows", "NO", "-localCLISetupComplete", setup ? "NO" : "YES", "--opengrokbot-test-cli", executable.path, "--opengrokbot-test-data", directory.appendingPathComponent("data").path, "--opengrokbot-test-setup", setup ? "1" : "0"]
        app.launchEnvironment = ["OPENGROKBOT_TEST_SETUP":setup ? "1" : "0", "OPENGROKBOT_TEST_CODEX_PATH":executable.path, "OPENGROKBOT_TEST_WORKSPACE_DIR":directory.appendingPathComponent("data").path]
        return (app, directory)
    }

    @MainActor
    func testFreshWorkspaceAndRealCLIProcessReply() throws {
        let (app, directory) = try application(setup: false)
        defer { app.terminate(); try? FileManager.default.removeItem(at: directory) }
        app.launch()
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
        verifyReply(app, at: 1)
        capture(app, name: "macos-cli-chat")
        input.click(); app.typeText("A second message")
        app.typeKey(.return, modifierFlags: .command)
        verifyReply(app, at: 3)
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

    @MainActor
    private func verifyReply(_ app: XCUIApplication, at index: Int) {
        let reply = app.staticTexts.matching(identifier: "conversation-message").element(boundBy: index)
        XCTAssertTrue(reply.waitForExistence(timeout: 15))
        let finished = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value CONTAINS %@", "CLI fixture reply"), object: reply)
        XCTAssertEqual(XCTWaiter.wait(for: [finished], timeout: 15), .completed, app.debugDescription)
    }

    @MainActor
    private func capture(_ app: XCUIApplication, name: String) {
        Thread.sleep(forTimeInterval: 0.5)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
