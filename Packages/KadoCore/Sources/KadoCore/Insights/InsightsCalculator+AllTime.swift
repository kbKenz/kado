import Foundation

extension InsightsCalculator {
    /// Totals since the first record.
    /// Rules: see `InsightsAllTime` in InsightsReport.swift.
    static func allTime(_ scope: InsightsScope) -> InsightsAllTime {
        let input = scope.input
        let tasks = input.tasks.filter { !$0.isCancelled }
        let sessions = InsightsSharedB.trackedSessions(scope)

        var instants: [Date] = []
        for habit in input.habits {
            instants.append(habit.habit.createdAt)
            instants += habit.completions.filter { $0.value > 0 }.map(\.date)
        }
        instants += tasks.map(\.createdAt)
        instants += sessions.map(\.source.session.startedAt)
        let firstDay = instants.min().map { scope.civilDay($0) }
        let daysSinceStart = firstDay.map { first in
            max(0, InsightsSharedB.wholeDays(from: first, to: scope.today, scope.calendar) + 1)
        } ?? 0

        let habitTimesDone = input.habits
            .filter { !InsightsSharedB.isNegative($0.habit.type) }
            .reduce(0) { sum, habit in
                let days = scope.completionsByDay[habit.id] ?? [:]
                return sum + days.values.filter { records in records.contains { $0.value > 0 } }.count
            }

        return InsightsAllTime(
            firstDay: firstDay,
            daysSinceStart: daysSinceStart,
            habitTimesDone: habitTimesDone,
            tasksDone: tasks.filter { $0.completedAt != nil }.count,
            focusSeconds: sessions.reduce(0) { $0 + $1.seconds },
            bestStreak: InsightsSharedB.bestStreak(scope)
        )
    }
}

private extension InsightsSharedB {
    /// Whole days from `start` to `end`, two day starts. Counted from
    /// noon to noon, so a day that starts at 01:00 (a DST change at
    /// midnight) is still one whole day.
    static func wholeDays(from start: Date, to end: Date, _ calendar: Calendar) -> Int {
        func noon(_ day: Date) -> Date {
            calendar.date(bySettingHour: 12, minute: 0, second: 0, of: day) ?? day
        }
        return calendar.dateComponents([.day], from: noon(start), to: noon(end)).day ?? 0
    }

    /// The habit with the longest streak ever, archived habits included.
    /// On a tie the first habit stays. `nil` below one day.
    static func bestStreak(_ scope: InsightsScope) -> InsightsNamedCount? {
        var best: InsightsNamedCount?
        for habit in scope.input.habits {
            let days = scope.context.streakCalculator.best(
                for: habit.habit,
                completions: habit.completions,
                asOf: scope.today
            )
            if days > (best?.count ?? 0) {
                best = InsightsNamedCount(name: habit.habit.name, count: days)
            }
        }
        return best
    }
}
