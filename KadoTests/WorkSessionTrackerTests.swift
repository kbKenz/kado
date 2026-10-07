import Foundation
import SwiftData
import Testing
@testable import Kado
import KadoCore

@Suite("WorkSessionTracker")
@MainActor
struct WorkSessionTrackerTests {
    private let calendar = TestCalendar.utc
    private var start: Date { TestCalendar.instant(calendar, 2026, 4, 13, 10, 17) }

    /// Held for the test's lifetime: a `ModelContext` does not retain its container.
    private let container: ModelContainer

    init() throws {
        let schema = Schema(versionedSchema: KadoSchemaV10.self)
        container = try ModelContainer(for: schema, configurations: ModelConfiguration(UUID().uuidString, schema: schema, isStoredInMemoryOnly: true))
    }

    /// A context of its own with autosave off, not `mainContext`: the
    /// main context's autosave timer can fire after the test frees the
    /// container, which traps the whole test host.
    private func context() throws -> ModelContext {
        let context = ModelContext(container)
        context.autosaveEnabled = false
        return context
    }

    private func tracker(now: Date, startHour: Int = 0) -> WorkSessionTracker {
        WorkSessionTracker(boundary: DayBoundary(calendar: calendar, startHour: startHour), now: { now })
    }

    private func sessions(_ context: ModelContext) throws -> [WorkSessionRecord] {
        try context.fetch(FetchDescriptor<WorkSessionRecord>(sortBy: [SortDescriptor(\.startedAt)]))
    }

    @Test("Starting what already runs does nothing")
    func startRunningIsNoOp() throws {
        let context = try context()
        let task = TaskRecord(title: "Research")
        context.insert(task)
        try tracker(now: start).start(task: task, block: nil, in: context)
        try tracker(now: start.addingTimeInterval(60)).start(task: task, block: nil, in: context)
        let all = try sessions(context)
        #expect(all.count == 1)
        #expect(all.first?.startedAt == start)
        #expect(all.first?.endedAt == nil)
    }

    @Test("Pause ends the run, continue starts a new one: each run is logged")
    func pauseAndContinueLogRuns() throws {
        let context = try context()
        let task = TaskRecord(title: "IELTS prep")
        context.insert(task)
        try tracker(now: start).start(task: task, block: nil, in: context)
        try tracker(now: start.addingTimeInterval(7200)).pause(in: context)
        #expect(try WorkSessionTracker.openSession(in: context) == nil)
        try tracker(now: start.addingTimeInterval(21_600)).start(task: task, block: nil, in: context)
        try tracker(now: start.addingTimeInterval(28_800)).pause(in: context)

        let runs = try sessions(context)
        #expect(runs.map(\.startedAt) == [start, start.addingTimeInterval(21_600)])
        #expect(runs.map(\.endedAt) == [start.addingTimeInterval(7200), start.addingTimeInterval(28_800)])
        #expect(runs.allSatisfy { $0.pausedAt == nil && $0.pausedSeconds == 0 })
        #expect(task.completedAt == nil)
    }

    @Test("Starting another item pauses the running one in the same save")
    func startSwitches() throws {
        let context = try context()
        let first = TaskRecord(title: "IELTS prep")
        let second = TaskRecord(title: "Report")
        let habit = HabitRecord(name: "Read", type: .binary)
        context.insert(first)
        context.insert(second)
        context.insert(habit)
        try tracker(now: start).start(task: first, block: nil, in: context)
        try tracker(now: start.addingTimeInterval(600)).start(task: second, block: nil, in: context)
        try tracker(now: start.addingTimeInterval(900)).start(habit: habit, block: nil, in: context)

        let runs = try sessions(context)
        #expect(runs.count == 3)
        #expect(runs[0].task?.id == first.id && runs[0].endedAt == start.addingTimeInterval(600))
        #expect(runs[1].task?.id == second.id && runs[1].endedAt == start.addingTimeInterval(900))
        #expect(runs[2].habit?.id == habit.id && runs[2].endedAt == nil)
        #expect(first.completedAt == nil && second.completedAt == nil)
        #expect(try WorkSessionTracker.openSession(in: context)?.id == runs[2].id)
    }

    @Test("Complete marks a running task done and ends its run")
    func completeRunningTask() throws {
        let context = try context()
        let task = TaskRecord(title: "Research")
        context.insert(task)
        try tracker(now: start).start(task: task, block: nil, in: context)
        let end = start.addingTimeInterval(1800)
        try tracker(now: end).complete(task: task, in: context)
        #expect(task.completedAt == end)
        #expect(task.workSessions?.first?.endedAt == end)
        #expect(try WorkSessionTracker.openSession(in: context) == nil)
    }

