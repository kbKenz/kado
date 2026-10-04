import Foundation
import SwiftData
import Testing
@testable import Kado
import KadoCore

@Suite("NowInputBuilder")
@MainActor
struct NowInputBuilderTests {
    private let calendar = TestCalendar.utc
    private var now: Date { TestCalendar.instant(calendar, 2026, 4, 13, 10) }

    private func context() throws -> ModelContext {
        let schema = Schema(versionedSchema: KadoSchemaV8.self)
        return ModelContext(try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)))
    }

    private var builder: NowInputBuilder {
        NowInputBuilder(boundary: DayBoundary(calendar: calendar, startHour: 0), evaluator: DefaultFrequencyEvaluator(calendar: calendar))
    }

    @Test("Done, archived and cancelled tasks, archived and negative habits and untimed blocks are skipped")
    func skipsUnworkable() throws {
        let context = try context()
        let old = now.addingTimeInterval(-86_400 * 3)
        let open = TaskRecord(title: "Open")
        let done = TaskRecord(title: "Done", completedAt: now)
        let archivedTask = TaskRecord(title: "Archived task", archivedAt: now)
        let cancelled = TaskRecord(title: "Cancelled", externalCancelledAt: now)
        let negative = HabitRecord(name: "No sugar", type: .negative, createdAt: old)
        let archivedHabit = HabitRecord(name: "Archived habit", createdAt: old, archivedAt: now)
        [open, done, archivedTask, cancelled].forEach(context.insert)
        [negative, archivedHabit].forEach(context.insert)
        for task in [open, done, archivedTask, cancelled] {
            context.insert(ScheduleBlockRecord(plannedDay: now, startAt: now, task: task))
        }
        for habit in [negative, archivedHabit] {
            context.insert(ScheduleBlockRecord(plannedDay: now, startAt: now, habit: habit))
        }
        context.insert(ScheduleBlockRecord(plannedDay: now, task: open))
        try context.save()

        let input = try builder.build(now: now, in: context)
        #expect(input.blocks.map(\.item.title) == ["Open"])
    }

    @Test("A habit not due today is excluded from blocks and candidates")
    func notDueToday() throws {
        let context = try context()
        // 2026-04-13 is a Monday.
        let tuesdays = HabitRecord(name: "Tuesdays", frequency: .specificDays([.tuesday]), createdAt: now.addingTimeInterval(-86_400 * 10))
        context.insert(tuesdays)
        context.insert(ScheduleBlockRecord(plannedDay: now, startAt: now, habit: tuesdays))
        try context.save()

        let input = try builder.build(now: now, in: context)
        #expect(input.blocks.isEmpty)
        #expect(input.startCandidates.isEmpty)
    }

    @Test("A block whose end is not after its start is skipped")
    func skipsEmptyRange() throws {
        let context = try context()
        let task = TaskRecord(title: "Open")
        context.insert(task)
        let empty = ScheduleBlockRecord(plannedDay: now, startAt: now, endAt: now, task: task)
        let inverted = ScheduleBlockRecord(plannedDay: now, startAt: now, endAt: now.addingTimeInterval(-60), task: task)
        let ok = ScheduleBlockRecord(plannedDay: now, startAt: now, endAt: now.addingTimeInterval(60), task: task)
        let openEnded = ScheduleBlockRecord(plannedDay: now, startAt: now, task: task)
        [empty, inverted, ok, openEnded].forEach(context.insert)
        try context.save()

        let input = try builder.build(now: now, in: context)
        #expect(Set(input.blocks.map(\.id)) == [ok.id, openEnded.id])
    }

    @Test("Only blocks starting in the logical day are read")
    func logicalDayWindow() throws {
        let context = try context()
        let task = TaskRecord(title: "Open")
        context.insert(task)
        func block(_ day: Int, _ hour: Int, _ minute: Int) -> ScheduleBlockRecord {
            ScheduleBlockRecord(plannedDay: now, startAt: TestCalendar.instant(calendar, 2026, 4, day, hour, minute), task: task)
        }
        let beforeStart = block(13, 3, 59)
        let atStart = block(13, 4, 0)
        let beforeEnd = block(14, 3, 59)
        let atEnd = block(14, 4, 0)
        [beforeStart, atStart, beforeEnd, atEnd].forEach(context.insert)
        try context.save()

        // 02:00 on the 14th with a 4 AM day start is still the 13th: the window is 13th 04:00 up to, not including, 14th 04:00.
        let early = TestCalendar.instant(calendar, 2026, 4, 14, 2)
        let shifted = NowInputBuilder(boundary: DayBoundary(calendar: calendar, startHour: 4), evaluator: DefaultFrequencyEvaluator(calendar: calendar))
        let input = try shifted.build(now: early, in: context)
        #expect(Set(input.blocks.map(\.id)) == [atStart.id, beforeEnd.id])
    }

    @Test("A block on another day is not read")
    func otherDayExcluded() throws {
        let context = try context()
        let task = TaskRecord(title: "Open")
        context.insert(task)
        context.insert(ScheduleBlockRecord(plannedDay: now, startAt: now.addingTimeInterval(86_400), task: task))
        context.insert(ScheduleBlockRecord(plannedDay: now, startAt: now.addingTimeInterval(-86_400), task: task))
        try context.save()

        #expect(try builder.build(now: now, in: context).blocks.isEmpty)
    }

    @Test("The open session carries its item and block")
    func openSession() throws {
        let context = try context()
        let task = TaskRecord(title: "Research")
        context.insert(task)
        let block = ScheduleBlockRecord(plannedDay: now, startAt: now, task: task)
        context.insert(block)
        context.insert(WorkSessionRecord(startedAt: now, task: task, scheduleBlock: block))
        try context.save()

        let input = try builder.build(now: now, in: context)
        #expect(input.openSession?.item == .task(id: task.id, title: "Research"))
        #expect(input.openSession?.blockID == block.id)
    }

    @Test("The open session on a habit maps to a habit item")
    func openHabitSession() throws {
        let context = try context()
        let habit = HabitRecord(name: "Read", createdAt: now.addingTimeInterval(-86_400 * 3))
        context.insert(habit)
        context.insert(WorkSessionRecord(startedAt: now, habit: habit))
        try context.save()

        let input = try builder.build(now: now, in: context)
        #expect(input.openSession?.item == .habit(id: habit.id, name: "Read"))
        #expect(input.openSession?.blockID == nil)
    }

    @Test("Ties in recent activity sort task titles case-insensitively")
    func titleOrder() throws {
        let context = try context()
        let edited = now.addingTimeInterval(-3_600)
        ["banana", "Apple", "cherry"].forEach { context.insert(TaskRecord(title: $0, updatedAt: edited)) }
        try context.save()
        let input = try builder.build(now: now, in: context)
        #expect(input.startCandidates.map(\.title) == ["Apple", "banana", "cherry"])
    }

    @Test("Start candidates: most recent activity first, tasks and habits mixed")
    func candidatesByRecentActivity() throws {
        let context = try context()
        let hour: TimeInterval = 3_600
        let old = TaskRecord(title: "Old", updatedAt: now.addingTimeInterval(-30 * hour))
        let worked = TaskRecord(title: "Worked", updatedAt: now.addingTimeInterval(-40 * hour))
        let habit = HabitRecord(name: "Read", createdAt: now.addingTimeInterval(-72 * hour))
        let logged = HabitRecord(name: "Logged", createdAt: now.addingTimeInterval(-72 * hour))
        [old, worked].forEach(context.insert)
        [habit, logged].forEach(context.insert)
        // A session two hours ago, a log yesterday: both count as activity.
        context.insert(WorkSessionRecord(startedAt: now.addingTimeInterval(-2 * hour), endedAt: now.addingTimeInterval(-hour), task: worked))
        context.insert(CompletionRecord(date: now.addingTimeInterval(-20 * hour), habit: logged))
        try context.save()
        let input = try builder.build(now: now, in: context)
        #expect(input.startCandidates.map(\.title) == ["Worked", "Logged", "Old", "Read"])
    }

    @Test("A habit created after today is not workable")
    func futureHabitSkipped() throws {
        let context = try context()
        context.insert(HabitRecord(name: "Later", createdAt: now.addingTimeInterval(86_400 * 3)))
        try context.save()
        let input = try builder.build(now: now, in: context)
        #expect(input.startCandidates.isEmpty)
    }
}
