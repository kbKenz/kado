import XCTest

/// Keeps `-uiTestSeedInsights` working: the Insights screen tests start
/// from this seed, so a launch that silently seeds nothing would make
/// them fail far from the cause.
final class InsightsSeedLaunchTests: KadoUITestCase {

    @MainActor
    func testInsightsSeedFillsToday() {
        let app = launchApp(seedInsights: true)
        tapTab(.today, in: app)

        // A task left open 47 days ago: always overdue, at the top of Today.
        let overdueTask = app.buttons
            .matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS %@", "task.row.", "Renew passport"))
            .firstMatch
        XCTAssertTrue(overdueTask.waitForExistence(timeout: 30), "The seeded overdue task should be on Today.")

        // Meditate is daily, so it is always on Today, below the tasks.
        let meditate = todayRows(in: app)
            .matching(NSPredicate(format: "label CONTAINS %@", "Meditate"))
            .firstMatch
        scrollTo(meditate, in: app)
    }
}
