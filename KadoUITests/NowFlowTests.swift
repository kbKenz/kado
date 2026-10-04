import XCTest

final class NowFlowTests: KadoUITestCase {
    @MainActor
    func testStartPauseResumeFinishDone() {
        let app = launchApp(resetState: true, startOnNow: true, seedNowBlock: true)
        let start = app.buttons[AccessibilityID.Now.start]
        XCTAssertTrue(start.waitForExistence(timeout: 15))
        capture(app, "1-suggested-current-block")
        start.tap()

        let pause = app.buttons[AccessibilityID.Now.pause]
        XCTAssertTrue(pause.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons[AccessibilityID.Now.finish].exists)
        capture(app, "2-running")
        pause.tap()

        let resume = app.buttons[AccessibilityID.Now.resume]
        XCTAssertTrue(resume.waitForExistence(timeout: 5))
        capture(app, "3-paused")
        resume.tap()
        XCTAssertTrue(pause.waitForExistence(timeout: 5))

        app.buttons[AccessibilityID.Now.finish].tap()
        let done = app.buttons[AccessibilityID.Now.finishDone].firstMatch
        XCTAssertTrue(done.waitForExistence(timeout: 5))
        done.tap()

        XCTAssertTrue(app.buttons[AccessibilityID.Now.startSomething].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons[AccessibilityID.Now.start].exists)
        XCTAssertFalse(app.buttons[AccessibilityID.Now.pause].exists)
        XCTAssertFalse(app.buttons[AccessibilityID.Now.finish].exists)
        XCTAssertFalse(app.staticTexts["Research"].exists)
        XCTAssertFalse(app.descendants(matching: .any)[AccessibilityID.Now.title].exists)
    }

    @MainActor
    func testFinishNotYetKeepsTaskSuggested() {
        let app = launchApp(resetState: true, startOnNow: true, seedNowBlock: true)
        let start = app.buttons[AccessibilityID.Now.start]
        XCTAssertTrue(start.waitForExistence(timeout: 15))
        start.tap()
        let finish = app.buttons[AccessibilityID.Now.finish]
        XCTAssertTrue(finish.waitForExistence(timeout: 5))
        finish.tap()
        let notYet = app.buttons[AccessibilityID.Now.finishNotYet].firstMatch
        XCTAssertTrue(notYet.waitForExistence(timeout: 5))
        notYet.tap()
        XCTAssertTrue(start.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons[AccessibilityID.Now.pause].exists)
        XCTAssertFalse(app.buttons[AccessibilityID.Now.finish].exists)
    }
}
