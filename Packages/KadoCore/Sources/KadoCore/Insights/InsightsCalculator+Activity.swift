import Foundation

extension InsightsCalculator {
    /// The heat map cells and perfect days.
    /// Rules: see `InsightsActivity` in InsightsReport.swift.
    static func activity(_ scope: InsightsScope) -> InsightsActivity {
        guard let firstDay = scope.days.first else { return .empty }
        let tasksDone = tasksDoneByDay(scope)
        let focus = focusByDay(scope)

        var cells: [InsightsActivityDay] = []
        var perfectDays = 0
        var longestRun = 0
        var run = 0
        for day in leadingDays(scope, before: firstDay) + scope.days {
            let habits = habitRate(scope, on: day)
            let isInPeriod = day >= firstDay
            cells.append(InsightsActivityDay(
                date: day,
                habitFraction: habits.fraction,
                tasksDone: tasksDone[day] ?? 0,
                focusSeconds: focus[day] ?? 0,
                isInPeriod: isInPeriod
            ))
            // Padding cells and days with nothing due neither break nor
            // extend a run.
            guard isInPeriod, habits.total > 0 else { continue }
            if habits.done == habits.total {
                perfectDays += 1
                run += 1
                longestRun = max(longestRun, run)
            } else {
                run = 0
            }
        }
        return InsightsActivity(days: cells, perfectDays: perfectDays, longestPerfectRun: longestRun)
    }

    /// The days from the calendar's first weekday on or before
    /// `firstDay` up to the day before it: the cells that pad the
    /// first week. Oldest first.
    private static func leadingDays(_ scope: InsightsScope, before firstDay: Date) -> [Date] {
        let calendar = scope.calendar
        guard let week = calendar.dateInterval(of: .weekOfYear, for: firstDay) else { return [] }
        let weekStart = calendar.startOfDay(for: week.start)
        var days: [Date] = []
        var day = InsightsScope.step(firstDay, by: -1, calendar: calendar)
        // A week has at most 6 days before its last one.
        while day >= weekStart && days.count < 6 {
            days.append(day)
            day = InsightsScope.step(day, by: -1, calendar: calendar)
        }
        return days.reversed()
    }

    /// Due habits and how many of them are done on `day`.
    ///
    /// Past days use the shared outcome. Today has no grace here: a
    /// partly done today must not look perfect, so every non-negative
    /// habit the schedule counts today is due, and it is done once its
    /// daily value is full.
    private static func habitRate(_ scope: InsightsScope, on day: Date) -> InsightsRate {
        guard day == scope.today else {
            return scope.habitConsistency(of: scope.input.habits, over: [day])
        }
        var rate = InsightsRate.empty
        let context = scope.context
        for habit in scope.input.habits where habit.habit.type != .negative {
            let counted = context.frequencyEvaluator.isCounted(
                habit: habit.habit,
                on: day,
                completions: habit.completions,
                calendar: scope.calendar
            )
            guard counted else { continue }
            let onDay = scope.completionsByDay[habit.id]?[day] ?? []
            rate.total += 1
            if DailyValue.compute(for: habit.habit, completionsOnDay: onDay) >= 1 - 1e-9 {
                rate.done += 1
            }
        }
        return rate
    }

    /// Tasks completed on each civil day.
    private static func tasksDoneByDay(_ scope: InsightsScope) -> [Date: Int] {
        var counts: [Date: Int] = [:]
        for task in scope.uncancelledTasks {
            guard let completedAt = task.completedAt else { continue }
            counts[scope.civilDay(completedAt), default: 0] += 1
        }
        return counts
    }

    /// Tracked seconds per logical day, by the day each session started.
    private static func focusByDay(_ scope: InsightsScope) -> [Date: TimeInterval] {
        var seconds: [Date: TimeInterval] = [:]
        for tracked in scope.sessionsWithTime {
            seconds[scope.sessionDay(tracked.session), default: 0] += tracked.seconds
        }
        return seconds
    }
}