    @Test("Complete on a paused task leaves the running item alone")
    func completePausedTask() throws {
        let context = try context()
        let paused = TaskRecord(title: "IELTS prep")
        let running = TaskRecord(title: "Report")
        context.insert(paused)
        context.insert(running)
        try tracker(now: start).start(task: paused, block: nil, in: context)
        try tracker(now: start.addingTimeInterval(600)).start(task: running, block: nil, in: context)
        let end = start.addingTimeInterval(1200)
        try tracker(now: end).complete(task: paused, in: context)
        #expect(paused.completedAt == end)
        #expect(running.completedAt == nil)
        #expect(try WorkSessionTracker.openSession(in: context)?.task?.id == running.id)
    }

    @Test("Complete logs a habit by its type", arguments: [
        (HabitType.binary, 0.0, 1.0),
        (HabitType.counter(target: 8), 2.0, 3.0),
        (HabitType.timer(targetSeconds: 3600), 600.0, 2400.0),
    ])
    func completeHabit(type: HabitType, existing: Double, expected: Double) throws {
        let context = try context()
        let habit = HabitRecord(name: "Read", type: type)
        context.insert(habit)
        if existing > 0 {
            context.insert(CompletionRecord(date: start, value: existing, habit: habit))
        }
        try tracker(now: start).start(habit: habit, block: nil, in: context)
        try tracker(now: start.addingTimeInterval(1800)).complete(habit: habit, in: context)
        #expect(habit.completions?.count == 1)
        #expect(habit.completions?.first?.value == expected)
    }

    @Test("Each run of a timer habit adds its time when it ends")
    func timerRunsAddUp() throws {
        let context = try context()
        let habit = HabitRecord(name: "IELTS", type: .timer(targetSeconds: 14_400))
        let task = TaskRecord(title: "Report")
        context.insert(habit)
        context.insert(task)
        try tracker(now: start).start(habit: habit, block: nil, in: context)
        try tracker(now: start.addingTimeInterval(3600)).pause(in: context)
        #expect(habit.completions?.first?.value == 3600.0)
        try tracker(now: start.addingTimeInterval(7200)).start(habit: habit, block: nil, in: context)
        // Switching away counts as a pause.
        try tracker(now: start.addingTimeInterval(9000)).start(task: task, block: nil, in: context)
        #expect(habit.completions?.count == 1)
        #expect(habit.completions?.first?.value == 5400.0)
    }

    @Test("Pausing a counter or binary habit logs nothing")
    func pauseHabitLogsNothing() throws {
        let context = try context()
        let habit = HabitRecord(name: "Read", type: .binary)
        context.insert(habit)
        try tracker(now: start).start(habit: habit, block: nil, in: context)
        try tracker(now: start.addingTimeInterval(60)).pause(in: context)
        #expect(habit.completions?.isEmpty ?? true)
    }

    @Test("A run started before the rollover logs on the previous logical day")
    func completeHabitBeforeRollover() throws {
        let context = try context()
        let habit = HabitRecord(name: "Read", type: .counter(target: 8))
        context.insert(habit)
        let stamped = TestCalendar.instant(calendar, 2026, 4, 13, 22, 0)
        context.insert(CompletionRecord(date: stamped, value: 2, habit: habit))
        let began = TestCalendar.instant(calendar, 2026, 4, 14, 2, 0)
        try tracker(now: began, startHour: 4).start(habit: habit, block: nil, in: context)
        try tracker(now: began.addingTimeInterval(1800), startHour: 4).complete(habit: habit, in: context)
        #expect(habit.completions?.count == 1)
        #expect(habit.completions?.first?.value == 3.0)

        let other = HabitRecord(name: "Write", type: .timer(targetSeconds: 3600))
        context.insert(other)
        try tracker(now: began, startHour: 4).start(habit: other, block: nil, in: context)
        try tracker(now: began.addingTimeInterval(1800), startHour: 4).pause(in: context)
        let date = try #require(other.completions?.first?.date)
        #expect(calendar.component(.day, from: date) == 13)
    }

