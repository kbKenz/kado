import XCTest

/// The category icons on Now, Today, the Calendar and Goals, over a
/// seeded planner (`-uiTestSeedPlanner`) on top of the demo habits.
///
/// The icons are decorative, so what can be asserted is the category
/// name VoiceOver reads after each title. Every screen is captured too,
/// because a cramped row passes every assertion. Rows are found by
/// scrolling, so the test also runs at large text sizes.
final class CategoryIconsTests: KadoUITestCase {

    @MainActor
    func testCategoriesReadOnNowTodayCalendarAndGoals() {
        let app = launchWithPlanner()

        // Now opens on the current block, a task guessed as Study.
        let title = app.buttons[AccessibilityID.Now.title].firstMatch
        XCTAssertTrue(title.waitForExistence(timeout: 30), "Now never showed the current block.")
        XCTAssertTrue(title.label.contains("Revise chemistry notes"), title.label)
        XCTAssertTrue(title.label.contains("Study"), title.label)
        capture(app, "1-now-suggested")
        app.buttons[AccessibilityID.Now.start].firstMatch.tap()
        XCTAssertTrue(app.buttons[AccessibilityID.Now.pause].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons[AccessibilityID.Now.title].firstMatch.label.contains("Study"))
        capture(app, "2-now-running")

        // Today: the goal gives Study, a stored category wins, the title
        // gives the rest, and a title with no match reads Other.
        tapTab(.today, in: app)
        XCTAssertTrue(
            elements(withIdentifierPrefix: AccessibilityID.Tasks.rowPrefix, in: app).firstMatch
                .waitForExistence(timeout: 10),
            "Today never showed a task."
        )
        capture(app, "3-today")
        expect(taskRow("Team meeting", reading: "Work", in: app), "Team meeting should read Work.", in: app)
        expect(taskRow("Pay the electricity bill", reading: "Money", in: app), "The bill should read Money.", in: app)
        expect(taskRow("Contact professors at Cambridge", reading: "Study", in: app),
               "The goal's task should read Study.", in: app)
        let weekend = taskRow("Think about the weekend", reading: "Other", in: app)
        expect(weekend, "A title with no match should read Other.", in: app)
        scrollTo(weekend, in: app)
        capture(app, "4-today-inbox")

        // The Calendar: the meeting reads its category too, on a timeline
        // block or, at large text sizes, on an agenda row. A block
        // collapses its button into a plain element, so any type.
        openCalendar(in: app)
        let meeting = app.descendants(matching: .any).matching(NSPredicate(
            format: "(identifier BEGINSWITH %@ OR identifier BEGINSWITH %@) AND label CONTAINS %@ AND label CONTAINS %@",
            AccessibilityID.Calendar.blockPrefix, AccessibilityID.Tasks.rowPrefix, "Team meeting", "Work"
        )).firstMatch
        capture(app, "5-calendar")
        expect(meeting, "The meeting on the Calendar should read Work.", in: app)
        scrollTo(meeting, in: app)
        scrollClearOfTabBar(meeting, in: app)
        capture(app, "6-calendar-meeting")

        // Goals: a stored category, a guessed one, and Other.
        tapTab(.goals, in: app)
        let cambridge = goalRow("Get into Cambridge", reading: "Study", in: app)
        expect(cambridge, "The stored Study should read.", in: app)
        capture(app, "7-goals")
        expect(goalRow("Run a half marathon", reading: "Fitness", in: app), "The name should give Fitness.", in: app)
        expect(goalRow("Be more present", reading: "Other", in: app), "A name with no match should read Other.", in: app)
        scrollTo(cambridge, in: app)
        cambridge.tap()
        XCTAssertTrue(app.buttons[AccessibilityID.Goals.edit].firstMatch.waitForExistence(timeout: 10))
        capture(app, "8-goal-detail")
    }

    // MARK: - Helpers

    /// `launchApp`'s English run with the demo habits, plus the planner,
    /// opening on Now. Built here: only this class needs the planner.
    @MainActor
    private func launchWithPlanner() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-uiTestRun", "-uiTestResetState", "-uiTestSeedProduction",
            "-uiTestSeedPlanner", "-uiTestStartOnNow",
            "-uiTestDevMode", "0", "-uiTestDevModeConfirmed", "1",
            "-AppleLanguages", "(en)", "-AppleLocale", "en",
        ]
        app.launch()
        return app
    }

    /// A Today or Calendar task row whose label has both the title and
    /// the category. Matched in one predicate, because a `List` row
    /// answers to its identifier twice.
    @MainActor
    private func taskRow(_ title: String, reading category: String, in app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(NSPredicate(
            format: "identifier BEGINSWITH %@ AND label CONTAINS %@ AND label CONTAINS %@",
            AccessibilityID.Tasks.rowPrefix, title, category
        )).firstMatch
    }

    @MainActor
    private func goalRow(_ name: String, reading category: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(
            format: "identifier BEGINSWITH %@ AND label CONTAINS %@ AND label CONTAINS %@",
            "goals.row.", name, category
        )).firstMatch
    }

    /// Fails unless `element` shows up, scrolling down and then back up
    /// to find it: the order of timed rows follows the clock, and at
    /// large text sizes a `List` row off screen does not exist yet.
    @MainActor
    private func expect(
        _ element: XCUIElement, _ message: String, in app: XCUIApplication,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        if element.waitForExistence(timeout: 5) { return }
        for _ in 0..<6 {
            app.swipeUp(velocity: .slow)
            if element.exists { return }
        }
        for _ in 0..<12 {
            app.swipeDown(velocity: .slow)
            if element.exists { return }
        }
        XCTFail(message, file: file, line: line)
    }
}
