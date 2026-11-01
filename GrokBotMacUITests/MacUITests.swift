import XCTest

final class MacUITests: XCTestCase {
    @MainActor
    func testWorkspaceAndReferencePanels() {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.buttons["Search Bots"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "conversation-message").firstMatch.waitForExistence(timeout: 10))
        capture(app, name: "macos-workspace")
        app.buttons["Connect apps"].click()
        XCTAssertTrue(app.staticTexts["Connect Apps"].waitForExistence(timeout: 5))
        capture(app, name: "macos-connect-apps")
        app.typeKey(.escape, modifierFlags: [])
        app.typeKey(",", modifierFlags: .command)
        XCTAssertTrue(app.staticTexts["Account"].waitForExistence(timeout: 5))
        capture(app, name: "macos-settings")
        app.terminate()
    }

    @MainActor
    private func capture(_ app: XCUIApplication, name: String) {
        // Allow the short, interruptible panel spring to settle before capturing.
        Thread.sleep(forTimeInterval: 0.6)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
