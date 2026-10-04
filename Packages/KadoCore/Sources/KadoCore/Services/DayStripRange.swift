import Foundation

/// The days Today's day strip offers: from the first day the user had
/// anything to look back on, to `futureDays` after today. Every element
/// is a calendar midnight, as `Calendar.startOfDay` returns them.
nonisolated public enum DayStripRange {
    /// How far ahead the strip reaches.
    public static let defaultFutureDays = 60

    public static func days(
        from earliest: Date?,
        today: Date,
        futureDays: Int = defaultFutureDays,
        calendar: Calendar
    ) -> [Date] {
        let todayStart = calendar.startOfDay(for: today)
        let first = earliest.map { min(calendar.startOfDay(for: $0), todayStart) } ?? todayStart
        guard let last = calendar.date(byAdding: .day, value: max(futureDays, 0), to: todayStart) else {
            return [todayStart]
        }
        let lastStart = calendar.startOfDay(for: last)
        var days: [Date] = []
        var cursor = first
        while cursor <= lastStart {
            days.append(cursor)
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            // Re-anchored: where DST starts at midnight (Havana) the
            // next day begins at 01:00, and adding a day from there
            // keeps the 01:00 rather than landing on a midnight.
            cursor = calendar.startOfDay(for: next)
        }
        return days
    }

    /// `day` moved inside `days`, or `nil` when `days` is empty.
    public static func clamp(_ day: Date, to days: [Date]) -> Date? {
        guard let first = days.first, let last = days.last else { return nil }
        return min(max(day, first), last)
    }
}
