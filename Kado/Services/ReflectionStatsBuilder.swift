import Foundation
import SwiftData
import KadoCore

/// A month in Kado's numbers, shown beside what the user wrote.
struct ReflectionMonthStats: Equatable {
    var tasksDone: Int
    /// Days a habit was logged, summed over habits ("don't" habits aside).
    var habitCheckIns: Int
    /// Time tracked in work sessions that started in the month.
    var focusSeconds: TimeInterval
    /// Days with at least one task done or habit logged.
    var activeDays: Int

    static let empty = ReflectionMonthStats(tasksDone: 0, habitCheckIns: 0, focusSeconds: 0, activeDays: 0)

    var isEmpty: Bool { self == .empty }
}

/// Reads the month's numbers from the store. Habit logs count on their
/// stamped day (already the logical day); tasks on the civil day of
/// `completedAt`; sessions by when they started.
@MainActor
struct ReflectionStatsBuilder {
    let calendar: Calendar

    func stats(for month: ReflectionMonth, in context: ModelContext) -> ReflectionMonthStats {
        let interval = month.interval(in: calendar)
        let start = interval.start
        let end = interval.end
        var days = Set<Date>()

        let tasks = (try? context.fetch(FetchDescriptor<TaskRecord>(predicate: #Predicate { task in
            task.completedAt != nil
        }))) ?? []
        var tasksDone = 0
        for task in tasks {
            guard let done = task.completedAt, done >= start, done < end, task.externalCancelledAt == nil else { continue }
            tasksDone += 1
            days.insert(calendar.startOfDay(for: done))
        }

        let completions = (try? context.fetch(FetchDescriptor<CompletionRecord>(predicate: #Predicate { completion in
            completion.date >= start && completion.date < end && completion.value > 0
        }))) ?? []
        var habitCheckIns = 0
        for completion in completions {
            guard let habit = completion.habit else { continue }
            if case .negative = habit.type { continue }
            habitCheckIns += 1
            days.insert(calendar.startOfDay(for: completion.date))
        }

        let sessions = (try? context.fetch(FetchDescriptor<WorkSessionRecord>(predicate: #Predicate { session in
            session.startedAt >= start && session.startedAt < end && session.endedAt != nil
        }))) ?? []
        let focus = sessions.reduce(0) { total, session in
            total + session.snapshot.elapsed(at: session.endedAt ?? session.startedAt)
        }

        return ReflectionMonthStats(tasksDone: tasksDone, habitCheckIns: habitCheckIns, focusSeconds: focus, activeDays: days.count)
    }
}
