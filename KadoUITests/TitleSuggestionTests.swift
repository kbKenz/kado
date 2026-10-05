import XCTest

/// Title suggestions, end to end. The word tier fills a new task's goal
/// and category from a title with typos, and a new habit's icon from its
/// name. UI runs inject no language model (`KadoApp` stands in
/// `UnavailableItemSuggester`), so what shows here is the word tier
/// alone and the same on every simulator.
final class TitleSuggestionTests: KadoUITestCase {
    private typealias Suggestion = AccessibilityID.Suggestion

    @MainActor
    func testTypedTaskTitleLinksTheGoalAndTheCategory() {
        let app = launchApp(suppressNameAutoFocus: true)
        createGoal(named: "Get into Cambridge", in: app)

        tapTab(.today, in: app)
        app.buttons[AccessibilityID.Today.addButton].firstMatch.tap()
        app.buttons[AccessibilityID.Today.newTaskButton].firstMatch.tap()
        let title = app.textFields[AccessibilityID.Tasks.title]
        XCTAssertTrue(title.waitForExistence(timeout: 10))
        title.tap()
        title.typeText("contact proffesors at cambrrdgige")

        // The strip shows under the title: the goal and the category,
        // both applied.
        XCTAssertTrue(element(Suggestion.strip, in: app).waitForExistence(timeout: 10), "No suggestion strip.")
        XCTAssertTrue(element(Suggestion.chip("goal"), in: app).exists)
        XCTAssertTrue(element(Suggestion.chip("category"), in: app).exists)
        XCTAssertTrue(app.buttons[Suggestion.undo].exists)
        capture(app, "suggestion-task-strip")
        dismissKeyboard(in: app)

        // The category row reads Study, marked as suggested.
        let category = element(Suggestion.taskCategory, in: app)
        scrollTo(category, in: app)
        expect(category, shows: "Study", in: app)
        XCTAssertTrue(element(Suggestion.categoryBadge, in: app).exists)

        // The goal row shows the goal, marked as suggested.
        let goal = element(AccessibilityID.Goals.picker, in: app)
        scrollTo(goal, in: app)
        expect(goal, shows: "Get into Cambridge", in: app)
        let badge = element(Suggestion.goalBadge, in: app)
        scrollTo(badge, in: app)
        XCTAssertTrue(badge.exists)
        capture(app, "suggestion-task-goal")

        let save = app.buttons[AccessibilityID.Tasks.save]
        XCTAssertTrue(save.isEnabled)
        save.tap()
        XCTAssertTrue(title.waitForNonExistence(timeout: 10))

        // Reopened, the task keeps the goal and the category, now as
        // saved values: no "Suggested" marks.
        let row = app.buttons.matching(NSPredicate(
            format: "identifier BEGINSWITH %@ AND label CONTAINS %@",
            AccessibilityID.Tasks.rowPrefix, "cambrrdgige"
        )).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10), "The new task is not in Today.")
        row.tap()
        XCTAssertTrue(title.waitForExistence(timeout: 10))
        let savedCategory = element(Suggestion.taskCategory, in: app)
        scrollTo(savedCategory, in: app)
        expect(savedCategory, shows: "Study", in: app)
        XCTAssertFalse(element(Suggestion.categoryBadge, in: app).exists)
        let savedGoal = element(AccessibilityID.Goals.picker, in: app)
        scrollTo(savedGoal, in: app)
        expect(savedGoal, shows: "Get into Cambridge", in: app)
        XCTAssertFalse(element(Suggestion.goalBadge, in: app).exists)
        capture(app, "suggestion-task-reopened")
        app.buttons[AccessibilityID.Tasks.cancel].tap()
    }

    @MainActor
    func testHabitNameSuggestsItsIcon() {
        let app = launchApp(suppressNameAutoFocus: true)
        tapTab(.today, in: app)
        app.buttons[AccessibilityID.Today.addButton].firstMatch.tap()
        app.buttons[AccessibilityID.Today.newHabitButton].firstMatch.tap()
        let name = app.textFields[AccessibilityID.NewHabit.nameField]
        XCTAssertTrue(name.waitForExistence(timeout: 10))
        name.tap()
        name.typeText("Read 20 pages")

        XCTAssertTrue(element(Suggestion.chip("icon"), in: app).waitForExistence(timeout: 10), "No icon chip.")
        capture(app, "suggestion-habit-strip")
        dismissKeyboard(in: app)

        let book = app.buttons["book.fill"].firstMatch
        scrollTo(book, in: app)
        XCTAssertTrue(book.isSelected, "The book icon is not the selected one.")
        let badge = element(Suggestion.iconBadge, in: app)
        scrollTo(badge, in: app)
        XCTAssertTrue(badge.exists)
        capture(app, "suggestion-habit-icon")

        // Undo, back at the top of the form, puts the circle back.
        let undo = app.buttons[Suggestion.undo]
        scrollBackTo(undo, in: app)
        undo.tap()
        XCTAssertTrue(element(Suggestion.strip, in: app).waitForNonExistence(timeout: 5))
        scrollTo(book, in: app)
        XCTAssertFalse(book.isSelected)
        app.buttons[AccessibilityID.NewHabit.cancelButton].tap()
    }

    @MainActor
    func testAddTaskFromGoalDetailStartsOnTheGoal() {
        let app = launchApp(suppressNameAutoFocus: true)
        createGoal(named: "Get into Cambridge", in: app)

        let add = app.buttons[AccessibilityID.Goals.addTask]
        scrollTo(add, in: app)
        add.tap()
        let title = app.textFields[AccessibilityID.Tasks.title]
        XCTAssertTrue(title.waitForExistence(timeout: 10))
        let goal = element(AccessibilityID.Goals.picker, in: app)
        scrollTo(goal, in: app)
        expect(goal, shows: "Get into Cambridge", in: app)
        // The person's choice, not a suggestion.
        XCTAssertFalse(element(Suggestion.goalBadge, in: app).exists)
        capture(app, "suggestion-task-from-goal")
        app.buttons[AccessibilityID.Tasks.cancel].tap()
    }

    // MARK: - Helpers

    /// Creates a goal from the Goals tab. The tab pushes the new goal's
    /// detail after Save.
    @MainActor
    private func createGoal(named name: String, in app: XCUIApplication) {
        tapTab(.goals, in: app)
        let new = app.buttons[AccessibilityID.Goals.newGoal].firstMatch
        XCTAssertTrue(new.waitForExistence(timeout: 10))
        new.tap()
        let field = app.textFields[AccessibilityID.Goals.name]
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.tap()
        field.typeText(name)
        app.buttons[AccessibilityID.Goals.save].tap()
        XCTAssertTrue(field.waitForNonExistence(timeout: 10), "The goal form should close after Save.")
    }

    /// `scrollTo`'s opposite: swipes down until `element` can be tapped.
    @MainActor
    private func scrollBackTo(_ element: XCUIElement, in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        for _ in 0..<6 where !(element.exists && element.isHittable) {
            app.swipeDown(velocity: .slow)
        }
        XCTAssertTrue(element.exists && element.isHittable, "Never scrolled back to \(element).", file: file, line: line)
    }

    @MainActor
    private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)[identifier].firstMatch
    }

    @MainActor
    private func dismissKeyboard(in app: XCUIApplication) {
        let done = app.keyboards.buttons["Done"]
        if done.exists { done.tap() }
    }

    /// The row's label, value or a text inside it names `text`: a menu
    /// picker reports its choice in one of these depending on what the
    /// choice is drawn with. Dumps the hierarchy when none does.
    @MainActor
    private func expect(
        _ element: XCUIElement, shows text: String, in app: XCUIApplication,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        let value = element.value as? String ?? ""
        guard !element.label.contains(text), !value.contains(text),
              !element.staticTexts[text].exists
        else { return }
        let dump = XCTAttachment(string: app.debugDescription)
        dump.name = "hierarchy-\(element.identifier)"
        dump.lifetime = .keepAlways
        add(dump)
        XCTFail("\(element.identifier) shows “\(element.label)” / “\(value)”, not “\(text)”.", file: file, line: line)
    }
}
