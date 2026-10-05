import Foundation

extension InsightsCalculator {
    /// One row per active habit.
    /// Rules: see `[InsightsHabitRow]` in InsightsReport.swift.
    static func habits(_ scope: InsightsScope) -> [InsightsHabitRow] {
        scope.input.habits
            .filter { $0.habit.archivedAt == nil }
            .map { SortableHabitRow(row: habitRow(scope, for: $0), sortOrder: $0.habit.sortOrder) }
            .sorted { $0.sortsBefore($1) }
            .map(\.row)
    }

    private static func habitRow(_ scope: InsightsScope, for habit: InsightsHabit) -> InsightsHabitRow {
        let model = habit.habit
        let context = scope.context
        let positive = habit.completions.filter { $0.value > 0 }
        let periodDays = Set(scope.days)
        let periodPositive = positive.filter { periodDays.contains(scope.calendar.startOfDay(for: $0.date)) }
        let allTimeDays = Set(positive.map { scope.calendar.startOfDay(for: $0.date) })
        return InsightsHabitRow(
            habitID: model.id,
            name: model.name,
            icon: model.icon,
            color: model.color,
            category: habit.category,
            type: model.type,
            rate: scope.habitConsistency(of: [habit], over: scope.days),
            timesDone: scope.daysWithPositiveRecord(of: habit, in: scope.days),
            amount: amount(of: periodPositive, for: model.type),
            allTimeTimesDone: allTimeDays.count,
            allTimeAmount: amount(of: positive, for: model.type),
            currentStreak: context.streakCalculator.current(for: model, completions: habit.completions, asOf: scope.today),
            bestStreak: context.streakCalculator.best(for: model, completions: habit.completions, asOf: scope.today),
            score: context.scoreCalculator.currentScore(for: model, completions: habit.completions, asOf: scope.today)
        )
    }

    /// Units for a counter, seconds for a timer, 0 for binary and
    /// negative habits.
    private static func amount(of completions: [Completion], for type: HabitType) -> Double {
        switch type {
        case .counter, .timer:
            return completions.reduce(0) { $0 + $1.value }
        case .binary, .negative:
            return 0
        }
    }
}

/// A habit row with the user's order, which the row itself does not
/// carry.
private struct SortableHabitRow {
    let row: InsightsHabitRow
    let sortOrder: Int

    /// Consistency first (no due day last), then times done, then the
    /// user's order, then the name.
    func sortsBefore(_ other: SortableHabitRow) -> Bool {
        let rate = row.rate
        let otherRate = other.row.rate
        if (rate.total > 0) != (otherRate.total > 0) {
            return rate.total > 0
        }
        // Cross-multiplied, so equal fractions compare equal exactly.
        let share = rate.done * otherRate.total
        let otherShare = otherRate.done * rate.total
        if share != otherShare {
            return share > otherShare
        }
        if row.timesDone != other.row.timesDone {
            return row.timesDone > other.row.timesDone
        }
        if sortOrder != other.sortOrder {
            return sortOrder < other.sortOrder
        }
        switch row.name.localizedStandardCompare(other.row.name) {
        case .orderedAscending: return true
        case .orderedDescending: return false
        case .orderedSame: return row.habitID.uuidString < other.row.habitID.uuidString
        }
    }
}
