import XCTest

/// The day strip end to end: a strip cell is the only way to reach
/// another day, and the backfill tap happens inside a List row that a
/// unit test can't drive.
final class TodayDayStripTests: KadoUITestCase {

    @MainActor
    func testPickingYesterdayLogsThereAndTodayJumpsBack() {
        // `launchApp` resets state, so the day-start hour is 0 and
        // "yesterday" from `Calendar.current` is the habit day the strip
        // calls yesterday. Every seeded habit was created 30+ days ago
        // (`DevModeSeed`), so all of them are listed yesterday under the
        // first-day rule, and whichever row is first has a trailing
        // control: the check, `+` or `+5m`.
        let app = launchApp(seedProduction: true)
        tapTab(.today, in: app)
        waitForTodayRows(in: app)

        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: .now)!
        let cell = app.buttons[AccessibilityID.Today.dayStripCell(yesterday)].firstMatch
        XCTAssertTrue(cell.waitForExistence(timeout: 5), "Yesterday's strip cell should exist.")
        cell.tap()

        let jumpBack = app.buttons[AccessibilityID.Today.jumpToTodayButton].firstMatch
        XCTAssertTrue(jumpBack.waitForExistence(timeout: 5), "Another day shows the Today button.")

        waitForTodayRows(in: app)
        let row = todayRows(in: app).firstMatch
        let before = row.value as? String
        // Trailing edge = the check / + control; the centre would push Detail.
        row.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
        let changed = NSPredicate { _, _ in (row.value as? String) != before }
        let result = XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: changed, object: nil)], timeout: 5)
        XCTAssertEqual(result, .completed, "Logging on yesterday should change the row's value (was \(before ?? "nil")).")

        jumpBack.tap()
        XCTAssertFalse(jumpBack.waitForExistence(timeout: 2), "Back on today, the Today button goes away.")
        capture(app, "today-day-strip")
    }
}
