import Foundation
import KadoCore

/// What Overview's Insights and History last showed, kept while the
/// user switches mode or period.
///
/// Each mode is its own screen, so a switch makes a new one, and a new
/// one used to open on a spinner. It opens on what was last shown for
/// the same day and the same choices instead, and still reads and
/// computes again exactly as before: the cache only fills the wait,
/// as each screen already does with its own last result while a new
/// one computes. Owned by `OverviewView`; not observed, since a screen
/// reads it while rendering and writes it when a result lands.
final class OverviewCache {
    private struct Report {
        var today: Date
        var civilToday: Date
        var report: InsightsReport
    }

    /// The History's last result, with what it was computed for.
    struct History {
        var civilToday: Date
        var startHour: Int
        var query: HistoryQuery
        var days: [HistoryDay]
        var availableCategories: [ItemCategory]
        var firstDay: Date?
    }

    private var reports: [InsightsPeriod: Report] = [:]
    private var history: History?

    /// The last report on `period`, if it was computed for the same day.
    func report(for period: InsightsPeriod, today: Date, civilToday: Date) -> InsightsReport? {
        guard let entry = reports[period], entry.today == today, entry.civilToday == civilToday else { return nil }
        return entry.report
    }

    func store(_ report: InsightsReport, today: Date, civilToday: Date) {
        reports[report.period] = Report(today: today, civilToday: civilToday, report: report)
    }

    /// The last History result, if it answered the same query on the
    /// same day.
    func history(for query: HistoryQuery, startHour: Int, civilToday: Date) -> History? {
        guard let history, history.query == query, history.startHour == startHour, history.civilToday == civilToday else { return nil }
        return history
    }

    func store(_ history: History) {
        self.history = history
    }
}
