import Foundation
import SwiftData
import KadoCore

/// Reads every record the Insights need and turns it into values.
///
/// Categories are resolved here, once: the stored category, else the
/// goal's, else the keyword classifier on the title, else Other
/// (`CategoryResolver`). Nothing is written back. Health is merged in
/// separately by `InsightsHealthLoader`, because it is async.
@MainActor
struct InsightsInputBuilder {
    let civilToday: Date
    let calendar: Calendar

    func build(in context: ModelContext) throws -> InsightsInput {
        let habitRecords = try context.fetch(FetchDescriptor<HabitRecord>())
        let taskRecords = try context.fetch(FetchDescriptor<TaskRecord>())
        let sessionRecords = try context.fetch(FetchDescriptor<WorkSessionRecord>())
        let goalRecords = try context.fetch(FetchDescriptor<GoalRecord>())

        var habitCategories: [UUID: ItemCategory] = [:]
        let habits = habitRecords.map { record -> InsightsHabit in
            let category = CategoryResolver.resolve(
                stored: record.category,
                goalCategory: record.goal?.category,
                title: record.name
            )
            habitCategories[record.id] = category
            return InsightsHabit(
                habit: record.snapshot,
                category: category,
                completions: (record.completions ?? []).compactMap(\.snapshot)
            )
        }

        var taskCategories: [UUID: ItemCategory] = [:]
        let tasks = taskRecords.map { record -> InsightsTask in
            let category = CategoryResolver.resolve(
                stored: record.category,
                goalCategory: record.goal?.category,
                title: record.title
            )
            taskCategories[record.id] = category
            let plannedDays = Set((record.scheduleBlocks ?? []).map { calendar.startOfDay(for: $0.plannedDay) })
            return InsightsTask(
                id: record.id,
                title: record.title,
                category: category,
                createdAt: record.createdAt,
                completedAt: record.completedAt,
                archivedAt: record.archivedAt,
                dueDay: record.dueDate.map { calendar.startOfDay(for: $0) },
                plannedDays: plannedDays.sorted(),
                goalID: record.goal?.id,
                isCancelled: record.externalCancelledAt != nil
            )
        }

        let sessions = sessionRecords.compactMap { record -> InsightsSession? in
            let taskID = record.task?.id
            let habitID = record.habit?.id
            let category = taskID.flatMap { taskCategories[$0] }
                ?? habitID.flatMap { habitCategories[$0] }
                ?? .other
            var planned: DateInterval?
            if let block = record.scheduleBlock, let start = block.startAt, let end = block.endAt, end > start {
                planned = DateInterval(start: start, end: end)
            }
            return InsightsSession(
                id: record.id,
                session: record.snapshot,
                category: category,
                taskID: taskID,
                habitID: habitID,
                plannedRange: planned
            )
        }

        let goals = goalRecords.map { record -> InsightsGoal in
            var progress: Double?
            if record.measurement.enabled {
                let result = record.progress(today: civilToday, calendar: calendar)
                if result.isAvailable { progress = result.fraction }
            }
            return InsightsGoal(
                id: record.id,
                name: record.name,
                category: record.category ?? CategoryClassifier.classify(record.name) ?? .other,
                status: record.status,
                isArchived: record.archivedAt != nil,
                startDate: record.startDate,
                targetDate: record.targetDate,
                createdAt: record.createdAt,
                progress: progress,
                linkedTaskIDs: (record.tasks ?? []).map(\.id),
                linkedHabitIDs: (record.habits ?? []).map(\.id)
            )
        }

        return InsightsInput(habits: habits, tasks: tasks, sessions: sessions, goals: goals)
    }
}
