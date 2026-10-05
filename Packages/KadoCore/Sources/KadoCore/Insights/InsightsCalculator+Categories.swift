import Foundation

extension InsightsCalculator {
    /// One row per category with activity in the period.
    /// Rules: see `[InsightsCategoryRow]` in InsightsReport.swift.
    static func categories(_ scope: InsightsScope) -> [InsightsCategoryRow] {
        let periodDays = Set(scope.days)
        let tasks = scope.uncancelledTasks
        var focus: [ItemCategory: TimeInterval] = [:]
        for tracked in scope.sessionsWithTime where periodDays.contains(scope.sessionDay(tracked.session)) {
            focus[tracked.session.category, default: 0] += tracked.seconds
        }

        let rows = ItemCategory.allCases.compactMap { category -> InsightsCategoryRow? in
            let habits = scope.input.habits.filter { $0.category == category }
            let tally = scope.taskTally(of: tasks.filter { $0.category == category }, over: periodDays)
            let timesDone = habits
                .filter { $0.habit.type != .negative }
                .reduce(0) { $0 + scope.daysWithPositiveRecord(of: $1, in: scope.days) }
            let row = InsightsCategoryRow(
                category: category,
                focusSeconds: focus[category] ?? 0,
                habitConsistency: scope.habitConsistency(of: habits, over: scope.days),
                habitTimesDone: timesDone,
                tasksDone: tally.done,
                tasksUndone: tally.undone
            )
            return hasActivity(row) ? row : nil
        }
        return rows.sorted(by: categorySortsBefore)
    }

    private static func hasActivity(_ row: InsightsCategoryRow) -> Bool {
        row.focusSeconds > 0
            || row.habitConsistency.total > 0
            || row.habitTimesDone > 0
            || row.tasksDone > 0
            || row.tasksUndone > 0
    }

    /// Most focus first, then most times done (habits and tasks), then
    /// the categories' own order.
    private static func categorySortsBefore(_ lhs: InsightsCategoryRow, _ rhs: InsightsCategoryRow) -> Bool {
        if lhs.focusSeconds != rhs.focusSeconds {
            return lhs.focusSeconds > rhs.focusSeconds
        }
        let lhsDone = lhs.habitTimesDone + lhs.tasksDone
        let rhsDone = rhs.habitTimesDone + rhs.tasksDone
        if lhsDone != rhsDone {
            return lhsDone > rhsDone
        }
        let order = ItemCategory.allCases
        return (order.firstIndex(of: lhs.category) ?? 0) < (order.firstIndex(of: rhs.category) ?? 0)
    }
}
