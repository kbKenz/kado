import Foundation
import Testing
@testable import Kado
import KadoCore

/// Which Insights cards a report shows, how the heat map lays out its
/// days, and the fixtures the previews and the UI suite share.
@Suite("Insights card rules")
@MainActor
struct InsightsCardRulesTests {

    @Test("Card names are the identifiers the UI suite asks for, in feed order")
    func names() {
        #expect(InsightsCardKind.allCases.map(\.rawValue) == [
            "pulse", "highlights", "activity", "focus", "categories", "sleep",
            "movement", "habits", "tasks", "goals", "rhythm", "allTime",
        ])
    }

    @Test("An empty report shows no card: the feed shows its first-run state")
    func emptyReport() {
        #expect(InsightsCardKind.visible(in: InsightsPreviewData.empty).isEmpty)
    }

    @Test("A rich report shows every card, whatever the period", arguments: InsightsPeriod.allCases)
    func richReport(period: InsightsPeriod) {
        #expect(InsightsCardKind.visible(in: InsightsPreviewData.rich(for: period)) == InsightsCardKind.allCases)
    }

    @Test("With nothing to show, only Focus, Sleep and Movement stay, to explain")
    func bareReport() {
        let report = InsightsReport(period: .week, days: [], isEmpty: false)
        #expect(InsightsCardKind.visible(in: report) == [.focus, .sleep, .movement])
    }

    @Test("A new user's report shows only the cards it has something for")
    func sparseReport() {
        #expect(InsightsCardKind.visible(in: InsightsPreviewData.sparse) == [
            .pulse, .activity, .focus, .categories, .sleep, .movement, .habits, .tasks, .rhythm, .allTime,
        ])
    }

    @Test("Open overdue tasks alone keep the Tasks card")
    func overdueTasksOnly() {
        var report = InsightsReport(period: .month, days: [], isEmpty: false)
        report.tasks = InsightsTasks(overdueOpen: 2)
        #expect(InsightsCardKind.visible(in: report).contains(.tasks))
    }

    @Test("The heat map needs a day with a habit due, not just tasks done")
    func activityNeedsHabitDays() {
        let day = InsightsTestSupport.day(0)
        var report = InsightsReport(period: .week, days: [day], isEmpty: false)
        report.activity = InsightsActivity(days: [InsightsActivityDay(date: day, habitFraction: nil, tasksDone: 3)])
        #expect(!InsightsCardKind.visible(in: report).contains(.activity))
        report.activity = InsightsActivity(days: [InsightsActivityDay(date: day, habitFraction: 0)])
        #expect(InsightsCardKind.visible(in: report).contains(.activity))
    }

    @Test("Padding cells outside the period do not count as activity")
    func paddingIsNotActivity() {
        let day = InsightsTestSupport.day(0)
        var report = InsightsReport(period: .week, days: [day], isEmpty: false)
        report.activity = InsightsActivity(days: [InsightsActivityDay(date: day, habitFraction: 1, isInPeriod: false)])
        #expect(!InsightsCardKind.visible(in: report).contains(.activity))
    }

    // MARK: - Heat map layout

    @Test("Each day lands on its weekday's row, a new week starts a column")
    func weekColumns() throws {
        let calendar = TestCalendar.utc(firstWeekday: 2)
        // Wednesday 1 April 2026 to Friday 10 April.
        let first = TestCalendar.instant(calendar, 2026, 4, 1)
        let days = (0..<10).map { InsightsActivityDay(date: InsightsScope.step(first, by: $0, calendar: calendar)) }

        let columns = InsightsWeekColumns.columns(of: days, calendar: calendar)

        #expect(columns.count == 2)
        let firstWeek = try #require(columns.first)
        #expect(firstWeek.cells[0] == nil)
        #expect(firstWeek.cells[2]?.date == days[0].date)
        #expect(firstWeek.cells[6]?.date == days[4].date)
        let secondWeek = try #require(columns.last)
        #expect(secondWeek.cells[0]?.date == days[5].date)
        #expect(secondWeek.cells[4]?.date == days[9].date)
        #expect(secondWeek.cells[5] == nil)
    }

    @Test("A week starting on Sunday puts Sunday on the first row")
    func sundayWeekColumns() throws {
        let calendar = TestCalendar.utc(firstWeekday: 1)
        // Sunday 12 April and Monday 13 April 2026.
        let sunday = TestCalendar.instant(calendar, 2026, 4, 12)
        let days = (0..<2).map { InsightsActivityDay(date: InsightsScope.step(sunday, by: $0, calendar: calendar)) }

        let columns = InsightsWeekColumns.columns(of: days, calendar: calendar)

        #expect(columns.count == 1)
        let week = try #require(columns.first)
        #expect(week.cells[0]?.date == days[0].date)
        #expect(week.cells[1]?.date == days[1].date)
    }

    @Test("No day, no column")
    func noColumns() {
        #expect(InsightsWeekColumns.columns(of: [], calendar: TestCalendar.utc).isEmpty)
    }

    // MARK: - Fixtures

    @Test("The rich month has 30 days, 6 habits across 6 categories, 21 nights and 2 goals")
    func richFixture() throws {
        let rich = InsightsPreviewData.rich
        #expect(rich.period == .month)
        #expect(rich.days.count == 30)
        #expect(rich.activity.days.filter(\.isInPeriod).count == 30)
        let firstCell = try #require(rich.activity.days.first)
        let calendar = InsightsPreviewData.calendar
        #expect(calendar.component(.weekday, from: firstCell.date) == calendar.firstWeekday)
        #expect(rich.habits.count == 6)
        #expect(Set(rich.habits.map(\.category)) == [.sleep, .fitness, .study, .mind, .health, .home])
        #expect(rich.sleep.nights.count == 21)
        #expect(rich.goals.count == 2)
        #expect(rich.goals.allSatisfy { $0.pace != nil })
        #expect(rich.highlights.count == 4)
        #expect(!rich.isEmpty)
    }

    @Test("Fixtures are stored, so every read hands back the same ids")
    func stableFixtures() {
        #expect(InsightsPreviewData.rich.habits.map(\.habitID) == InsightsPreviewData.rich.habits.map(\.habitID))
        #expect(InsightsPreviewData.rich(for: .month) == InsightsPreviewData.rich)
        #expect(InsightsPreviewData.rich.habits.first?.habitID == InsightsPreviewData.ID.readHabit)
    }

    // MARK: - Highlights

    @Test("Every highlight reads as a sentence with a symbol")
    func highlightSentences() {
        for highlight in InsightsPreviewData.everyHighlight {
            #expect(!highlight.sentence.isEmpty)
            #expect(!highlight.symbolName.isEmpty)
        }
    }

    @Test("A highlight's sentence carries its name and number")
    func highlightValues() {
        let record = InsightsHighlight.streakRecord(habitName: "Read", days: 12).sentence
        #expect(record.contains("Read"))
        #expect(record.contains("12"))
        let drop = InsightsHighlight.consistencyChange(points: -4).sentence
        #expect(drop.contains("4"))
        #expect(!drop.contains("-4"))
    }
}
