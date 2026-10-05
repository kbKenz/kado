import XCTest

/// The Insights feed on the Overview tab, end to end.
///
/// The calculator is not wired to the store yet, so the filled run
/// launches with `-uiTestInsightsFixture`: the feed then draws
/// `InsightsPreviewData.rich`, and every card has something to show.
/// The run photographs each card on the way down, for a look at the
/// layout, and ends on the Grid, which still needs the seeded habits.
final class InsightsFeedTests: KadoUITestCase {

    /// Feed order, as `InsightsCardKind` names them.
    private let cards = [
        "pulse", "highlights", "activity", "focus", "categories", "sleep",
        "movement", "habits", "tasks", "goals", "rhythm", "allTime",
    ]

    @MainActor
    func testTheFeedShowsEveryCardAndSwitchesToTheGrid() {
        let app = launchApp(seedProduction: true, insightsFixture: true)
        tapTab(.overview, in: app)

        let period = app.segmentedControls[AccessibilityID.Insights.periodPicker].firstMatch
        XCTAssertTrue(period.waitForExistence(timeout: 10), "The period picker never appeared.")
        XCTAssertTrue(
            cardTitle("pulse", in: app).waitForExistence(timeout: 10),
            "Overview should open on Insights, with the Pulse card first."
        )
        capture(app, "insights-1-top")

        // Week, then Year: each period redraws the same cards.
        period.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(cardTitle("pulse", in: app).waitForExistence(timeout: 5))
        capture(app, "insights-week-top")
        period.buttons.element(boundBy: 2).tap()
        XCTAssertTrue(cardTitle("pulse", in: app).waitForExistence(timeout: 5))
        capture(app, "insights-year-top")
        for name in ["activity", "focus", "sleep"] {
            showCard(name, in: app)
            capture(app, "insights-year-\(name)")
        }

        // Back to Month, then down the whole feed.
        scrollBack(to: period, in: app)
        period.buttons.element(boundBy: 1).tap()
        for (index, name) in cards.enumerated() {
            showCard(name, in: app)
            capture(app, "insights-\(index + 2)-\(name)")
        }
        app.swipeUp(velocity: .slow)
        capture(app, "insights-14-bottom")

        // The switch above the feed stays on screen, and Grid brings
        // back the matrix.
        let mode = app.segmentedControls[AccessibilityID.Insights.modePicker].firstMatch
        XCTAssertTrue(mode.exists, "The Insights / History / Grid switch should stay above the feed.")
        mode.buttons.element(boundBy: 2).tap()
        let label = elements(withIdentifierPrefix: "overview.label.", in: app).firstMatch
        XCTAssertTrue(label.waitForExistence(timeout: 10), "The Grid should show the habit labels.")
        capture(app, "insights-grid")
    }

    /// A store with nothing in it has nothing to summarize: the feed
    /// says where insights come from instead of drawing empty cards.
    @MainActor
    func testAnEmptyStoreShowsTheFirstRunState() {
        let app = launchApp()
        tapTab(.overview, in: app)

        let empty = app.descendants(matching: .any)
            .matching(identifier: AccessibilityID.Insights.empty)
            .firstMatch
        XCTAssertTrue(empty.waitForExistence(timeout: 10), "An empty store should show the first-run state.")
        XCTAssertFalse(cardTitle("pulse", in: app).exists, "An empty store should draw no card.")
        capture(app, "insights-empty")
    }

    // MARK: - Driving

    /// A card's title, which carries the card's identifier.
    @MainActor
    private func cardTitle(_ name: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)
            .matching(identifier: AccessibilityID.Insights.card(name))
            .firstMatch
    }

    /// Scrolls a card's title into view, then drags it up to just below
    /// the Insights / Grid switch, so the capture shows the card rather
    /// than its title alone at the bottom of the screen.
    @MainActor
    private func showCard(_ name: String, in app: XCUIApplication) {
        let title = cardTitle(name, in: app)
        scrollTo(title, in: app, swipes: 15)
        let window = app.windows.firstMatch.frame
        let switchBottom = app.segmentedControls[AccessibilityID.Insights.modePicker].firstMatch.frame.maxY
        let target = max(switchBottom, window.minY) + 24
        for _ in 0..<3 {
            guard title.exists else { return }
            let distance = title.frame.minY - target
            guard distance > 12 else { return }
            // A slow drag held at the end does not coast, so the feed
            // moves by the drag's length and no further.
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.85))
            let end = start.withOffset(CGVector(dx: 0, dy: -min(distance, window.height * 0.6)))
            start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.3)
            // At the bottom of the feed nothing moves any more.
            if title.exists, abs(title.frame.minY - target - distance) < 1 { return }
        }
    }

    /// Swipes down until `element` can be tapped again.
    @MainActor
    private func scrollBack(to element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<15 {
            if element.exists && element.isHittable { return }
            app.swipeDown(velocity: .fast)
        }
        XCTAssertTrue(element.exists && element.isHittable, "Never scrolled back to \(element).")
    }
}
