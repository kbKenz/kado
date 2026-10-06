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
        /// task's category or the habit's own icon. Only the block,
        /// session and paused items are filled, which is what the cards show.
        var glyphs: [UUID: ItemGlyph] = [:]
        /// The running item's time today before its current run.
        var runningProgress: NowProgress?
        /// Items worked on today, paused and not done: the last
        /// stopped first. Never the running item.
        var paused: [NowProgress] = []
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

        // A session an earlier version paused is still open: it is shown
        // as paused work, and ends where it paused on the next action.
        let open = try WorkSessionTracker.openSession(in: context).flatMap { record -> OpenSession? in
            guard record.pausedAt == nil, let item = item(task: record.task, habit: record.habit) else { return nil }
            glyphs[item.id] = Self.glyph(for: item, task: record.task, habit: record.habit)
            return OpenSession(id: record.id, item: item, session: record.snapshot, blockID: record.scheduleBlock?.id)
        }

        let progress = try todaysProgress(
            from: dayStart, to: dayEnd, day: day,
            taskIDs: taskIDs, habitIDs: habitIDs, in: context
        )
        let runningProgress = open.map { open in
            progress.byItem[open.item.id] ?? emptyProgress(for: open.item, in: context, day: day)
        }
        for entry in progress.ordered where entry.item.id != open?.item.id {
            glyphs[entry.item.id] = progress.glyphs[entry.item.id]
        }
        let paused = progress.ordered.filter { $0.item.id != open?.item.id }

        // The sorts above settle ties, because `sorted` is stable.
        let recentTasks = workableTasks.map { (item: NowItem.task(id: $0.id, title: $0.title), last: Self.lastActivity(of: $0)) }
        let recentHabits = workableHabits.map { (item: NowItem.habit(id: $0.id, name: $0.name), last: Self.lastActivity(of: $0)) }
        let candidates = (recentTasks + recentHabits).sorted { $0.last > $1.last }.map(\.item)
        return Input(
            blocks: blocks, openSession: open, startCandidates: candidates, glyphs: glyphs,
            runningProgress: runningProgress, paused: paused
        )
    }

    private struct TodaysRuns {
        var byItem: [UUID: NowProgress] = [:]
        /// Last stopped first.
        var ordered: [NowProgress] = []
        var glyphs: [UUID: ItemGlyph] = [:]
    }

    /// Every workable item not done for the day with a finished run
    /// that started in the logical day `[dayStart, dayEnd)`, with that
    /// day's runs.
    private func todaysProgress(
        from dayStart: Date, to dayEnd: Date, day: Date,
        taskIDs: Set<UUID>, habitIDs: Set<UUID>, in context: ModelContext
    ) throws -> TodaysRuns {
        let inDay = #Predicate<WorkSessionRecord> { $0.startedAt >= dayStart && $0.startedAt < dayEnd }
        let records = try context.fetch(FetchDescriptor<WorkSessionRecord>(
            predicate: inDay, sortBy: [SortDescriptor(\.startedAt)]
        ))
        var runs: [UUID: [DateInterval]] = [:]
        var worked: [UUID: TimeInterval] = [:]
        var owners: [UUID: (task: TaskRecord?, habit: HabitRecord?)] = [:]
        for record in records {
            // A running session is the card's; a paused one from an
            // earlier version counts up to its pause.
            guard let stop = record.endedAt ?? record.pausedAt else { continue }
            let id: UUID
            if let task = record.task {
                guard taskIDs.contains(task.id) else { continue }
                id = task.id
                owners[id] = (task, nil)
            } else if let habit = record.habit {
                guard habitIDs.contains(habit.id) else { continue }
                id = habit.id
                owners[id] = (nil, habit)
            } else {
                continue
            }
            runs[id, default: []].append(DateInterval(start: record.startedAt, end: max(stop, record.startedAt)))
            worked[id, default: 0] += record.snapshot.elapsed(at: stop)
        }

        var result = TodaysRuns()
        for (id, itemRuns) in runs {
            guard let owner = owners[id] else { continue }
            let progress: NowProgress
            if let task = owner.task {
                progress = NowProgress(item: .task(id: id, title: task.title), runs: itemRuns, countedSeconds: worked[id] ?? 0)
                result.glyphs[id] = Self.glyph(for: progress.item, task: task, habit: nil)
            } else if let habit = owner.habit {
                // Done for the day (a timer at its target too): nothing left to continue.
                let snapshot = habit.snapshot
                let state = HabitRowState.resolve(
                    habit: snapshot, completions: (habit.completions ?? []).compactMap(\.snapshot),
                    calendar: boundary.calendar, asOf: day
                )
                if state.isDone(for: snapshot) { continue }
                progress = habitProgress(habit, runs: itemRuns, worked: worked[id] ?? 0, day: day)
                result.glyphs[id] = Self.glyph(for: progress.item, task: nil, habit: habit)
            } else {
                continue
            }
            result.byItem[id] = progress
        }
        result.ordered = result.byItem.values.sorted {
            ($0.lastStoppedAt ?? .distantPast, $0.id.uuidString) > ($1.lastStoppedAt ?? .distantPast, $1.id.uuidString)
        }
        return result
    }

    /// A timer habit counts what is logged for the day (manual logs
    /// too) against its target; other habits count their runs.
    private func habitProgress(_ habit: HabitRecord, runs: [DateInterval], worked: TimeInterval, day: Date) -> NowProgress {
        let item = NowItem.habit(id: habit.id, name: habit.name)
        guard case .timer(let target) = habit.type else {
            return NowProgress(item: item, runs: runs, countedSeconds: worked)
        }
        // Completions are stamped on the civil day equal to the logical day.
        let logged = (habit.completions ?? [])
            .filter { boundary.calendar.isDate($0.date, inSameDayAs: day) }
            .reduce(0) { $0 + $1.value }
        return NowProgress(item: item, runs: runs, countedSeconds: logged, targetSeconds: target, canMarkDone: false)
    }

    /// The running item's progress when it has no finished run today.
    private func emptyProgress(for item: NowItem, in context: ModelContext, day: Date) -> NowProgress {
        guard case .habit(let id, _) = item,
              let habit = try? context.fetch(FetchDescriptor<HabitRecord>(predicate: #Predicate { $0.id == id })).first
        else { return NowProgress(item: item, runs: [], countedSeconds: 0) }
        return habitProgress(habit, runs: [], worked: 0, day: day)
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
        // The snapshot's type, rather than a second decode of the record's.
        let snapshot = habit.snapshot
        if case .negative = snapshot.type { return false }
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
