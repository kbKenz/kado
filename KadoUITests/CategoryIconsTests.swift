import XCTest

/// The category icons on Now, Today, the Calendar and Goals, over a
/// seeded planner (`-uiTestSeedPlanner`) on top of the demo habits.
///
/// The icons are decorative, so what can be asserted is the category
/// name VoiceOver reads after each title. Every screen is captured too,
/// because a cramped row passes every assertion.
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
        expectTaskRow("Contact professors at Cambridge", reads: "Study", in: app)
        expectTaskRow("Team meeting", reads: "Work", in: app)
        expectTaskRow("Pay the electricity bill", reads: "Money", in: app)
        capture(app, "3-today")
        let weekend = taskRow("Think about the weekend", reading: "Other", in: app)
        scrollTo(weekend, in: app)
        capture(app, "4-today-inbox")

        // The Calendar: the meeting's block reads its category too. A
        // block collapses its button into a plain element, so any type.
        openCalendar(in: app)
        let meeting = app.descendants(matching: .any).matching(NSPredicate(
            format: "identifier BEGINSWITH %@ AND label CONTAINS %@ AND label CONTAINS %@",
            AccessibilityID.Calendar.blockPrefix, "Team meeting", "Work"
        )).firstMatch
        XCTAssertTrue(meeting.waitForExistence(timeout: 10), "The meeting block should read Work.")
        capture(app, "5-calendar")
        scrollTo(meeting, in: app)
        scrollClearOfTabBar(meeting, in: app)
        capture(app, "6-calendar-meeting")

        // Goals: a stored category, a guessed one, and Other.
        tapTab(.goals, in: app)
        let cambridge = goalRow("Get into Cambridge", reading: "Study", in: app)
        XCTAssertTrue(cambridge.waitForExistence(timeout: 10), "The goal row should read Study.")
        XCTAssertTrue(goalRow("Run a half marathon", reading: "Fitness", in: app).exists)
        XCTAssertTrue(goalRow("Be more present", reading: "Other", in: app).exists)
        capture(app, "7-goals")
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
    private func expectTaskRow(
        _ title: String, reads category: String, in app: XCUIApplication,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        XCTAssertTrue(
            taskRow(title, reading: category, in: app).waitForExistence(timeout: 10),
            "The \(title) row should read \(category).", file: file, line: line
        )
    }

    @MainActor
    private func goalRow(_ name: String, reading category: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(
            format: "identifier BEGINSWITH %@ AND label CONTAINS %@ AND label CONTAINS %@",
            "goals.row.", name, category
        )).firstMatch
    }
}
