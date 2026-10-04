import Foundation
import KadoCore

extension GoalProgressMode {
    var plannerTitle: String {
        switch self {
        case .manual: String(localized: "Manual amounts")
        case .tasks: String(localized: "Completed tasks")
        case .habit: String(localized: "Habit values")
        }
    }
}

extension GoalRecord {
    func progress(today: Date, calendar: Calendar) -> GoalProgressResult {
        GoalProgressCalculator.calculate(
            goalID: id, measurement: measurement, startDate: startDate, today: today, calendar: calendar,
            entries: (progressEntries ?? []).compactMap(\.snapshot),
            tasks: (tasks ?? []).map { TaskBackup(id: $0.id, title: $0.title, createdAt: $0.createdAt, updatedAt: $0.updatedAt, completedAt: $0.completedAt, goalID: $0.goal?.id) },
            habits: (habits ?? []).map(\.snapshot),
            completions: (habits ?? []).flatMap { ($0.completions ?? []).compactMap(\.snapshot) }
        )
    }
}

struct GoalProgressDisplay {
    static func unit(_ raw: String, mode: GoalProgressMode) -> String {
        if mode == .tasks { return String(localized: "tasks") }
        if mode == .habit && raw == "minutes" { return String(localized: "minutes") }
        return raw
    }
}
