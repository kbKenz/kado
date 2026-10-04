import Foundation

/// Where the day Today is showing sits relative to the habit-day today.
nonisolated enum TodayDayKind: Equatable {
    case past, today, future

    init(day: Date, today: Date, calendar: Calendar) {
        let day = calendar.startOfDay(for: day)
        let today = calendar.startOfDay(for: today)
        if day < today { self = .past } else if day == today { self = .today } else { self = .future }
    }

    /// A habit can't be done before its day, so future days are view-only
    /// for habits. Past days allow backfill.
    var allowsHabitLogging: Bool { self != .future }
}
