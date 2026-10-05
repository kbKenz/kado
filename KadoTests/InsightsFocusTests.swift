import Foundation
import Testing
@testable import KadoCore

@Suite("Insights focus")
struct InsightsFocusTests {
    typealias T = InsightsTestSupport

    private func calculate(_ input: InsightsInput, _ context: InsightsContext = T.context()) -> InsightsFocus {
        InsightsCalculator.focus(T.scope(input, context))
    }

    @Test("Without sessions: no time, no averages, an empty bar per day")
    func empty() {
        let focus = calculate(.empty)
        #expect(focus.total == 0.0)
        #expect(focus.previousTotal == 0.0)
        #expect(focus.sessionCount == 0)
        #expect(focus.averageSession == nil)
        #expect(focus.longestSession == nil)
        #expect(focus.planRatio == nil)
        #expect(!focus.hasEverTracked)
        #expect(focus.buckets == (-6...0).map { InsightsFocusBucket(start: T.day($0)) })
    }

    @Test("Total, count, average and longest over the sessions of the period")
    func totals() {
        let input = InsightsInput(sessions: [
            T.session(offset: -6, minutes: 30),
            T.session(offset: -2, minutes: 60),
            T.session(offset: 0, hour: 8, minutes: 90),
        ])
        let focus = calculate(input)
        #expect(focus.total == 180.0 * 60)
        #expect(focus.sessionCount == 3)
        #expect(focus.averageSession == 60.0 * 60)
        #expect(focus.longestSession == 90.0 * 60)
        #expect(focus.hasEverTracked)
    }

    @Test("The days just outside the period count for the previous period or not at all")
    func periodEdges() {
        let input = InsightsInput(sessions: [
            T.session(offset: -14, minutes: 600), // before both periods
            T.session(offset: -13, minutes: 15),  // first day of the previous period
            T.session(offset: -7, minutes: 45),   // last day of the previous period
            T.session(offset: -6, minutes: 20),   // first day of the period
        ])
        let focus = calculate(input)
        #expect(focus.total == 20.0 * 60)
        #expect(focus.sessionCount == 1)
        #expect(focus.previousTotal == 60.0 * 60)
    }

    @Test("An open session today counts up to now")
    func openSessionToday() {
        // The context's now is 18:00 today.
        let open = InsightsSession(id: UUID(), session: WorkSession(startedAt: T.time(0, 17)), category: .work)
        let focus = calculate(InsightsInput(sessions: [open]))
        #expect(focus.total == 3600.0)
        #expect(focus.sessionCount == 1)
        #expect(focus.buckets.last == InsightsFocusBucket(start: T.day(0), seconds: 3600, byCategory: [.work: 3600]))
    }

    @Test("Sessions without time are ignored everywhere")
    func zeroSessions() {
        let focus = calculate(InsightsInput(sessions: [T.session(offset: -1, minutes: 0, plannedMinutes: 30)]))
        #expect(focus.sessionCount == 0)
        #expect(focus.averageSession == nil)
        #expect(focus.longestSession == nil)
        #expect(focus.planRatio == nil)
        #expect(!focus.hasEverTracked)
    }

    @Test("A session long ago still means the user has tracked")
    func trackedLongAgo() {
        let focus = calculate(InsightsInput(sessions: [T.session(offset: -200, minutes: 10)]))
        #expect(focus.total == 0.0)
        #expect(focus.hasEverTracked)
    }

    @Test("Week bars: one per day, split by category, empty days kept")
    func weekBuckets() {
        let input = InsightsInput(sessions: [
            T.session(offset: -3, minutes: 30, category: .work),
            T.session(offset: -3, hour: 14, minutes: 15, category: .study),
            T.session(offset: -3, hour: 16, minutes: 15, category: .work),
            T.session(offset: -1, minutes: 60, category: .fitness),
        ])
        let buckets = calculate(input).buckets
        #expect(buckets.map(\.start) == (-6...0).map { T.day($0) })
        #expect(buckets[3] == InsightsFocusBucket(start: T.day(-3), seconds: 3600, byCategory: [.work: 2700, .study: 900]))
        #expect(buckets[5] == InsightsFocusBucket(start: T.day(-1), seconds: 3600, byCategory: [.fitness: 3600]))
        #expect(buckets[0] == InsightsFocusBucket(start: T.day(-6)))
    }

