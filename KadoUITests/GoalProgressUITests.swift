import XCTest

final class GoalProgressUITests: KadoUITestCase {
    @MainActor
    func testManualProgressPersistsAndCanBeEdited() {
        let app = launchApp(suppressNameAutoFocus: true)
        tapTab(.goals, in: app)
        app.buttons[AccessibilityID.Goals.newGoal].tap()
        let name = app.textFields[AccessibilityID.Goals.name]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap(); name.typeText("Read 100 pages")
        if app.keyboards.buttons["Done"].exists { app.keyboards.buttons["Done"].tap() }
        app.swipeUp()
        let enable = app.switches["goal.measurement.enabled"]
        scrollTo(enable, in: app); enable.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        XCTAssertEqual(enable.value as? String, "1")
        let target = app.textFields["goal.measurement.target"]
        scrollTo(target, in: app); target.tap(); target.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 8) + "100")
        let unit = app.textFields["goal.measurement.unit"]
        scrollTo(unit, in: app); unit.tap(); unit.typeText("pages")
        app.buttons[AccessibilityID.Goals.save].tap()
        let add = app.buttons["goal.progress.add"]
        XCTAssertTrue(add.waitForExistence(timeout: 10)); add.tap()
        let amount = app.textFields["goal.progress.amount"]
        XCTAssertTrue(amount.waitForExistence(timeout: 5)); amount.tap()
        amount.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 8) + "abc")
        XCTAssertFalse(app.buttons["goal.progress.save"].isEnabled)
        amount.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 8) + "5")
        app.buttons["goal.progress.save"].tap()
        let total = app.staticTexts["goal.progress.total"]
        XCTAssertTrue(total.waitForExistence(timeout: 5))
        XCTAssertTrue(total.label.contains("5 / 100"), total.label)
        capture(app, "goal-progress-manual")
        app.terminate()
        let reopened = launchApp(resetState: false, suppressNameAutoFocus: true)
        tapTab(.goals, in: reopened)
        reopened.staticTexts["Read 100 pages"].firstMatch.tap()
        XCTAssertTrue(reopened.staticTexts["goal.progress.total"].waitForExistence(timeout: 5))
        XCTAssertTrue(reopened.staticTexts["goal.progress.total"].label.contains("5 / 100"))
        let row = reopened.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "goal.progress.entry.")).firstMatch
        scrollTo(row, in: reopened); row.tap()
        let edited = reopened.textFields["goal.progress.amount"]
        XCTAssertTrue(edited.waitForExistence(timeout: 5)); edited.tap()
        edited.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 8) + "8")
        reopened.buttons["goal.progress.save"].tap()
        XCTAssertTrue(reopened.staticTexts["goal.progress.total"].waitForExistence(timeout: 5))
        XCTAssertTrue(reopened.staticTexts["goal.progress.total"].label.contains("8 / 100" ))
        reopened.buttons[AccessibilityID.Goals.actions].tap()
        reopened.buttons[AccessibilityID.Goals.archive].tap()
        reopened.buttons[AccessibilityID.Goals.edit].tap()
        // Archived: the start date row is read-only — shown, no add button.
        let startDateRow = reopened.descendants(matching: .any)[AccessibilityID.Goals.startDate].firstMatch
        scrollTo(startDateRow, in: reopened)
        XCTAssertTrue(startDateRow.exists)
        XCTAssertFalse(reopened.buttons[AccessibilityID.OptionalDate.add(AccessibilityID.Goals.startDate)].exists)
        capture(reopened, "goal-progress-archived-form")
        reopened.buttons[AccessibilityID.Goals.cancel].tap()
    }
}
