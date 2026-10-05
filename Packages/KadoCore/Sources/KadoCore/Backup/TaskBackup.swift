import Foundation

/// Portable task data. OAuth credentials never enter the backup;
/// external IDs only retain the provenance of imported calendar events.
public struct TaskBackup: Hashable, Codable, Sendable {
    public var id: UUID
    public var title: String
    public var notes: String
    public var dueDate: Date?
    public var createdAt: Date
    public var updatedAt: Date
    public var completedAt: Date?
    public var archivedAt: Date?
    public var externalAccountID: String?
    public var externalCalendarID: String?
    public var externalEventID: String?
    public var externalURL: String?
    public var externalUpdatedAt: Date?
    public var externalCancelledAt: Date?
    public var goalID: UUID?
    /// Raw `ItemCategory` value, `""` when not set. Files older than
    /// format 6 have no such key and decode as `""`.
    public var category: String

    public init(
        id: UUID,
        title: String,
        notes: String = "",
        dueDate: Date? = nil,
        createdAt: Date,
        updatedAt: Date,
        completedAt: Date? = nil,
        archivedAt: Date? = nil,
        externalAccountID: String? = nil,
        externalCalendarID: String? = nil,
        externalEventID: String? = nil,
        externalURL: String? = nil,
        externalUpdatedAt: Date? = nil,
        externalCancelledAt: Date? = nil,
        goalID: UUID? = nil,
        category: String = ""
    ) {
        self.id = id
        self.title = title
        self.notes = notes
        self.dueDate = dueDate
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.completedAt = completedAt
        self.archivedAt = archivedAt
        self.externalAccountID = externalAccountID
        self.externalCalendarID = externalCalendarID
        self.externalEventID = externalEventID
        self.externalURL = externalURL
        self.externalUpdatedAt = externalUpdatedAt
        self.externalCancelledAt = externalCancelledAt
        self.goalID = goalID
        self.category = category
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, notes, dueDate, createdAt, updatedAt, completedAt, archivedAt
        case externalAccountID, externalCalendarID, externalEventID, externalURL
        case externalUpdatedAt, externalCancelledAt, goalID, category
    }

    /// Decodes every key the synthesized decoder read before format 6,
    /// and reads a missing `category` as `""`.
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        title = try values.decode(String.self, forKey: .title)
        notes = try values.decode(String.self, forKey: .notes)
        dueDate = try values.decodeIfPresent(Date.self, forKey: .dueDate)
        createdAt = try values.decode(Date.self, forKey: .createdAt)
        updatedAt = try values.decode(Date.self, forKey: .updatedAt)
        completedAt = try values.decodeIfPresent(Date.self, forKey: .completedAt)
        archivedAt = try values.decodeIfPresent(Date.self, forKey: .archivedAt)
        externalAccountID = try values.decodeIfPresent(String.self, forKey: .externalAccountID)
        externalCalendarID = try values.decodeIfPresent(String.self, forKey: .externalCalendarID)
        externalEventID = try values.decodeIfPresent(String.self, forKey: .externalEventID)
        externalURL = try values.decodeIfPresent(String.self, forKey: .externalURL)
        externalUpdatedAt = try values.decodeIfPresent(Date.self, forKey: .externalUpdatedAt)
        externalCancelledAt = try values.decodeIfPresent(Date.self, forKey: .externalCancelledAt)
        goalID = try values.decodeIfPresent(UUID.self, forKey: .goalID)
        category = try values.decodeIfPresent(String.self, forKey: .category) ?? ""
    }
}
