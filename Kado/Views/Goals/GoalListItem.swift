import Foundation
import KadoCore

/// Navigation, lists, and sheets retain values, never SwiftData records.
struct GoalListItem: Identifiable {
    let id: UUID
    let name: String
    let details: String
    let status: GoalStatus
    let startDate: Date?
    let targetDate: Date?
    let completedAt: Date?
    let archivedAt: Date?
    let measurement: GoalMeasurement
    /// The stored category, or `nil` when none is set.
    let category: ItemCategory?

    /// The category rows show: stored, else guessed from the name, else
    /// Other. The rule Insights counts by.
    var resolvedCategory: ItemCategory {
        CategoryResolver.resolve(stored: category, goalCategory: nil, title: name)
    }

    init(_ record: GoalRecord) {
        id = record.id
        name = record.name
        details = record.details
        status = record.status
        startDate = record.startDate
        targetDate = record.targetDate
        completedAt = record.completedAt
        archivedAt = record.archivedAt
        measurement = record.measurement
        category = record.category
    }

    init(
        id: UUID = UUID(), name: String, details: String = "", status: GoalStatus = .active,
        startDate: Date? = nil, targetDate: Date? = nil,
        completedAt: Date? = nil, archivedAt: Date? = nil, measurement: GoalMeasurement = GoalMeasurement(),
        category: ItemCategory? = nil
    ) {
        self.id = id
        self.name = name
        self.details = details
        self.status = status
        self.startDate = startDate
        self.targetDate = targetDate
        self.completedAt = completedAt
        self.archivedAt = archivedAt
        self.measurement = measurement
        self.category = category
    }
}

extension GoalStatus {
    var plannerTitle: String {
        switch self {
        case .active: String(localized: "Active")
        case .paused: String(localized: "Paused")
        case .completed: String(localized: "Completed")
        }
    }

    var plannerSymbol: String {
        switch self {
        case .active: "scope"
        case .paused: "pause.circle"
        case .completed: "checkmark.circle"
        }
    }
}

struct GoalRoute: Hashable {
    let id: UUID
}