    @Test("A session paused by an earlier version ends where it paused")
    func legacyPausedSessionEndsAtPause() throws {
        let context = try context()
        let habit = HabitRecord(name: "IELTS", type: .timer(targetSeconds: 14_400))
        let task = TaskRecord(title: "Report")
        context.insert(habit)
        context.insert(task)
        let legacy = WorkSessionRecord(startedAt: start, pausedAt: start.addingTimeInterval(1800), pausedSeconds: 600, habit: habit)
        context.insert(legacy)
        try context.save()

        try tracker(now: start.addingTimeInterval(7200)).start(task: task, block: nil, in: context)
        #expect(legacy.endedAt == start.addingTimeInterval(1800))
        #expect(legacy.pausedAt == nil)
        #expect(habit.completions?.first?.value == 1200.0)
    }

    @Test("Continuing a legacy paused session starts a new run")
    func continueLegacyPaused() throws {
        let context = try context()
        let task = TaskRecord(title: "Report")
        context.insert(task)
        let legacy = WorkSessionRecord(startedAt: start, pausedAt: start.addingTimeInterval(1800), task: task)
        context.insert(legacy)
        try context.save()
        try tracker(now: start.addingTimeInterval(3600)).start(task: task, block: nil, in: context)
        #expect(legacy.endedAt == start.addingTimeInterval(1800))
        #expect(try WorkSessionTracker.openSession(in: context)?.startedAt == start.addingTimeInterval(3600))
    }

    @Test("Cancel deletes the open session")
    func cancel() throws {
        let context = try context()
        let task = TaskRecord(title: "Research")
        context.insert(task)
        try tracker(now: start).start(task: task, block: nil, in: context)
        try tracker(now: start).cancel(in: context)
        #expect(try context.fetchCount(FetchDescriptor<WorkSessionRecord>()) == 0)
    }

    @Test("With two open sessions from sync, the earlier one is the open session")
    func earliestOpenWins() throws {
        let context = try context()
        let early = WorkSessionRecord(startedAt: start)
        let late = WorkSessionRecord(startedAt: start.addingTimeInterval(60))
        context.insert(late)
        context.insert(early)
        try context.save()
        #expect(try WorkSessionTracker.openSession(in: context)?.id == early.id)
    }

    @Test("Starting ends every open session sync brought in")
    func startEndsAllOpen() throws {
        let context = try context()
        let task = TaskRecord(title: "Research")
        context.insert(task)
        context.insert(WorkSessionRecord(startedAt: start))
        context.insert(WorkSessionRecord(startedAt: start.addingTimeInterval(60)))
        try context.save()
        try tracker(now: start.addingTimeInterval(600)).start(task: task, block: nil, in: context)
        let open = try context.fetch(FetchDescriptor<WorkSessionRecord>(predicate: #Predicate { $0.endedAt == nil }))
        #expect(open.count == 1)
        #expect(open.first?.task?.id == task.id)
    }

    @Test("Pause and cancel need an open session")
    func noOpenSession() throws {
        let context = try context()
        let tracker = tracker(now: start)
        #expect(throws: WorkSessionTracker.TrackerError.noOpenSession) { try tracker.pause(in: context) }
        #expect(throws: WorkSessionTracker.TrackerError.noOpenSession) { try tracker.cancel(in: context) }
    }

    @Test("A binary habit with a noted zero completion becomes 1 and keeps the note")
    func binaryKeepsNote() throws {
        let context = try context()
        let habit = HabitRecord(name: "Read", type: .binary)
        context.insert(habit)
        context.insert(CompletionRecord(date: start, value: 0, note: "felt slow", habit: habit))
        try tracker(now: start).start(habit: habit, block: nil, in: context)
        try tracker(now: start.addingTimeInterval(60)).complete(habit: habit, in: context)
        #expect(habit.completions?.count == 1)
        #expect(habit.completions?.first?.value == 1.0)
        #expect(habit.completions?.first?.note == "felt slow")
    }

    @Test("A timer habit with no worked time logs nothing")
    func timerZeroSeconds() throws {
        let context = try context()
        let habit = HabitRecord(name: "Read", type: .timer(targetSeconds: 3600))
        context.insert(habit)
        try tracker(now: start).start(habit: habit, block: nil, in: context)
        try tracker(now: start).pause(in: context)
        #expect(habit.completions?.isEmpty ?? true)
    }

    @Test("Completing keeps a completion date the task already has")
    func taskAlreadyCompleted() throws {
        let context = try context()
        let task = TaskRecord(title: "Research")
        context.insert(task)
        let earlier = start.addingTimeInterval(-86_400)
        task.completedAt = earlier
        try tracker(now: start).start(task: task, block: nil, in: context)
        try tracker(now: start.addingTimeInterval(60)).complete(task: task, in: context)
        #expect(task.completedAt == earlier)
    }
}
