import Foundation

extension InsightsCalculator {
    /// One row per active goal.
    /// Rules: see `[InsightsGoalRow]` in InsightsReport.swift.
    static func goals(_ scope: InsightsScope) -> [InsightsGoalRow] {
        scope.input.goals
            .filter { $0.status == .active && !$0.isArchived }
            .sorted(by: goalSortsBefore)
            .map { goalRow(scope, for: $0) }
    }

    private static func goalRow(_ scope: InsightsScope, for goal: InsightsGoal) -> InsightsGoalRow {
        let taskIDs = Set(goal.linkedTaskIDs)
        let habitIDs = Set(goal.linkedHabitIDs)
        let tasks = scope.uncancelledTasks.filter { taskIDs.contains($0.id) }
        let habits = scope.input.habits.filter { habitIDs.contains($0.id) }
        let periodDays = Set(scope.days)
        return InsightsGoalRow(
            goalID: goal.id,
            name: goal.name,
            category: goal.category,
            progress: goal.progress,
            tasksDone: tasks.filter { $0.completedAt != nil }.count,
            tasksTotal: tasks.count,
            tasksDoneInPeriod: tasks.filter { scope.isTaskDone($0, in: periodDays) }.count,
            habitConsistency: scope.habitConsistency(of: habits, over: scope.days),
            pace: pace(scope, for: goal),
            daysLeft: daysLeft(scope, for: goal)
        )
    }

    /// Progress against the share of time already gone, from the start
    /// (start date, else creation) to the target date.
    private static func pace(_ scope: InsightsScope, for goal: InsightsGoal) -> InsightsGoalPace? {
        guard let progress = goal.progress, let targetDate = goal.targetDate else { return nil }
        let start = goal.startDate ?? goal.createdAt
        let total = scope.civilDayDistance(from: start, to: targetDate)
        guard total > 0 else { return nil }
        let elapsed = scope.civilDayDistance(from: start, to: scope.today)
        let elapsedShare = min(max(Double(elapsed) / Double(total), 0), 1)
        let lead = progress - elapsedShare
        // The tolerance keeps 0.6 - 0.5, which is 0.0999… in binary,
        // on the "ahead" side of 0.1.
        let tolerance = 1e-9
        if lead >= 0.1 - tolerance { return .ahead }
        if lead >= -0.1 - tolerance { return .onTrack }
        return .behind
    }

    /// Civil days from today to the target date, 0 on the day. `nil`
    /// without a target date or after it.
    private static func daysLeft(_ scope: InsightsScope, for goal: InsightsGoal) -> Int? {
        guard let targetDate = goal.targetDate else { return nil }
        let days = scope.civilDayDistance(from: scope.today, to: targetDate)
        return days >= 0 ? days : nil
    }

    /// Nearest target date first (no target date last), then the name.
    private static func goalSortsBefore(_ lhs: InsightsGoal, _ rhs: InsightsGoal) -> Bool {
        switch (lhs.targetDate, rhs.targetDate) {
        case let (lhsTarget?, rhsTarget?) where lhsTarget != rhsTarget:
            return lhsTarget < rhsTarget
        case (.some, nil):
            return true
        case (nil, .some):
            return false
        default:
            break
        }
        switch lhs.name.localizedStandardCompare(rhs.name) {
        case .orderedAscending: return true
        case .orderedDescending: return false
        case .orderedSame: return lhs.id.uuidString < rhs.id.uuidString
        }
    }
}
