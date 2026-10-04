import Foundation

/// The ring on one day-strip cell: habits done against habits due, with
/// the same rule as Today's "Habits today" section (listed on the day,
/// `isDueOrLogged`, `HabitRowState.isDone`), so the ring and the list
/// never disagree. Tasks are not counted — `DayProgress` is habits-only
/// everywhere (confetti, lock-screen ring).
nonisolated public enum DayStripProgress {
    public static func progress(
        on day: Date,
        isFuture: Bool,
        habits: [Habit],
        completions: [UUID: [Completion]],
        evaluator: any FrequencyEvaluating,
        calendar: Calendar
    ) -> DayProgress {
        var total = 0
        var completed = 0
        for habit in habits {
            let comps = completions[habit.id] ?? []
            guard habit.isListed(on: day, completions: comps, calendar: calendar),
                  evaluator.isDueOrLogged(habit: habit, on: day, completions: comps, calendar: calendar)
            else { continue }
            total += 1
            // Nothing can be done ahead of its day; a negative habit
            // would otherwise read as "done" on every future day.
            guard !isFuture else { continue }
            let state = HabitRowState.resolve(habit: habit, completions: comps, calendar: calendar, asOf: day)
            if state.isDone(for: habit) { completed += 1 }
        }
        return DayProgress(completed: completed, total: total)
    }
}
