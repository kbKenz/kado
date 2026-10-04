import Foundation

/// Tracked time, with stable links to its task, habit and planned block.
public struct WorkSessionBackup: Hashable, Codable, Sendable {
    public var id: UUID
    public var startedAt: Date
    public var endedAt: Date?
    public var pausedAt: Date?
    public var pausedSeconds: Double
    public var createdAt: Date
    public var updatedAt: Date
    public var taskID: UUID?
    public var habitID: UUID?
    public var scheduleBlockID: UUID?

    public init(
        id: UUID, startedAt: Date, endedAt: Date?, pausedAt: Date?, pausedSeconds: Double,
        createdAt: Date, updatedAt: Date, taskID: UUID?, habitID: UUID?, scheduleBlockID: UUID?
    ) {
        self.id = id
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.pausedAt = pausedAt
        self.pausedSeconds = pausedSeconds
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.taskID = taskID
        self.habitID = habitID
        self.scheduleBlockID = scheduleBlockID
    }
}
