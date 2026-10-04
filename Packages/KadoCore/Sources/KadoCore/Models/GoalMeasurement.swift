import Foundation

public enum GoalProgressMode: String, CaseIterable, Codable, Sendable {
    case manual, tasks, habit
}

public struct GoalMeasurement: Hashable, Codable, Sendable {
    public var enabled: Bool
    public var mode: GoalProgressMode
    public var baseline: Double
    public var target: Double
    public var unit: String
    public var habitID: UUID?

    public init(enabled: Bool = false, mode: GoalProgressMode = .manual, baseline: Double = 0, target: Double = 1, unit: String = "", habitID: UUID? = nil) {
        self.enabled = enabled; self.mode = mode; self.baseline = baseline
        self.target = target; self.unit = unit; self.habitID = habitID
    }

    public var isValid: Bool {
        baseline.isFinite && target.isFinite && baseline >= 0 && target > baseline
            && (!enabled || (mode == .tasks || !unit.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty))
            && (!enabled || mode != .habit || habitID != nil)
    }
}

/// Manual contributions are independent of habit/task completion records.
public struct GoalProgressEntry: Identifiable, Hashable, Codable, Sendable {
    public var id: UUID
    public var goalID: UUID
    public var date: Date
    public var amount: Double
    public var note: String?
    public var createdAt: Date
    public var updatedAt: Date

    public init(id: UUID = UUID(), goalID: UUID, date: Date = .now, amount: Double, note: String? = nil, createdAt: Date = .now, updatedAt: Date = .now) {
        self.id = id; self.goalID = goalID; self.date = date; self.amount = amount
        self.note = note; self.createdAt = createdAt; self.updatedAt = updatedAt
    }
    public var isValid: Bool {
        amount.isFinite && amount > 0 && [date, createdAt, updatedAt].allSatisfy { $0.timeIntervalSinceReferenceDate.isFinite }
    }
}
