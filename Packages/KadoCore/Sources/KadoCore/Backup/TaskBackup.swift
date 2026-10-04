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
        goalID: UUID? = nil
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
    }
}
