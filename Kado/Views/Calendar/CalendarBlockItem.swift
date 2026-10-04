import Foundation
import KadoCore

struct CalendarBlockItem: Identifiable {
    let id: UUID
    let title: String
    let schedule: TaskScheduleItem
    let task: TaskListItem?
    let habitID: UUID?
    let isComplete: Bool
    /// Non-nil for a read-only Health entry (sleep or workout).
    let healthKind: HealthTimelineEntry.Kind?

    var isFromHealth: Bool { healthKind != nil }

    init(_ record: ScheduleBlockRecord, on day: Date, calendar: Calendar) {
        id = record.id
        schedule = TaskScheduleItem(record)
        if let taskRecord = record.task {
            let task = TaskListItem(taskRecord)
            self.task = task
            title = task.title
            habitID = nil
            isComplete = task.isComplete
        } else if let habit = record.habit {
            task = nil
            title = habit.name
            habitID = habit.id
            isComplete = HabitRowState.resolve(
                habit: habit.snapshot, completions: (habit.completions ?? []).compactMap(\.snapshot),
                calendar: calendar, asOf: day
            ).status == .complete
        } else {
            task = nil
            title = String(localized: "Unlinked planned block")
            habitID = nil
            isComplete = false
        }
        healthKind = nil
    }

    init(id: UUID = UUID(), title: String, schedule: TaskScheduleItem, task: TaskListItem? = nil, habitID: UUID? = nil, isComplete: Bool = false, healthKind: HealthTimelineEntry.Kind? = nil) {
        self.id = id
        self.title = title
        self.schedule = schedule
        self.task = task
        self.habitID = habitID
        self.isComplete = isComplete
        self.healthKind = healthKind
    }

    init(_ entry: HealthTimelineEntry) {
        id = entry.id
        switch entry.kind {
        case .sleep: title = String(localized: "Sleep", comment: "Calendar timeline: a sleep session read from Health.")
        case .workout(let name): title = name
        }
        schedule = TaskScheduleItem(id: entry.id, plannedDay: entry.interval.start,
                                    startAt: entry.interval.start, endAt: entry.interval.end)
        task = nil
        habitID = nil
        isComplete = false
        healthKind = entry.kind
    }
}
