import XCTest

/// The monthly check-in end to end: open it from Overview › Reflect,
/// rate, write a word, skip to the end, finish, and read it back.
final class ReflectTests: KadoUITestCase {
    @MainActor
    func testCheckInFromStartToMonthView() {
        let app = launchApp()
        openOverviewReflect(in: app)

        let empty = app.descendants(matching: .any)[AccessibilityID.Reflect.empty].firstMatch
        XCTAssertTrue(empty.waitForExistence(timeout: 10), "Reflect never showed its empty state.")
        capture(app, "1-reflect-empty")
        app.buttons[AccessibilityID.Reflect.checkInButton].tap()

        let next = app.buttons[AccessibilityID.Reflect.next]
        XCTAssertTrue(next.waitForExistence(timeout: 10), "The check-in never opened.")
        capture(app, "2-intro")
        next.tap()

        // Ratings: overall 7.
        let seven = app.buttons[AccessibilityID.Reflect.ratingValue("rating.overall", 7)]
        XCTAssertTrue(seven.waitForExistence(timeout: 5))
        seven.tap()
        capture(app, "3-ratings")
        next.tap()

        // The word of the month.
        let word = app.textFields[AccessibilityID.Reflect.answer("core.word")]
        XCTAssertTrue(word.waitForExistence(timeout: 5))
        word.tap()
        word.typeText("Steady")
        capture(app, "4-word")
        next.tap()

        // Skip the rest to the last screen.
        let finish = app.buttons[AccessibilityID.Reflect.finish]
        for _ in 0..<20 where !finish.exists {
            next.tap()
        }
        XCTAssertTrue(finish.waitForExistence(timeout: 5), "The check-in never reached its last screen.")
        capture(app, "5-finish")
        finish.tap()

        // Back on Reflect, the month is listed with its word.
        let row = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'reflect.month.'")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10), "The finished month is not listed.")
        XCTAssertTrue(row.label.contains("Steady"), row.label)
        capture(app, "6-months")
        row.tap()

        XCTAssertTrue(app.staticTexts["“Steady”"].waitForExistence(timeout: 10), "The month view does not show the word.")
        capture(app, "7-month-view")
    }

    @MainActor
    func testQuestionsAndTrendsShowAfterACheckIn() {
        let app = launchApp()
        openOverviewReflect(in: app)
        let start = app.buttons[AccessibilityID.Reflect.checkInButton]
        XCTAssertTrue(start.waitForExistence(timeout: 10))
        start.tap()
        let next = app.buttons[AccessibilityID.Reflect.next]
        XCTAssertTrue(next.waitForExistence(timeout: 10))
        next.tap()
        app.buttons[AccessibilityID.Reflect.ratingValue("rating.overall", 4)].tap()
        // Leaving keeps the answer: the card offers to continue.
        app.buttons[AccessibilityID.Reflect.close].tap()

        let picker = app.segmentedControls[AccessibilityID.Reflect.archivePicker].firstMatch
        XCTAssertTrue(picker.waitForExistence(timeout: 10), "One answer should show the archive.")
        picker.buttons.element(boundBy: 1).tap()
        let overall = app.buttons[AccessibilityID.Reflect.questionRow("rating.overall")]
        XCTAssertTrue(overall.waitForExistence(timeout: 5))
        capture(app, "1-questions")
        overall.tap()
        let answer = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS '4 / 10'")).firstMatch
        XCTAssertTrue(answer.waitForExistence(timeout: 10))
        capture(app, "2-overall-history")
    }

    @MainActor
    private func openOverviewReflect(in app: XCUIApplication) {
        tapTab(.overview, in: app)
        let picker = app.segmentedControls[AccessibilityID.Insights.modePicker].firstMatch
        XCTAssertTrue(picker.waitForExistence(timeout: 10), "Overview never showed its mode switch.")
        picker.buttons.element(boundBy: 3).tap()
    }
}
