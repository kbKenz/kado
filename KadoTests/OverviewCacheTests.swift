import Foundation
import Testing
@testable import Kado
import KadoCore

/// `OverviewCache` only hands back a result computed for exactly what
/// the screen is about to show: the same period or query, on the same day.
@Suite("OverviewCache")
@MainActor
struct OverviewCacheTests {
    private let today = TestCalendar.utc.startOfDay(for: TestCalendar.referenceDate)
    private var tomorrow: Date { TestCalendar.utc.date(byAdding: .day, value: 1, to: today)! }

    @Test("A report comes back for its own period and day only")
    func reports() {
        let cache = OverviewCache()
        let week = InsightsReport(period: .week, days: [today])
        let month = InsightsReport(period: .month, days: [today])
        cache.store(week, today: today, civilToday: today)
        cache.store(month, today: today, civilToday: today)

        #expect(cache.report(for: .week, today: today, civilToday: today) == week)
        #expect(cache.report(for: .month, today: today, civilToday: today) == month)
        #expect(cache.report(for: .quarter, today: today, civilToday: today) == nil)
        #expect(cache.report(for: .week, today: tomorrow, civilToday: today) == nil)
        #expect(cache.report(for: .week, today: today, civilToday: tomorrow) == nil)

        let newer = InsightsReport(period: .week, days: [today], isEmpty: false)
        cache.store(newer, today: today, civilToday: today)
        #expect(cache.report(for: .week, today: today, civilToday: today) == newer)
    }

    @Test("The History comes back for the same query, day start and day only")
    func history() {
        let cache = OverviewCache()
        let query = HistoryQuery(kind: .tasks, search: "run")
        cache.store(OverviewCache.History(
            civilToday: today,
            startHour: 4,
            query: query,
            days: [],
            availableCategories: [.fitness],
            firstDay: today
        ))

        let kept = cache.history(for: query, startHour: 4, civilToday: today)
        #expect(kept?.availableCategories == [.fitness])
        #expect(kept?.firstDay == today)
        #expect(cache.history(for: HistoryQuery(kind: .tasks, search: "ru"), startHour: 4, civilToday: today) == nil)
        #expect(cache.history(for: HistoryQuery(kind: .habits, search: "run"), startHour: 4, civilToday: today) == nil)
        #expect(cache.history(for: query, startHour: 0, civilToday: today) == nil)
        #expect(cache.history(for: query, startHour: 4, civilToday: tomorrow) == nil)
    }
}
