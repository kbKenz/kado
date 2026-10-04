import XCTest

/// These cover the seams a pure schedule validator cannot: adding a
/// task through the sheets and one completion appearing in both tabs.
final class TaskCalendarTests: KadoUITestCase {
    @MainActor
    func testInboxTaskNeedsNoDayOrTimes() {
        let app = launchApp(suppressNameAutoFocus: true)
        tapTab(.today, in: app)
        app.buttons[AccessibilityID.Today.addButton].firstMatch.tap()
        app.buttons[AccessibilityID.Today.newTaskButton].firstMatch.tap()
        enterTitle("Buy groceries", in: app)
        // No day yet: the quick picks are offered, and no time rows
        // exist without a day.
        expectButton(OptionalDate.quick(Tasks.day, "today"), in: app)
        XCTAssertFalse(app.buttons[OptionalDate.add(Tasks.start)].exists)
        XCTAssertFalse(app.buttons[OptionalDate.add(Tasks.end)].exists)
        saveTask(in: app)

        let row = taskRow(named: "Buy groceries", in: app)
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        capture(app, "today-task-inbox")
        tapTab(.calendar, in: app)
        XCTAssertFalse(taskRow(named: "Buy groceries", in: app).exists)
    }

    @MainActor
    func testAnyTimeCalendarTaskSharesCompletionWithTodayAndSurvivesRelaunch() {
        let app = launchApp(suppressNameAutoFocus: true)
        tapTab(.calendar, in: app)
        app.buttons[AccessibilityID.Calendar.newTask].tap()
        enterTitle("Plan tomorrow", in: app)
        // Opened from Calendar: the day is set, times are not.
        expectButton(OptionalDate.clear(Tasks.day), in: app)
        expectButton(OptionalDate.add(Tasks.start), in: app)
        expectButton(OptionalDate.add(Tasks.end), in: app)
        saveTask(in: app)

        let row = taskRow(named: "Plan tomorrow", in: app)
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        guard let id = taskID(of: row) else { return }
        app.buttons[AccessibilityID.Tasks.complete(id)].firstMatch.tap()
        expectTask(id, completed: true, in: app)

        tapTab(.today, in: app)
        expectTask(id, completed: true, in: app)
        app.buttons[AccessibilityID.Tasks.complete(id)].firstMatch.tap()
        expectTask(id, completed: false, in: app)
        tapTab(.calendar, in: app)
        expectTask(id, completed: false, in: app)
        capture(app, "calendar-any-time-task")

        app.terminate()
        let relaunched = launchApp(resetState: false, suppressNameAutoFocus: true)
        tapTab(.calendar, in: relaunched)
        expectTask(id, completed: false, in: relaunched)
    }

    @MainActor
    func testStartOnlyTaskAppearsOnTimelineAndKeepsOptionalEnd() {
        let app = launchApp(suppressNameAutoFocus: true)
        tapTab(.calendar, in: app)
        app.buttons[AccessibilityID.Calendar.newTask].tap()
        enterTitle("Deep work", in: app)
        tapButton(OptionalDate.add(Tasks.start), in: app)
        expectButton(OptionalDate.clear(Tasks.start), in: app)
        expectButton(OptionalDate.add(Tasks.end), in: app)
        saveTask(in: app)

        let block = elements(withIdentifierPrefix: AccessibilityID.Calendar.blockPrefix, in: app).firstMatch
        scrollTo(block, in: app)
        XCTAssertTrue(block.label.contains("Deep work"))
        block.tap()
        XCTAssertTrue(app.textFields[AccessibilityID.Tasks.title].waitForExistence(timeout: 10))
        expectButton(OptionalDate.clear(Tasks.start), in: app)
        expectButton(OptionalDate.add(Tasks.end), in: app)
        capture(app, "task-start-only")
    }

    @MainActor
    func testEndOnlyTaskAppearsUnderAnyTimeAndKeepsOptionalStart() {
        let app = launchApp(suppressNameAutoFocus: true)
        tapTab(.calendar, in: app)
        app.buttons[AccessibilityID.Calendar.newTask].tap()
        enterTitle("Submit application", in: app)
        tapButton(OptionalDate.add(Tasks.end), in: app)
        expectButton(OptionalDate.clear(Tasks.end), in: app)
        expectButton(OptionalDate.add(Tasks.start), in: app)
        saveTask(in: app)

        let row = taskRow(named: "Submit application", in: app)
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        XCTAssertTrue(row.label.contains("Ends at"))
        row.tap()
        XCTAssertTrue(app.textFields[AccessibilityID.Tasks.title].waitForExistence(timeout: 10))
        expectButton(OptionalDate.add(Tasks.start), in: app)
        expectButton(OptionalDate.clear(Tasks.end), in: app)
        capture(app, "task-end-only")
    }

    @MainActor
    private func enterTitle(_ title: String, in app: XCUIApplication) {
        let field = app.textFields[AccessibilityID.Tasks.title]
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.tap()
        field.typeText(title)
        // Dismiss the keyboard so optional schedule controls remain
        // reachable on a compact phone.
        if app.keyboards.buttons["Done"].exists { app.keyboards.buttons["Done"].tap() }
    }

    @MainActor
    private func saveTask(in app: XCUIApplication) {
        let save = app.buttons[AccessibilityID.Tasks.save]
        XCTAssertTrue(save.isEnabled)
        save.tap()
        XCTAssertTrue(app.textFields[AccessibilityID.Tasks.title].waitForNonExistence(timeout: 10))
    }

    private typealias OptionalDate = AccessibilityID.OptionalDate
    private typealias Tasks = AccessibilityID.Tasks

    /// Scrolls first: a `Form` row below the fold is not in the
    /// hierarchy, so a bare `exists` would fail (or an absence check
    /// pass) for the wrong reason.
    @MainActor
    private func expectButton(_ identifier: String, in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        let button = app.buttons[identifier]
        scrollTo(button, in: app, file: file, line: line)
        XCTAssertTrue(button.exists, "Missing \(identifier)", file: file, line: line)
    }

    @MainActor
    private func tapButton(_ identifier: String, in app: XCUIApplication) {
        let button = app.buttons[identifier]
        scrollTo(button, in: app)
        button.tap()
    }

    @MainActor
    private func taskRow(named title: String, in app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS %@", AccessibilityID.Tasks.rowPrefix, title)).firstMatch
    }

    @MainActor
    private func taskID(of row: XCUIElement) -> UUID? {
        let id = UUID(uuidString: String(row.identifier.dropFirst(AccessibilityID.Tasks.rowPrefix.count)))
        XCTAssertNotNil(id)
        return id
    }

    @MainActor
    private func expectTask(_ id: UUID, completed: Bool, in app: XCUIApplication) {
        let row = app.buttons[AccessibilityID.Tasks.row(id)].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", completed ? "Complete" : "Incomplete"), object: row)
        XCTAssertEqual(XCTWaiter().wait(for: [expectation], timeout: 5), .completed)
    }
}
