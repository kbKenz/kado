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
        let schema = Schema(versionedSchema: KadoSchemaV9.self)
        container = try ModelContainer(for: schema, configurations: ModelConfiguration(UUID().uuidString, schema: schema, isStoredInMemoryOnly: true))
    }

    private func context() throws -> ModelContext {
        container.mainContext
    }

    private func tracker(now: Date, startHour: Int = 0) -> WorkSessionTracker {
        WorkSessionTracker(boundary: DayBoundary(calendar: calendar, startHour: startHour), now: { now })
    }

    @Test("Only one session can be open")
    func oneOpenSession() throws {
        let context = try context()
        let task = TaskRecord(title: "Research")
        context.insert(task)
        try tracker(now: start).start(task: task, block: nil, in: context)
        #expect(throws: WorkSessionTracker.TrackerError.sessionAlreadyOpen) {
            try tracker(now: start).start(task: task, block: nil, in: context)
        }
        #expect(try context.fetchCount(FetchDescriptor<WorkSessionRecord>()) == 1)
    }

    @Test("Pause and resume add up the paused time")
    func pauseResume() throws {
        let context = try context()
        let task = TaskRecord(title: "Research")
        context.insert(task)
        try tracker(now: start).start(task: task, block: nil, in: context)
        try tracker(now: start.addingTimeInterval(600)).pause(in: context)
        let paused = try #require(try WorkSessionTracker.openSession(in: context))
        #expect(paused.pausedAt == start.addingTimeInterval(600))
        try tracker(now: start.addingTimeInterval(900)).resume(in: context)
        #expect(paused.pausedAt == nil)
        #expect(paused.pausedSeconds == 300.0)
    }

    @Test("Finish without done keeps the task open and closes the pause")
    func finishNotYet() throws {
        let context = try context()
        let task = TaskRecord(title: "Research")
        context.insert(task)
        try tracker(now: start).start(task: task, block: nil, in: context)
        try tracker(now: start.addingTimeInterval(600)).pause(in: context)
        try tracker(now: start.addingTimeInterval(900)).finish(markDone: false, in: context)
        let session = try #require(task.workSessions?.first)
        #expect(session.endedAt == start.addingTimeInterval(900))
        #expect(session.pausedAt == nil)
        #expect(session.pausedSeconds == 300.0)
        #expect(task.completedAt == nil)
        #expect(try WorkSessionTracker.openSession(in: context) == nil)
    }

    @Test("Finish as done completes the task")
    func finishDoneTask() throws {
        let context = try context()
        let task = TaskRecord(title: "Research")
        context.insert(task)
        try tracker(now: start).start(task: task, block: nil, in: context)
        let end = start.addingTimeInterval(1800)
        try tracker(now: end).finish(markDone: true, in: context)
        #expect(task.completedAt == end)
    }

    @Test("Finish as done logs a habit by its type", arguments: [
        (HabitType.binary, 0.0, 1.0),
        (HabitType.counter(target: 8), 2.0, 3.0),
        (HabitType.timer(targetSeconds: 3600), 600.0, 2400.0),
    ])
    func finishDoneHabit(type: HabitType, existing: Double, expected: Double) throws {
        let context = try context()
        let habit = HabitRecord(name: "Read", type: type)
        context.insert(habit)
        if existing > 0 {
            context.insert(CompletionRecord(date: start, value: existing, habit: habit))
        }
        try tracker(now: start).start(habit: habit, block: nil, in: context)
        try tracker(now: start.addingTimeInterval(1800)).finish(markDone: true, in: context)
        #expect(habit.completions?.count == 1)
        #expect(habit.completions?.first?.value == expected)
    }

    @Test("A session started before the rollover logs on the previous logical day")
    func finishDoneHabitBeforeRollover() throws {
        let context = try context()
        let habit = HabitRecord(name: "Read", type: .counter(target: 8))
        context.insert(habit)
        let stamped = TestCalendar.instant(calendar, 2026, 4, 13, 22, 0)
        context.insert(CompletionRecord(date: stamped, value: 2, habit: habit))
        let began = TestCalendar.instant(calendar, 2026, 4, 14, 2, 0)
        try tracker(now: began, startHour: 4).start(habit: habit, block: nil, in: context)
        try tracker(now: began.addingTimeInterval(1800), startHour: 4).finish(markDone: true, in: context)
        #expect(habit.completions?.count == 1)
        #expect(habit.completions?.first?.value == 3.0)

        let other = HabitRecord(name: "Write", type: .binary)
        context.insert(other)
        try tracker(now: began, startHour: 4).start(habit: other, block: nil, in: context)
        try tracker(now: began.addingTimeInterval(1800), startHour: 4).finish(markDone: true, in: context)
        let date = try #require(other.completions?.first?.date)
        #expect(calendar.component(.day, from: date) == 13)
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

    @Test("Pause, resume, finish and cancel need an open session")
    func noOpenSession() throws {
        let context = try context()
        let tracker = tracker(now: start)
        #expect(throws: WorkSessionTracker.TrackerError.noOpenSession) { try tracker.pause(in: context) }
        #expect(throws: WorkSessionTracker.TrackerError.noOpenSession) { try tracker.resume(in: context) }
        #expect(throws: WorkSessionTracker.TrackerError.noOpenSession) { try tracker.finish(markDone: true, in: context) }
        #expect(throws: WorkSessionTracker.TrackerError.noOpenSession) { try tracker.cancel(in: context) }
    }

    @Test("Pausing twice keeps the first pause")
    func pauseTwice() throws {
        let context = try context()
        let task = TaskRecord(title: "Research")
        context.insert(task)
        try tracker(now: start).start(task: task, block: nil, in: context)
        try tracker(now: start.addingTimeInterval(600)).pause(in: context)
        try tracker(now: start.addingTimeInterval(700)).pause(in: context)
        let session = try #require(try WorkSessionTracker.openSession(in: context))
        #expect(session.pausedAt == start.addingTimeInterval(600))
    }

    @Test("A binary habit with a noted zero completion becomes 1 and keeps the note")
    func binaryKeepsNote() throws {
        let context = try context()
        let habit = HabitRecord(name: "Read", type: .binary)
        context.insert(habit)
        context.insert(CompletionRecord(date: start, value: 0, note: "felt slow", habit: habit))
        try tracker(now: start).start(habit: habit, block: nil, in: context)
        try tracker(now: start.addingTimeInterval(60)).finish(markDone: true, in: context)
        #expect(habit.completions?.count == 1)
        #expect(habit.completions?.first?.value == 1.0)
        #expect(habit.completions?.first?.note == "felt slow")
    }

    @Test("Finishing a habit session without done logs nothing")
    func habitNotDone() throws {
        let context = try context()
        let habit = HabitRecord(name: "Read", type: .binary)
        context.insert(habit)
        try tracker(now: start).start(habit: habit, block: nil, in: context)
        try tracker(now: start.addingTimeInterval(60)).finish(markDone: false, in: context)
        #expect(habit.completions?.isEmpty ?? true)
    }

    @Test("A timer habit with no worked time logs nothing")
    func timerZeroSeconds() throws {
        let context = try context()
        let habit = HabitRecord(name: "Read", type: .timer(targetSeconds: 3600))
        context.insert(habit)
        try tracker(now: start).start(habit: habit, block: nil, in: context)
        try tracker(now: start).finish(markDone: true, in: context)
        #expect(habit.completions?.isEmpty ?? true)
    }

    @Test("Finishing as done keeps a completion date the task already has")
    func taskAlreadyCompleted() throws {
        let context = try context()
        let task = TaskRecord(title: "Research")
        context.insert(task)
        let earlier = start.addingTimeInterval(-86_400)
        task.completedAt = earlier
        try tracker(now: start).start(task: task, block: nil, in: context)
        try tracker(now: start.addingTimeInterval(60)).finish(markDone: true, in: context)
        #expect(task.completedAt == earlier)
    }
}
