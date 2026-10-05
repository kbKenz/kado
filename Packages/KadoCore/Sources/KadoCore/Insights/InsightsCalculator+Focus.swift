import Foundation

extension InsightsCalculator {
    /// Tracked session time and the focus chart buckets.
    /// Rules: see `InsightsFocus` in InsightsReport.swift.
    static func focus(_ scope: InsightsScope) -> InsightsFocus {
        let sessions = InsightsSharedB.trackedSessions(scope, on: scope.days)
        let total = sessions.reduce(0) { $0 + $1.seconds }
        let previousTotal = InsightsSharedB.trackedSessions(scope, on: scope.previousDays)
            .reduce(0) { $0 + $1.seconds }
        return InsightsFocus(
            total: total,
            previousTotal: previousTotal,
            sessionCount: sessions.count,
            averageSession: sessions.isEmpty ? nil : total / Double(sessions.count),
            longestSession: sessions.map(\.seconds).max(),
            buckets: InsightsSharedB.focusBuckets(sessions, scope),
            planRatio: InsightsSharedB.planRatio(sessions),
            hasEverTracked: !InsightsSharedB.trackedSessions(scope).isEmpty
        )
    }
}

private extension InsightsSharedB {
    /// One bar per day for a week or a month, one per calendar month for
    /// a year, oldest first. Bars without time stay, so the chart has no
    /// gaps.
    static func focusBuckets(_ sessions: [TrackedSession], _ scope: InsightsScope) -> [InsightsFocusBucket] {
        let calendar = scope.calendar
        let starts: [Date]
        let bucketStart: (Date) -> Date
        switch scope.context.period {
        case .week, .month:
            starts = scope.days
            bucketStart = { $0 }
        case .year:
            starts = monthStarts(from: scope.days.first ?? scope.today, through: scope.today, calendar: calendar)
            bucketStart = { monthStart(of: $0, calendar: calendar) }
        }
        var buckets: [Date: InsightsFocusBucket] = [:]
        for start in starts {
            buckets[start] = InsightsFocusBucket(start: start)
        }
        for session in sessions {
            let start = bucketStart(session.day)
            guard var bucket = buckets[start] else { continue }
            bucket.seconds += session.seconds
            bucket.byCategory[session.source.category, default: 0] += session.seconds
            buckets[start] = bucket
        }
        return starts.compactMap { buckets[$0] }
    }

    /// Tracked time / planned time, over the sessions with a planned
    /// range. `nil` when there is no planned time.
    static func planRatio(_ sessions: [TrackedSession]) -> Double? {
        let planned = sessions.filter { $0.source.plannedRange != nil }
        let plannedSeconds = planned.reduce(0) { $0 + ($1.source.plannedRange?.duration ?? 0) }
        guard plannedSeconds > 0 else { return nil }
        return planned.reduce(0) { $0 + $1.seconds } / plannedSeconds
    }

    /// Start of the first day of the calendar month that holds `day`.
    static func monthStart(of day: Date, calendar: Calendar) -> Date {
        calendar.startOfDay(for: calendar.dateInterval(of: .month, for: day)?.start ?? day)
    }

    /// The start of every calendar month from the month of `first` to
    /// the month of `last`, oldest first.
    static func monthStarts(from first: Date, through last: Date, calendar: Calendar) -> [Date] {
        let end = monthStart(of: last, calendar: calendar)
        var month = monthStart(of: first, calendar: calendar)
        var result: [Date] = []
        while month <= end {
            result.append(month)
            guard let next = calendar.date(byAdding: .month, value: 1, to: month) else { break }
            // Re-anchored: a month whose first day starts at 01:00 must
            // not shift the months after it.
            let nextMonth = monthStart(of: next, calendar: calendar)
            guard nextMonth > month else { break }
            month = nextMonth
        }
        return result
    }
}
