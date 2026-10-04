import XCTest

/// Starting a brand-new task from an empty Now screen.
final class NowQuickStartTests: KadoUITestCase {
    @MainActor
    func testQuickStartTaskFromEmptyNow() {
        let app = launchApp(startOnNow: true)

        let startSomething = app.buttons[AccessibilityID.Now.startSomething]
        XCTAssertTrue(startSomething.waitForExistence(timeout: 15), "The empty Now screen never appeared.")
        capture(app, "1-empty-now")
        startSomething.tap()

        let field = app.textFields[AccessibilityID.Now.quickStartTitle]
        XCTAssertTrue(field.waitForExistence(timeout: 10), "The quick-start sheet never appeared.")
        let start = app.buttons[AccessibilityID.Now.quickStartStart]
        XCTAssertFalse(start.isEnabled, "Start must stay disabled while the title is empty.")
        // Tap first: programmatic focus is not guaranteed on every runtime.
        field.tap()
        field.typeText("Write report")
        XCTAssertTrue(start.isEnabled)
        capture(app, "2-quick-start-sheet")
        start.tap()

        let finish = app.buttons[AccessibilityID.Now.finish]
        XCTAssertTrue(finish.waitForExistence(timeout: 10), "Starting should open a running session.")
        capture(app, "3-running-session")
    }
}
