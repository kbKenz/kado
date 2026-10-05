import Foundation
import KadoCore

/// What `MonthlyCalendarView` needs to know about each day, gathered
/// in one pass over the completions. Each cell used to scan every
/// completion three or four times (effective start, completed, note
/// dot twice), which made a month of a year-old habit cost ~100k
/// calendar calls per render.
///
/// Days are compared by `startOfDay`, which is the same question as
/// `isDate(_:inSameDayAs:)`, including on a day that begins at 01:00.
nonisolated struct MonthlyCalendarDayIndex {
    private let calendar: Calendar
    private let startDay: Date
    private let completedDays: Set<Date>
    private let noteDays: Set<Date>

    init(habit: Habit, completions: [Completion], calendar: Calendar) {
        self.calendar = calendar
        startDay = calendar.startOfDay(for: habit.effectiveStart(completions: completions, calendar: calendar))
        var completed = Set<Date>()
        var noted = Set<Date>()
        for completion in completions where completion.habitID == habit.id {
            let hasValue = completion.value > 0
            let hasNote = completion.note.map { !$0.isEmpty } ?? false
            guard hasValue || hasNote else { continue }
            let day = calendar.startOfDay(for: completion.date)
            if hasValue { completed.insert(day) }
            if hasNote { noted.insert(day) }
        }
        completedDays = completed
        noteDays = noted
    }

    /// `Habit.isBeforeStart`, with the effective start computed once.
    func isBeforeStart(_ day: Date) -> Bool {
        calendar.startOfDay(for: day) < startDay
    }

    /// A record with a positive value on `day` — done, or for a
    /// negative habit, slipped.
    func hasValue(on day: Date) -> Bool {
        completedDays.contains(calendar.startOfDay(for: day))
    }

    /// A non-empty note on `day`, whatever the record's value.
    func hasNote(on day: Date) -> Bool {
        noteDays.contains(calendar.startOfDay(for: day))
    }
}
