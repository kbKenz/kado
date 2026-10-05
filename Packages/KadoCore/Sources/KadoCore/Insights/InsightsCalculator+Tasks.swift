import Foundation

extension InsightsCalculator {
    /// Done and left-undone tasks.
    /// Rules: see `InsightsTasks` in InsightsReport.swift.
    static func tasks(_ scope: InsightsScope) -> InsightsTasks {
        let tasks = scope.uncancelledTasks
        let periodDays = Set(scope.days)
        let current = scope.taskTally(of: tasks, over: periodDays)
        let previous = scope.taskTally(of: tasks, over: Set(scope.previousDays))
        let done = tasks.filter { scope.isTaskDone($0, in: periodDays) }
        return InsightsTasks(
            done: current.done,
            undone: current.undone,
            previousDone: previous.done,
            previousUndone: previous.undone,
            onTime: onTime(scope, done: done),
            averageDaysToFinish: averageDaysToFinish(scope, done: done),
            undoneByCategory: undoneByCategory(scope, tasks: tasks, days: periodDays),
            overdueOpen: tasks.filter { isOverdueOpen(scope, $0) }.count
        )
    }

    /// Among `done` tasks with a target day: done on or before it.
    private static func onTime(_ scope: InsightsScope, done: [InsightsTask]) -> InsightsRate {
        var rate = InsightsRate.empty
        for task in done {
            guard let completedAt = task.completedAt, let target = task.targetDay else { continue }
            rate.total += 1
            if scope.civilDay(completedAt) <= scope.civilDay(target) {
                rate.done += 1
            }
        }
        return rate
    }

    /// Mean whole civil days from creation to completion, never
    /// negative. `nil` when nothing was done.
    private static func averageDaysToFinish(_ scope: InsightsScope, done: [InsightsTask]) -> Double? {
        let days = done.compactMap { task -> Int? in
            guard let completedAt = task.completedAt else { return nil }
            return max(0, scope.civilDayDistance(from: task.createdAt, to: completedAt))
        }
        guard !days.isEmpty else { return nil }
        return Double(days.reduce(0, +)) / Double(days.count)
    }

    /// Categories with at least 2 tasks done or left undone and at least
    /// 1 left undone: highest undone share first, then most undone, then
    /// the categories' own order. At most 3.
    private static func undoneByCategory(
        _ scope: InsightsScope,
        tasks: [InsightsTask],
        days: Set<Date>
    ) -> [InsightsCategoryUndone] {
        let order = ItemCategory.allCases
        let rows = order.compactMap { category -> InsightsCategoryUndone? in
            let tally = scope.taskTally(of: tasks.filter { $0.category == category }, over: days)
            guard tally.total >= 2, tally.undone >= 1 else { return nil }
            return InsightsCategoryUndone(category: category, undone: tally.undone, total: tally.total)
        }
        let sorted = rows.sorted { lhs, rhs in
            // Cross-multiplied, so equal shares compare equal exactly.
            let lhsShare = lhs.undone * rhs.total
            let rhsShare = rhs.undone * lhs.total
            if lhsShare != rhsShare {
                return lhsShare > rhsShare
            }
            if lhs.undone != rhs.undone {
                return lhs.undone > rhs.undone
            }
            return (order.firstIndex(of: lhs.category) ?? 0) < (order.firstIndex(of: rhs.category) ?? 0)
        }
        return Array(sorted.prefix(3))
    }

    /// An open task (no completion, not archived) whose target day is
    /// before today, whatever the period.
    private static func isOverdueOpen(_ scope: InsightsScope, _ task: InsightsTask) -> Bool {
        guard task.completedAt == nil, task.archivedAt == nil, let target = task.targetDay else { return false }
        return scope.civilDay(target) < scope.today
    }
}
