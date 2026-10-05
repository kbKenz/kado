import Foundation

/// The ring on one day-strip cell: habits done against habits due, with
/// the same rule as Today's "Habits today" section (listed on the day,
/// `isDueOrLogged`, `HabitRowState.isDone`), so the ring and the list
/// never disagree. Tasks are not counted — `DayProgress` is habits-only
/// everywhere (confetti, lock-screen ring).
///
/// `isListed` overlaps with `isDue`'s own before-start check; it is kept
/// so the rule is explicit and shared with `TodayRow`. The caller must
/// pass already-filtered (non-archived) habits, and `evaluator` must use
/// the same calendar as `calendar`.
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

    /// The per-habit facts every cell reads, built once per data change
    /// rather than once per cell: the first listed day, and the
    /// completions grouped by day. The strip asks for dozens of days, and
    /// each ask used to scan every completion of every habit several times.
    public struct Index: Sendable {
        fileprivate struct Entry: Sendable {
            let habit: Habit
            /// The full list, for the schedule (`isDue`), which reads
            /// history across days.
            let completions: [Completion]
            let firstListedDay: Date
            /// Keyed by `startOfDay`, each list in the original order, so
            /// `HabitRowState.resolve` still picks the same first match.
            let byDay: [Date: [Completion]]
        }

        fileprivate let entries: [Entry]

        public init(habits: [Habit], completions: [UUID: [Completion]], calendar: Calendar) {
            entries = habits.map { habit in
                let comps = completions[habit.id] ?? []
                return Entry(
                    habit: habit,
                    completions: comps,
                    firstListedDay: habit.firstListedDay(completions: comps, calendar: calendar),
                    byDay: Dictionary(grouping: comps) { calendar.startOfDay(for: $0.date) }
                )
            }
        }
    }

    /// Same answer as `progress(on:isFuture:habits:completions:…)`, read
    /// from a prebuilt `Index`. `index` must be built with `calendar`.
    public static func progress(
        on day: Date,
        isFuture: Bool,
        index: Index,
        evaluator: any FrequencyEvaluating,
        calendar: Calendar
    ) -> DayProgress {
        let dayStart = calendar.startOfDay(for: day)
        var total = 0
        var completed = 0
        for entry in index.entries {
            let habit = entry.habit
            // `isListed`, with its first day hoisted out.
            guard dayStart >= entry.firstListedDay else { continue }
            let onDay = entry.byDay[dayStart] ?? []
            // `isDueOrLogged`, with its "logged that day" arm read from
            // the day's own completions instead of a scan of all of them.
            guard evaluator.isDue(habit: habit, on: day, completions: entry.completions)
                    || isLogged(habit, in: onDay)
            else { continue }
            total += 1
            guard !isFuture else { continue }
            // `resolve` only matches completions on `day`, so the day's
            // own list gives the same first match as the full one.
            let state = HabitRowState.resolve(habit: habit, completions: onDay, calendar: calendar, asOf: day)
            if state.isDone(for: habit) { completed += 1 }
        }
        return DayProgress(completed: completed, total: total)
    }

    /// The second arm of `FrequencyEvaluating.isDueOrLogged`, over
    /// completions already narrowed to the day.
    private static func isLogged(_ habit: Habit, in onDay: [Completion]) -> Bool {
        if case .negative = habit.type { return false }
        return onDay.contains { $0.habitID == habit.id && $0.value > 0 }
    }
}
