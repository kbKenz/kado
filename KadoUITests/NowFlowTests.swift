import XCTest

final class NowFlowTests: KadoUITestCase {
    @MainActor
    func testStartPauseContinueDone() {
        let app = launchApp(resetState: true, startOnNow: true, seedNowBlock: true)
        let start = app.buttons[AccessibilityID.Now.start]
        XCTAssertTrue(start.waitForExistence(timeout: 15))
        capture(app, "1-suggested-current-block")
        start.tap()

        let pause = app.buttons[AccessibilityID.Now.pause]
        XCTAssertTrue(pause.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons[AccessibilityID.Now.done].exists)
        capture(app, "2-running")
        pause.tap()

        // Paused work is listed with a button to continue it.
        let resume = continueButtons(app).firstMatch
        XCTAssertTrue(resume.waitForExistence(timeout: 5))
        XCTAssertEqual(continueButtons(app).count, 1)
        XCTAssertFalse(pause.exists)
        capture(app, "3-paused")
        resume.tap()
        XCTAssertTrue(pause.waitForExistence(timeout: 5))
        XCTAssertEqual(continueButtons(app).count, 0)

        app.buttons[AccessibilityID.Now.done].tap()

        XCTAssertTrue(app.buttons[AccessibilityID.Now.startSomething].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons[AccessibilityID.Now.start].exists)
        XCTAssertFalse(app.buttons[AccessibilityID.Now.pause].exists)
        XCTAssertFalse(app.buttons[AccessibilityID.Now.done].exists)
        XCTAssertEqual(continueButtons(app).count, 0)
        XCTAssertFalse(app.staticTexts["Research"].exists)
    }

    /// Several things in progress at once: starting another item pauses
    /// the running one, and either can be continued later.
    @MainActor
    func testSwitchBetweenTwoTasks() {
        let app = launchApp(resetState: true, startOnNow: true, seedNowBlock: true)
        let start = app.buttons[AccessibilityID.Now.start]
        XCTAssertTrue(start.waitForExistence(timeout: 15))
        start.tap()
        let pause = app.buttons[AccessibilityID.Now.pause]
        XCTAssertTrue(pause.waitForExistence(timeout: 5))

        app.buttons[AccessibilityID.Now.startSomething].tap()
        let outreach = app.buttons.matching(NSPredicate(
            format: "identifier BEGINSWITH 'now.candidate.' AND label CONTAINS 'Outreach'"
        )).firstMatch
        XCTAssertTrue(outreach.waitForExistence(timeout: 10), "The Start something sheet never listed Outreach.")
        outreach.tap()

        // Outreach runs; Research waits in the paused list.
        XCTAssertTrue(pause.waitForExistence(timeout: 10))
        let title = app.buttons[AccessibilityID.Now.title].firstMatch
        XCTAssertTrue(title.label.contains("Outreach"), title.label)
        XCTAssertTrue(continueButtons(app).firstMatch.waitForExistence(timeout: 5))
        XCTAssertEqual(continueButtons(app).count, 1)
        capture(app, "1-switched")

        // Switching back pauses Outreach.
        continueButtons(app).firstMatch.tap()
        let back = NSPredicate(format: "label CONTAINS 'Research'")
        expectation(for: back, evaluatedWith: app.buttons[AccessibilityID.Now.title].firstMatch)
        waitForExpectations(timeout: 10)
        XCTAssertEqual(continueButtons(app).count, 1)
        capture(app, "2-switched-back")

        // Done on Research leaves Outreach paused and nothing running.
        app.buttons[AccessibilityID.Now.done].tap()
        XCTAssertTrue(continueButtons(app).firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons[AccessibilityID.Now.pause].exists)
        capture(app, "3-one-paused")
    }

    private func continueButtons(_ app: XCUIApplication) -> XCUIElementQuery {
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'now.paused.continue.'"))
    }
}
