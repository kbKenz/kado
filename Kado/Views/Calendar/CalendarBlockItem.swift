import Foundation
import KadoCore

struct CalendarBlockItem: Identifiable {
    let id: UUID
    let title: String
    let schedule: TaskScheduleItem
    let task: TaskListItem?
    let habitID: UUID?
    let isComplete: Bool

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
    }

    init(id: UUID = UUID(), title: String, schedule: TaskScheduleItem, task: TaskListItem? = nil, habitID: UUID? = nil, isComplete: Bool = false) {
        self.id = id
        self.title = title
        self.schedule = schedule
        self.task = task
        self.habitID = habitID
        self.isComplete = isComplete
    }
}
