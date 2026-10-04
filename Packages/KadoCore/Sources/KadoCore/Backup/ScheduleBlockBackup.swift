import Foundation

/// Planned time and stable relationship IDs, separate from completion.
public struct ScheduleBlockBackup: Hashable, Codable, Sendable {
    public var id: UUID
    public var plannedDay: Date
    public var startAt: Date?
    public var endAt: Date?
    public var createdAt: Date
    public var updatedAt: Date
    public var taskID: UUID?
    public var habitID: UUID?

    public init(
        id: UUID,
        plannedDay: Date,
        startAt: Date? = nil,
        endAt: Date? = nil,
        createdAt: Date,
        updatedAt: Date,
        taskID: UUID? = nil,
        habitID: UUID? = nil
    ) {
        self.id = id
        self.plannedDay = plannedDay
        self.startAt = startAt
        self.endAt = endAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.taskID = taskID
        self.habitID = habitID
    }
}
