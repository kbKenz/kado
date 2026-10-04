import Foundation

public extension Habit {
    /// The first day this habit shows on Today's other days: the earlier
    /// of its creation day and its effective start (a backfill can move
    /// the start before creation). Today never lists a habit before this
    /// day, so it never logs a pre-start day — that case keeps its
    /// warning in Overview and Habit Detail (issue #104).
    func firstListedDay(completions: [Completion], calendar: Calendar) -> Date {
        let start = effectiveStart(completions: completions, calendar: calendar)
        return calendar.startOfDay(for: min(createdAt, start))
    }

    func isListed(on day: Date, completions: [Completion], calendar: Calendar) -> Bool {
        calendar.startOfDay(for: day) >= firstListedDay(completions: completions, calendar: calendar)
    }
}
