import Foundation

extension InsightsCalculator {
    /// The three dials, for the period and the previous one.
    /// Rules: see `InsightsPulse` in InsightsReport.swift.
    static func pulse(_ scope: InsightsScope) -> InsightsPulse {
        let habits = scope.input.habits
        let tasks = scope.uncancelledTasks
        let firstDay = firstRecordDay(scope)
        let activeDays = activeDaySet(scope)
        return InsightsPulse(
            consistency: scope.habitConsistency(of: habits, over: scope.days),
            previousConsistency: scope.habitConsistency(of: habits, over: scope.previousDays),
            followThrough: scope.taskTally(of: tasks, over: Set(scope.days)).followThrough,
            previousFollowThrough: scope.taskTally(of: tasks, over: Set(scope.previousDays)).followThrough,
            activeDays: activeDayRate(scope, window: scope.days, firstDay: firstDay, activeDays: activeDays),
            previousActiveDays: activeDayRate(scope, window: scope.previousDays, firstDay: firstDay, activeDays: activeDays)
        )
    }

    /// Active days / counted days in `window`. A day counts from the
    /// first record on; today counts only once it is active.
    private static func activeDayRate(
        _ scope: InsightsScope,
        window: [Date],
        firstDay: Date?,
        activeDays: Set<Date>
    ) -> InsightsRate {
        guard let firstDay else { return .empty }
        var rate = InsightsRate.empty
        for day in window where day >= firstDay {
            let isActive = activeDays.contains(day)
            if day == scope.today && !isActive { continue }
            rate.total += 1
            if isActive { rate.done += 1 }
        }
        return rate
    }

    /// Days with activity: a positive record on a non-negative habit,
    /// a task completed (civil day), or a session started (logical day).
    private static func activeDaySet(_ scope: InsightsScope) -> Set<Date> {
        var days = Set<Date>()
        for habit in scope.input.habits where habit.habit.type != .negative {
            for completion in habit.completions where completion.value > 0 {
                days.insert(scope.calendar.startOfDay(for: completion.date))
            }
        }
        for task in scope.uncancelledTasks {
            if let completedAt = task.completedAt {
                days.insert(scope.civilDay(completedAt))
            }
        }
        for tracked in scope.sessionsWithTime {
            days.insert(scope.sessionDay(tracked.session))
        }
        return days
    }

    /// The day of the user's first record: a habit or task created, a
    /// positive completion, a task completed, or a session with time.
    /// `nil` when there is none.
    private static func firstRecordDay(_ scope: InsightsScope) -> Date? {
        var days: [Date] = []
        for habit in scope.input.habits {
            days.append(scope.calendar.startOfDay(for: habit.habit.createdAt))
            for completion in habit.completions where completion.value > 0 {
                days.append(scope.calendar.startOfDay(for: completion.date))
            }
        }
        for task in scope.uncancelledTasks {
            days.append(scope.civilDay(task.createdAt))
            if let completedAt = task.completedAt {
                days.append(scope.civilDay(completedAt))
            }
        }
        for tracked in scope.sessionsWithTime {
            days.append(scope.sessionDay(tracked.session))
        }
        return days.min()
    }
}