    @Test("Month bars: one per day of the 30")
    func monthBuckets() {
        let focus = calculate(InsightsInput(sessions: [T.session(offset: -29, minutes: 5)]), T.context(period: .month))
        #expect(focus.buckets.map(\.start) == (-29...0).map { T.day($0) })
        #expect(focus.buckets.first?.seconds == 5.0 * 60)
    }

    @Test("Quarter bars: one per calendar week, from the first week of the period to this week")
    func quarterBuckets() {
        let input = InsightsInput(sessions: [
            T.session(offset: -90, minutes: 99), // the day before the period
            T.session(offset: -89, minutes: 30), // 2026-01-14, the first day of the period (a Wednesday)
            T.session(offset: -10, minutes: 20), // 2026-04-03
            T.session(offset: 0, minutes: 10),   // 2026-04-13, today
        ])
        let focus = calculate(input, T.context(period: .quarter))
        // Weeks start on Sunday in TestCalendar.utc: from Sunday 2026-01-11
        // to Sunday 2026-04-12, 14 weeks.
        let weeks = (0..<14).map { T.day(-92 + 7 * $0) }
        #expect(focus.buckets.map(\.start) == weeks)
        #expect(focus.buckets.first?.seconds == 30.0 * 60)
        #expect(focus.buckets.last?.seconds == 10.0 * 60)
        #expect(focus.buckets[11].seconds == 20.0 * 60)
        #expect(focus.total == 60.0 * 60)
        #expect(focus.previousTotal == 99.0 * 60)
    }

    @Test("Plan ratio: tracked over planned, only for sessions with a planned range")
    func planRatio() {
        let input = InsightsInput(sessions: [
            T.session(offset: -2, minutes: 60, plannedMinutes: 50),
            T.session(offset: -1, minutes: 30, plannedMinutes: 25),
            T.session(offset: -1, hour: 15, minutes: 100),            // no plan
            T.session(offset: -8, minutes: 10, plannedMinutes: 100),  // previous period
        ])
        #expect(calculate(input).planRatio == 90.0 / 75.0)
    }

    @Test("No planned time, no plan ratio")
    func planRatioWithoutPlannedTime() {
        let input = InsightsInput(sessions: [T.session(offset: -1, minutes: 30, plannedMinutes: 0)])
        #expect(calculate(input).planRatio == nil)
    }

    @Test("A session before the day-start hour belongs to the day before")
    func dayStartHour() {
        let input = InsightsInput(sessions: [
            T.session(offset: -6, hour: 2, minutes: 30), // logical day -7
            T.session(offset: 0, hour: 3, minutes: 20),  // logical day -1
        ])
        let focus = calculate(input, T.context(startHour: 4))
        #expect(focus.total == 20.0 * 60)
        #expect(focus.previousTotal == 30.0 * 60)
        #expect(focus.buckets[5].seconds == 20.0 * 60)
    }

    @Test("Havana: day bars stay on day starts across the midnight DST change")
    func havanaBuckets() {
        let calendar = TestCalendar.havana
        let today = TestCalendar.instant(calendar, 2026, 3, 12)
        let context = T.context(period: .month, today: today, calendar: calendar)
        // On 2026-03-08 Havana's clock skips from 00:00 to 01:00.
        let session = InsightsSession(
            id: UUID(),
            session: WorkSession(
                startedAt: TestCalendar.instant(calendar, 2026, 3, 8, 10),
                endedAt: TestCalendar.instant(calendar, 2026, 3, 8, 11)
            ),
            category: .work
        )
        let focus = InsightsCalculator.focus(T.scope(InsightsInput(sessions: [session]), context))
        let dstDay = calendar.startOfDay(for: session.session.startedAt)
        #expect(focus.buckets.map(\.start) == T.scope(.empty, context).days)
        #expect(focus.buckets.first { $0.start == dstDay }?.seconds == 3600.0)
        #expect(focus.total == 3600.0)
    }
}
