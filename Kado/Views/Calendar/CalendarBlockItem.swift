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
    /// The task's category icon or the habit's own icon. `nil` for a
    /// Health entry, which has its own symbol, and an unlinked block.
    let glyph: ItemGlyph?

    var isFromHealth: Bool { healthKind != nil }

    /// The name used for any activity without its own name.
    static var genericWorkoutName: String {
        String(localized: "Workout", comment: "Generic workout name shown on the Calendar timeline.")
    }

    /// SF Symbol for a Health entry; nil for planned blocks.
    var healthSymbol: String? {
        switch healthKind {
        case .sleep: "bed.double.fill"
        case .workout: "figure.run"
        case nil: nil
        }
    }

    init(_ record: ScheduleBlockRecord, on day: Date, calendar: Calendar) {
        id = record.id
        schedule = TaskScheduleItem(record)
        if let taskRecord = record.task {
            let task = TaskListItem(taskRecord)
            self.task = task
            title = task.title
            habitID = nil
            isComplete = task.isComplete
            glyph = ItemGlyph(category: task.resolvedCategory)
        } else if let habit = record.habit {
            task = nil
            title = habit.name
            habitID = habit.id
            isComplete = HabitRowState.resolve(
                habit: habit.snapshot, completions: (habit.completions ?? []).compactMap(\.snapshot),
                calendar: calendar, asOf: day
            ).status == .complete
            glyph = ItemGlyph(habitIcon: habit.icon, color: habit.color)
        } else {
            task = nil
            title = String(localized: "Unlinked planned block")
            habitID = nil
            isComplete = false
            glyph = nil
        }
        healthKind = nil
    }

    /// Without a `glyph`, a task block takes its task's category icon.
    init(id: UUID = UUID(), title: String, schedule: TaskScheduleItem, task: TaskListItem? = nil, habitID: UUID? = nil, isComplete: Bool = false, healthKind: HealthTimelineEntry.Kind? = nil, glyph: ItemGlyph? = nil) {
        self.id = id
        self.title = title
        self.schedule = schedule
        self.task = task
        self.habitID = habitID
        self.isComplete = isComplete
        self.healthKind = healthKind
        self.glyph = glyph ?? task.map { ItemGlyph(category: $0.resolvedCategory) }
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
        glyph = nil
    }
}
