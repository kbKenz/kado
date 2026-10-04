import Foundation

/// Portable goal metadata. Relationships are carried by each linked
/// habit or task's optional goal ID, avoiding nested duplicate items.
public struct GoalBackup: Hashable, Codable, Sendable {
    public var id: UUID
    public var name: String
    public var details: String
    public var status: GoalStatus
    public var startDate: Date?
    public var targetDate: Date?
    public var createdAt: Date
    public var updatedAt: Date
    public var completedAt: Date?
    public var archivedAt: Date?
    public var measurement: GoalMeasurement?

    public init(
        id: UUID,
        name: String,
        details: String = "",
        status: GoalStatus = .active,
        startDate: Date? = nil,
        targetDate: Date? = nil,
        createdAt: Date,
        updatedAt: Date,
        completedAt: Date? = nil,
        archivedAt: Date? = nil,
        measurement: GoalMeasurement? = nil
    ) {
        self.id = id
        self.name = name
        self.details = details
        self.status = status
        self.startDate = startDate
        self.targetDate = targetDate
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.completedAt = completedAt
        self.archivedAt = archivedAt
        self.measurement = measurement
    }
}
