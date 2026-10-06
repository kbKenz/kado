import XCTest

/// Creating a task or habit from an empty Now screen with the full
/// form, which starts a session on it after Save.
final class NowQuickStartTests: KadoUITestCase {
    @MainActor
    func testNewTaskFromEmptyNowStartsSession() {
        let app = launchApp(startOnNow: true)

        let startSomething = app.buttons[AccessibilityID.Now.startSomething]
        XCTAssertTrue(startSomething.waitForExistence(timeout: 15), "The empty Now screen never appeared.")
        capture(app, "1-empty-now")
        startSomething.tap()

        let newTask = app.buttons[AccessibilityID.Now.newTask]
        XCTAssertTrue(newTask.waitForExistence(timeout: 10), "The Start something sheet never appeared.")
        capture(app, "2-start-something-sheet")
        newTask.tap()

        let field = app.textFields[AccessibilityID.Tasks.title]
        XCTAssertTrue(field.waitForExistence(timeout: 10), "The New Task form never appeared.")
        // Tap first: programmatic focus is not guaranteed on every runtime.
        field.tap()
        field.typeText("Write report")
        capture(app, "3-new-task-form")
        app.buttons[AccessibilityID.Tasks.save].firstMatch.tap()

        let pause = app.buttons[AccessibilityID.Now.pause]
        XCTAssertTrue(pause.waitForExistence(timeout: 10), "Saving the new task should open a running session.")
        capture(app, "4-running-session")
    }

    @MainActor
    func testNewHabitFromEmptyNowStartsSession() {
        let app = launchApp(startOnNow: true)

        let startSomething = app.buttons[AccessibilityID.Now.startSomething]
        XCTAssertTrue(startSomething.waitForExistence(timeout: 15), "The empty Now screen never appeared.")
        startSomething.tap()

        let newHabit = app.buttons[AccessibilityID.Now.newHabit]
        XCTAssertTrue(newHabit.waitForExistence(timeout: 10), "The Start something sheet never appeared.")
        newHabit.tap()

        let field = app.textFields[AccessibilityID.NewHabit.nameField]
        XCTAssertTrue(field.waitForExistence(timeout: 10), "The New Habit form never appeared.")
        field.tap()
        field.typeText("Stretch")
        capture(app, "5-new-habit-form")
        app.buttons[AccessibilityID.NewHabit.saveButton].firstMatch.tap()

        XCTAssertTrue(
            app.buttons[AccessibilityID.Now.pause].waitForExistence(timeout: 10),
            "Saving the new habit should open a running session."
        )
    }
}
