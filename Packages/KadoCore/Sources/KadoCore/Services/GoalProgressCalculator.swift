import Foundation

public struct GoalProgressContribution: Identifiable, Hashable, Sendable {
    public enum Source: Hashable, Sendable { case manual(UUID), task(UUID), habit(UUID) }
    public var id: UUID
    public var date: Date
    public var amount: Double
    public var title: String
    public var source: Source
}

public struct GoalProgressResult: Sendable {
    public var current: Double
    public var fraction: Double
    public var unit: String
    public var isAvailable: Bool
    public var contributions: [GoalProgressContribution]
}

public enum GoalProgressCalculator {
    public static func calculate(
        goalID: UUID, measurement: GoalMeasurement, startDate: Date? = nil,
        today: Date, calendar: Calendar, entries: [GoalProgressEntry] = [],
        tasks: [TaskBackup] = [], habits: [Habit] = [], completions: [Completion] = []
    ) -> GoalProgressResult {
        let end = calendar.startOfDay(for: today)
        let start = startDate.map { calendar.startOfDay(for: $0) }
        func included(_ date: Date) -> Bool {
            guard date.timeIntervalSinceReferenceDate.isFinite else { return false }
            let day = calendar.startOfDay(for: date)
            return day <= end && (start == nil || day >= start!)
        }
        var result = GoalProgressResult(current: measurement.baseline, fraction: 0, unit: measurement.mode == .tasks ? "tasks" : measurement.unit, isAvailable: measurement.isValid, contributions: [])
        guard measurement.enabled, result.isAvailable else { return result }
        var seen = Set<UUID>()
        switch measurement.mode {
        case .manual:
            result.contributions = entries.filter { $0.goalID == goalID && $0.isValid && included($0.date) && seen.insert($0.id).inserted }.map {
                GoalProgressContribution(id: $0.id, date: $0.date, amount: $0.amount, title: $0.note ?? "", source: .manual($0.id))
            }
        case .tasks:
            result.contributions = tasks.compactMap { task in
                guard task.goalID == goalID, let date = task.completedAt, included(date), seen.insert(task.id).inserted else { return nil }
                return GoalProgressContribution(id: task.id, date: date, amount: 1, title: task.title, source: .task(task.id))
            }
        case .habit:
            guard let habit = habits.first(where: { $0.id == measurement.habitID && $0.goalID == goalID }) else {
                result.isAvailable = false; return result
            }
            let divisor: Double
            switch habit.type {
            case .counter: divisor = 1
            case .timer: divisor = 60; result.unit = "minutes"
            default: result.isAvailable = false; return result
            }
            result.contributions = completions.filter { $0.habitID == habit.id && $0.value.isFinite && $0.value > 0 && included($0.date) && seen.insert($0.id).inserted }.map {
                GoalProgressContribution(id: $0.id, date: $0.date, amount: $0.value / divisor, title: $0.note ?? habit.name, source: .habit(habit.id))
            }
        }
        result.contributions.sort { $0.date == $1.date ? $0.id.uuidString < $1.id.uuidString : $0.date > $1.date }
        result.current += result.contributions.reduce(0) { $0 + $1.amount }
        guard result.current.isFinite else { result.isAvailable = false; return result }
        result.fraction = min(1, max(0, (result.current - measurement.baseline) / (measurement.target - measurement.baseline)))
        return result
    }
}
