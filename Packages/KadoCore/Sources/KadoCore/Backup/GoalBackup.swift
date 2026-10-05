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
    /// Raw `ItemCategory` value, `""` when not set. Files older than
    /// format 6 have no such key and decode as `""`.
    public var category: String

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
        measurement: GoalMeasurement? = nil,
        category: String = ""
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
        self.category = category
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, details, status, startDate, targetDate, createdAt, updatedAt
        case completedAt, archivedAt, measurement, category
    }

    /// Decodes every key the synthesized decoder read before format 6,
    /// and reads a missing `category` as `""`.
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        name = try values.decode(String.self, forKey: .name)
        details = try values.decode(String.self, forKey: .details)
        status = try values.decode(GoalStatus.self, forKey: .status)
        startDate = try values.decodeIfPresent(Date.self, forKey: .startDate)
        targetDate = try values.decodeIfPresent(Date.self, forKey: .targetDate)
        createdAt = try values.decode(Date.self, forKey: .createdAt)
        updatedAt = try values.decode(Date.self, forKey: .updatedAt)
        completedAt = try values.decodeIfPresent(Date.self, forKey: .completedAt)
        archivedAt = try values.decodeIfPresent(Date.self, forKey: .archivedAt)
        measurement = try values.decodeIfPresent(GoalMeasurement.self, forKey: .measurement)
        category = try values.decodeIfPresent(String.self, forKey: .category) ?? ""
    }
}
