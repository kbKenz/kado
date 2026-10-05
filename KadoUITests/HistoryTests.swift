import XCTest

/// Overview's History mode, end to end, on the Insights seed: months of
/// habit records, completed tasks and sessions in the real store.
final class HistoryTests: KadoUITestCase {

    @MainActor
    func testHistoryShowsDaysFiltersAndLoadsMoreOnScroll() {
        let app = launchApp(seedInsights: true)
        openOverviewHistory(in: app)

        let firstDay = elements(withIdentifierPrefix: "history.day.", in: app).firstMatch
        XCTAssertTrue(firstDay.waitForExistence(timeout: 15), "History should show a day header.")
        let firstEntry = elements(withIdentifierPrefix: "history.entry.", in: app).firstMatch
        XCTAssertTrue(firstEntry.waitForExistence(timeout: 5), "History should show what was done on that day.")
        capture(app, "history-1-top")

        // Tasks only: every row left is a task or time on a task.
        let tasks = app.buttons[AccessibilityID.History.kind("tasks")]
        XCTAssertTrue(tasks.waitForExistence(timeout: 5))
        tasks.tap()
        XCTAssertTrue(firstEntry.waitForExistence(timeout: 5), "The seed has completed tasks.")
        XCTAssertEqual(
            elements(withIdentifierPrefix: "history.entry.habit-", in: app).count, 0,
            "The Tasks chip should hide habit records."
        )
        capture(app, "history-2-tasks")
        app.buttons[AccessibilityID.History.kind("all")].tap()

        // Scrolling past the first page loads older days.
        let shownBefore = elements(withIdentifierPrefix: "history.day.", in: app).count
        for _ in 0..<8 { app.swipeUp(velocity: .fast) }
        capture(app, "history-3-scrolled")
        let identifiers = Set(elements(withIdentifierPrefix: "history.day.", in: app).allElementsBoundByIndex.map(\.identifier))
        XCTAssertGreaterThan(identifiers.count, 0)
        XCTAssertNotEqual(
            identifiers, [firstDay.identifier],
            "Scrolling should bring other days in (\(shownBefore) on the first screen)."
        )

        // Oldest first puts the first day of the record on top.
        let sort = app.buttons[AccessibilityID.History.sortMenu]
        XCTAssertTrue(sort.waitForExistence(timeout: 5))
        sort.tap()
        let oldest = app.buttons["Oldest first"]
        XCTAssertTrue(oldest.waitForExistence(timeout: 5))
        oldest.tap()
        XCTAssertTrue(
            elements(withIdentifierPrefix: "history.day.", in: app).firstMatch.waitForExistence(timeout: 10)
        )
        // A new order starts at the top, with the chips in view.
        let all = app.buttons[AccessibilityID.History.kind("all")]
        let atTop = all.waitForExistence(timeout: 5)
        capture(app, "history-4-oldest-first")
        XCTAssertTrue(atTop, "A new sort order should scroll back to the top.")
    }

    @MainActor
    func testAnEmptyStoreSaysWhereHistoryComesFrom() {
        let app = launchApp()
        openOverviewHistory(in: app)
        let empty = app.descendants(matching: .any)
            .matching(identifier: AccessibilityID.History.empty)
            .firstMatch
        XCTAssertTrue(empty.waitForExistence(timeout: 10), "An empty store should show History's first-run state.")
        capture(app, "history-empty")
    }
}
