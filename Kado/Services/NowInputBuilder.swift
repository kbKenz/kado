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
        /// Most recent activity first: a Now session, a habit log, or an edit.
        var startCandidates: [NowItem]
        /// The icon beside each title on the cards, by item id: the
        /// task's category or the habit's own icon. Only the block and
        /// session items are filled, which is what the cards show.
        var glyphs: [UUID: ItemGlyph] = [:]
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

        // A typed nil: three inline `== nil` checks time out the #Predicate type-checker.
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
        var glyphs: [UUID: ItemGlyph] = [:]
        // Untimed or unworkable blocks are not Now's concern.
        let blocks = todaysBlocks.compactMap { block -> NowBlock? in
            guard let start = block.startAt else { return nil }
            // `NowBlock.isCurrent` is half-open, so an empty or inverted range never shows.
            if let end = block.endAt, end <= start { return nil }
            guard let item = workableItem(for: block, taskIDs: taskIDs, habitIDs: habitIDs) else { return nil }
            glyphs[item.id] = Self.glyph(for: item, task: block.task, habit: block.habit)
            return NowBlock(id: block.id, item: item, start: start, end: block.endAt, createdAt: block.createdAt)
        }

        let open = try WorkSessionTracker.openSession(in: context).flatMap { record -> OpenSession? in
            guard let item = item(task: record.task, habit: record.habit) else { return nil }
            glyphs[item.id] = Self.glyph(for: item, task: record.task, habit: record.habit)
            return OpenSession(id: record.id, item: item, session: record.snapshot, blockID: record.scheduleBlock?.id)
        }

        // The sorts above settle ties, because `sorted` is stable.
        let recentTasks = workableTasks.map { (item: NowItem.task(id: $0.id, title: $0.title), last: Self.lastActivity(of: $0)) }
        let recentHabits = workableHabits.map { (item: NowItem.habit(id: $0.id, name: $0.name), last: Self.lastActivity(of: $0)) }
        let candidates = (recentTasks + recentHabits).sorted { $0.last > $1.last }.map(\.item)
        return Input(blocks: blocks, openSession: open, startCandidates: candidates, glyphs: glyphs)
    }

    /// A task's category, resolved as Insights does, or a habit's own
    /// icon (habits keep their icon).
    private static func glyph(for item: NowItem, task: TaskRecord?, habit: HabitRecord?) -> ItemGlyph? {
        switch item {
        case .task:
            guard let task else { return nil }
            return ItemGlyph(category: CategoryResolver.resolve(
                stored: task.category, goalCategory: task.goal?.category, title: task.title
            ))
        case .habit:
            guard let habit else { return nil }
            return ItemGlyph(habitIcon: habit.icon, color: habit.color)
        }
    }

    private static func lastActivity(of task: TaskRecord) -> Date {
        let sessions = (task.workSessions ?? []).map(\.startedAt)
        return ([task.updatedAt] + sessions).max() ?? task.updatedAt
    }

    private static func lastActivity(of habit: HabitRecord) -> Date {
        let sessions = (habit.workSessions ?? []).map(\.startedAt)
        let logs = (habit.completions ?? []).map(\.date)
        return ([habit.createdAt] + sessions + logs).max() ?? habit.createdAt
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
