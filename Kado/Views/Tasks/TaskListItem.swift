import Foundation
import KadoCore

/// Value snapshots keep list diffs and presented forms independent of
/// managed objects from a previous SwiftData container.
struct TaskListItem: Identifiable {
    let id: UUID
    let title: String
    let notes: String
    let dueDate: Date?
    let completedAt: Date?
    let isFromGoogle: Bool
    let schedules: [TaskScheduleItem]
    let goalID: UUID?
    let goalName: String?

    var isComplete: Bool { completedAt != nil }

    init(_ record: TaskRecord) {
        id = record.id
        title = record.title
        notes = record.notes
        dueDate = record.dueDate
        completedAt = record.completedAt
        isFromGoogle = record.externalEventID != nil
        goalID = record.goal?.id
        goalName = record.goal?.name
        schedules = (record.scheduleBlocks ?? [])
            .map { TaskScheduleItem($0) }
            .sorted { $0.plannedDay == $1.plannedDay
                ? $0.createdAt < $1.createdAt
                : $0.plannedDay < $1.plannedDay }
    }

    init(
        id: UUID = UUID(), title: String, notes: String = "", dueDate: Date? = nil,
        completedAt: Date? = nil, isFromGoogle: Bool = false,
        schedules: [TaskScheduleItem] = [], goalID: UUID? = nil, goalName: String? = nil
    ) {
        self.id = id
        self.title = title
        self.notes = notes
        self.dueDate = dueDate
        self.completedAt = completedAt
        self.isFromGoogle = isFromGoogle
        self.schedules = schedules
        self.goalID = goalID
        self.goalName = goalName
    }
}

struct TaskScheduleItem: Identifiable {
    let id: UUID
    let plannedDay: Date
    let startAt: Date?
    let endAt: Date?
    let createdAt: Date

    init(_ record: ScheduleBlockRecord) {
        id = record.id
        plannedDay = record.plannedDay
        startAt = record.startAt
        endAt = record.endAt
        createdAt = record.createdAt
    }

    init(
        id: UUID = UUID(), plannedDay: Date, startAt: Date? = nil,
        endAt: Date? = nil, createdAt: Date = .now
    ) {
        self.id = id
        self.plannedDay = plannedDay
        self.startAt = startAt
        self.endAt = endAt
        self.createdAt = createdAt
    }

    /// Both time bounds are optional independently. Never invent an
    /// end time for a start-only task, or a start for an end-only task.
    var timeLabel: String {
        switch (startAt, endAt) {
        case (.some(let start), .some(let end)):
            return "\(start.formatted(date: .omitted, time: .shortened)) – \(end.formatted(date: .omitted, time: .shortened))"
        case (.some(let start), nil):
            return String(localized: "Starts at \(start.formatted(date: .omitted, time: .shortened))")
        case (nil, .some(let end)):
            return String(localized: "Ends at \(end.formatted(date: .omitted, time: .shortened))")
        case (nil, nil):
            return String(localized: "Any time")
        }
    }

    func belongs(to day: Date, calendar: Calendar) -> Bool {
        if let startAt, let endAt, let interval = calendar.dateInterval(of: .day, for: day) {
            return startAt < interval.end && endAt > interval.start
        }
        return calendar.isDate(plannedDay, inSameDayAs: day)
    }
}
