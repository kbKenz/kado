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
        XCTAssertEqual(app.switches[AccessibilityID.Tasks.hasDay].value as? String, "0")
        XCTAssertFalse(app.switches[AccessibilityID.Tasks.hasStart].exists)
        XCTAssertFalse(app.switches[AccessibilityID.Tasks.hasEnd].exists)
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
        XCTAssertEqual(app.switches[AccessibilityID.Tasks.hasDay].value as? String, "1")
        XCTAssertEqual(app.switches[AccessibilityID.Tasks.hasStart].value as? String, "0")
        XCTAssertEqual(app.switches[AccessibilityID.Tasks.hasEnd].value as? String, "0")
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
        toggle(AccessibilityID.Tasks.hasStart, in: app)
        XCTAssertEqual(app.switches[AccessibilityID.Tasks.hasEnd].value as? String, "0")
        saveTask(in: app)

        let block = elements(withIdentifierPrefix: AccessibilityID.Calendar.blockPrefix, in: app).firstMatch
        scrollTo(block, in: app)
        XCTAssertTrue(block.label.contains("Deep work"))
        block.tap()
        XCTAssertTrue(app.textFields[AccessibilityID.Tasks.title].waitForExistence(timeout: 10))
        XCTAssertEqual(app.switches[AccessibilityID.Tasks.hasStart].value as? String, "1")
        XCTAssertEqual(app.switches[AccessibilityID.Tasks.hasEnd].value as? String, "0")
        capture(app, "task-start-only")
    }

    @MainActor
    func testEndOnlyTaskAppearsUnderAnyTimeAndKeepsOptionalStart() {
        let app = launchApp(suppressNameAutoFocus: true)
        tapTab(.calendar, in: app)
        app.buttons[AccessibilityID.Calendar.newTask].tap()
        enterTitle("Submit application", in: app)
        toggle(AccessibilityID.Tasks.hasEnd, in: app)
        XCTAssertEqual(app.switches[AccessibilityID.Tasks.hasStart].value as? String, "0")
        saveTask(in: app)

        let row = taskRow(named: "Submit application", in: app)
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        XCTAssertTrue(row.label.contains("Ends at"))
        row.tap()
        XCTAssertTrue(app.textFields[AccessibilityID.Tasks.title].waitForExistence(timeout: 10))
        XCTAssertEqual(app.switches[AccessibilityID.Tasks.hasStart].value as? String, "0")
        XCTAssertEqual(app.switches[AccessibilityID.Tasks.hasEnd].value as? String, "1")
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

    @MainActor
    private func toggle(_ identifier: String, in app: XCUIApplication) {
        let row = app.switches[identifier]
        scrollTo(row, in: app)
        let control = row.switches.firstMatch
        (control.exists ? control : row).tap()
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
