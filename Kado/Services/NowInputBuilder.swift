import Foundation
import SwiftData
import KadoCore

/// Reads the store and produces what `NowResolver` and the "Start
/// something…" list need, as values. All "can this be worked on now?"
/// rules live here.
@MainActor
struct NowInputBuilder {
    struct Input: Equatable {
        var blocks: [NowBlock]
        var openSession: OpenSession?
        var startCandidates: [NowItem]
    }

    let boundary: DayBoundary
    let evaluator: any FrequencyEvaluating

    func build(now: Date, in context: ModelContext) throws -> Input {
        // Completions are stamped so their civil day equals the logical
        // day, so habit rules take the logical day start, as Today does.
        let day = boundary.startOfDay(for: now)
        // The logical day as instants: `startOfDay` is a calendar midnight,
        // so the lower bound is its rollover instant (04:00 under a 4 AM start).
        let dayStart = boundary.rollover(into: day)
        let dayEnd = boundary.nextRollover(after: now)
        let distantPast = Date.distantPast

        let noDate: Date? = nil
        let openTasks = #Predicate<TaskRecord> { task in
            task.completedAt == noDate && task.archivedAt == noDate && task.externalCancelledAt == noDate
        }
        let liveHabits = #Predicate<HabitRecord> { habit in habit.archivedAt == nil }
        let tasks = try context.fetch(FetchDescriptor<TaskRecord>(predicate: openTasks))
        let habits = try context.fetch(FetchDescriptor<HabitRecord>(predicate: liveHabits))
        let workableTasks = tasks.sorted(by: Self.taskPrecedes)
        let workableHabits = habits.filter { isWorkable($0, on: day) }.sorted(by: Self.habitPrecedes)
        let taskIDs = Set(workableTasks.map(\.id))
        let habitIDs = Set(workableHabits.map(\.id))

        // A missing start falls to `distantPast`, below `dayStart`.
        let inDay = #Predicate<ScheduleBlockRecord> { block in
            (block.startAt ?? distantPast) >= dayStart && (block.startAt ?? distantPast) < dayEnd
        }
        let todaysBlocks = try context.fetch(FetchDescriptor<ScheduleBlockRecord>(predicate: inDay))
        // Untimed or unworkable blocks are not Now's concern.
        let blocks = todaysBlocks.compactMap { block -> NowBlock? in
            guard let start = block.startAt else { return nil }
            // `NowBlock.isCurrent` is half-open, so an empty or inverted range never shows.
            if let end = block.endAt, end <= start { return nil }
            guard let item = workableItem(for: block, taskIDs: taskIDs, habitIDs: habitIDs) else { return nil }
            return NowBlock(id: block.id, item: item, start: start, end: block.endAt, createdAt: block.createdAt)
        }

        let open = try WorkSessionTracker.openSession(in: context).flatMap { record -> OpenSession? in
            guard let item = item(task: record.task, habit: record.habit) else { return nil }
            return OpenSession(id: record.id, item: item, session: record.snapshot, blockID: record.scheduleBlock?.id)
        }

        let candidates = workableTasks.map { NowItem.task(id: $0.id, title: $0.title) }
            + workableHabits.map { NowItem.habit(id: $0.id, name: $0.name) }
        return Input(blocks: blocks, openSession: open, startCandidates: candidates)
    }

    private static func taskPrecedes(_ lhs: TaskRecord, _ rhs: TaskRecord) -> Bool {
        let order = lhs.title.localizedStandardCompare(rhs.title)
        if order != .orderedSame { return order == .orderedAscending }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    private static func habitPrecedes(_ lhs: HabitRecord, _ rhs: HabitRecord) -> Bool {
        if lhs.sortOrder != rhs.sortOrder { return lhs.sortOrder < rhs.sortOrder }
        if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    private func isWorkable(_ habit: HabitRecord, on day: Date) -> Bool {
        guard habit.archivedAt == nil else { return false }
        if case .negative = habit.type { return false }
        let snapshot = habit.snapshot
        let completions = (habit.completions ?? []).compactMap(\.snapshot)
        // Same listing rule as Today: not before the habit's first day (#104).
        guard snapshot.isListed(on: day, completions: completions, calendar: boundary.calendar) else { return false }
        return evaluator.isOutstanding(habit: snapshot, on: day, completions: completions)
    }

    private func workableItem(for block: ScheduleBlockRecord, taskIDs: Set<UUID>, habitIDs: Set<UUID>) -> NowItem? {
        if let task = block.task, taskIDs.contains(task.id) { return .task(id: task.id, title: task.title) }
        if let habit = block.habit, habitIDs.contains(habit.id) { return .habit(id: habit.id, name: habit.name) }
        return nil
    }

    private func item(task: TaskRecord?, habit: HabitRecord?) -> NowItem? {
        if let task { return .task(id: task.id, title: task.title) }
        if let habit { return .habit(id: habit.id, name: habit.name) }
        return nil
    }
}
