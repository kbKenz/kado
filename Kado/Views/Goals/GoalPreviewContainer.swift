import Foundation
import KadoCore
import SwiftData

/// Stable preview identities for filled forms, every goal status, and
/// mixed linked-item history. This container never touches a live store.
@MainActor
enum GoalPreviewContainer {
    static let healthGoalID = UUID()
    static let archivedGoalID = UUID()

    static let shared: ModelContainer = {
        do {
            let schema = Schema(versionedSchema: KadoSchemaV10.self)
            let container = try ModelContainer(
                for: schema, migrationPlan: KadoMigrationPlan.self,
                configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            )
            let context = container.mainContext
            let calendar = Calendar.current
            let day = calendar.startOfDay(for: .now)
            let health = GoalRecord(id: healthGoalID, name: "Make more time for health",
                                    details: "Build a routine that fits an ordinary week.",
                                    startDate: day, targetDate: calendar.date(byAdding: .month, value: 2, to: day))
            health.measurement = GoalMeasurement(enabled: true, mode: .tasks, target: 5, unit: "tasks")
            let language = GoalRecord(name: "Learn conversational Japanese", status: .paused)
            let finished = GoalRecord(name: "Finish the first draft", status: .completed, completedAt: .now)
            let archived = GoalRecord(id: archivedGoalID, name: "Plan a long trip", status: .paused, archivedAt: .now)
            for goal in [health, language, finished, archived] { context.insert(goal) }

            let appointment = TaskRecord(title: "Book a checkup", dueDate: day, goal: health)
            let bottle = TaskRecord(title: "Buy a water bottle", completedAt: .now, goal: health)
            let meeting = TaskRecord(title: "Meeting with Thomas", dueDate: day,
                                     externalCalendarID: "primary", externalEventID: "preview-meeting", goal: health)
            let oldTask = TaskRecord(title: "Old appointment", completedAt: .now, archivedAt: .now, goal: health)
            let cancelled = TaskRecord(title: "Cancelled booking",
                                       externalEventID: "preview-cancelled", externalCancelledAt: .now, goal: health)
            let practice = TaskRecord(title: "Practice Japanese phrases", goal: language)
            let inbox = TaskRecord(title: "Renew passport")
            for task in [appointment, bottle, meeting, oldTask, cancelled, practice, inbox] { context.insert(task) }
            context.insert(ScheduleBlockRecord(plannedDay: day,
                startAt: calendar.date(bySettingHour: 9, minute: 0, second: 0, of: day),
                endAt: calendar.date(bySettingHour: 10, minute: 0, second: 0, of: day), task: meeting))

            let walk = HabitRecord(name: "Morning walk", goal: health)
            let stretch = HabitRecord(name: "Evening stretch", goal: health)
            let snacking = HabitRecord(name: "Less late-night snacking", type: .negative, goal: health)
            let oldRoutine = HabitRecord(name: "Old gym routine", archivedAt: .now, goal: health)
            let vocabulary = HabitRecord(name: "Vocabulary practice", goal: language)
            for habit in [walk, stretch, snacking, oldRoutine, vocabulary] { context.insert(habit) }
            context.insert(CompletionRecord(date: day, value: 1, habit: walk))
            context.insert(CompletionRecord(date: day, value: 1, habit: snacking))
            try context.save()
            return container
        } catch {
            fatalError("Failed to construct goal preview container: \(error)")
        }
    }()
}
