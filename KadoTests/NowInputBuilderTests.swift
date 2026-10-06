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
        let schema = Schema(versionedSchema: KadoSchemaV9.self)
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

    @Test("Block items carry their icon: the task's category as Insights resolves it, or the habit's own icon")
    func blockGlyphs() throws {
        let context = try context()
        let goal = GoalRecord(name: "Save for a house", category: .money)
        // Alone, the title reads as People: the goal's category wins.
        let linked = TaskRecord(title: "Call grandma", goal: goal)
        let stored = TaskRecord(title: "Revise chemistry", category: .work)
        let guessed = TaskRecord(title: "Revise chemistry notes")
        let unknown = TaskRecord(title: "Something else")
        let habit = HabitRecord(name: "Read", createdAt: now.addingTimeInterval(-86_400 * 3), color: .purple, icon: "book.fill")
        context.insert(goal)
        [linked, stored, guessed, unknown].forEach(context.insert)
        context.insert(habit)
        for task in [linked, stored, guessed, unknown] {
            context.insert(ScheduleBlockRecord(plannedDay: now, startAt: now, task: task))
        }
        context.insert(ScheduleBlockRecord(plannedDay: now, startAt: now, habit: habit))
        try context.save()

        let input = try builder.build(now: now, in: context)
        #expect(input.glyphs[linked.id] == ItemGlyph(category: .money))
        #expect(input.glyphs[stored.id] == ItemGlyph(category: .work))
        #expect(input.glyphs[guessed.id] == ItemGlyph(category: .study))
        #expect(input.glyphs[unknown.id] == ItemGlyph(category: .other))
        #expect(input.glyphs[habit.id] == ItemGlyph(habitIcon: "book.fill", color: .purple))
    }

    @Test("The open session's item carries its icon without a block today")
    func sessionGlyph() throws {
        let context = try context()
        let task = TaskRecord(title: "Pay the rent")
        context.insert(task)
        context.insert(WorkSessionRecord(startedAt: now, task: task))
        try context.save()

        let input = try builder.build(now: now, in: context)
        #expect(input.glyphs[task.id] == ItemGlyph(category: .money))
    }

    // MARK: - Paused today

    @Test("Items worked on today and paused are listed, last stopped first, with their runs")
    func pausedToday() throws {
        let context = try context()
        let ielts = TaskRecord(title: "IELTS prep")
        let report = TaskRecord(title: "Report")
        [ielts, report].forEach(context.insert)
        let morning = TestCalendar.instant(calendar, 2026, 4, 13, 6)
        context.insert(WorkSessionRecord(startedAt: morning, endedAt: morning.addingTimeInterval(3600), task: ielts))
        context.insert(WorkSessionRecord(startedAt: morning.addingTimeInterval(3600), endedAt: morning.addingTimeInterval(5400), task: report))
        context.insert(WorkSessionRecord(startedAt: morning.addingTimeInterval(5400), endedAt: morning.addingTimeInterval(7200), task: ielts))
        try context.save()

        let input = try builder.build(now: now, in: context)
        #expect(input.openSession == nil)
        #expect(input.paused.map(\.item.title) == ["IELTS prep", "Report"])
        let first = try #require(input.paused.first)
        #expect(first.countedSeconds == 5400.0)
        #expect(first.runs == [
            DateInterval(start: morning, duration: 3600),
            DateInterval(start: morning.addingTimeInterval(5400), duration: 1800),
        ])
        #expect(first.canMarkDone)
        #expect(input.glyphs[ielts.id] != nil)
    }

    @Test("The running item is not in the paused list; its earlier time is its progress")
    func runningItemProgress() throws {
        let context = try context()
        let ielts = TaskRecord(title: "IELTS prep")
        let report = TaskRecord(title: "Report")
        [ielts, report].forEach(context.insert)
        let morning = TestCalendar.instant(calendar, 2026, 4, 13, 6)
        context.insert(WorkSessionRecord(startedAt: morning, endedAt: morning.addingTimeInterval(3600), task: ielts))
        context.insert(WorkSessionRecord(startedAt: morning.addingTimeInterval(3600), endedAt: morning.addingTimeInterval(4200), task: report))
        context.insert(WorkSessionRecord(startedAt: morning.addingTimeInterval(7200), task: ielts))
        try context.save()

        let input = try builder.build(now: now, in: context)
        #expect(input.openSession?.item.id == ielts.id)
        #expect(input.runningProgress?.countedSeconds == 3600.0)
        #expect(input.paused.map(\.item.title) == ["Report"])
    }

    @Test("Done tasks, other days' runs and running-only items are not paused")
    func pausedSkips() throws {
        let context = try context()
        let done = TaskRecord(title: "Done", completedAt: now)
        let yesterday = TaskRecord(title: "Yesterday")
        [done, yesterday].forEach(context.insert)
        let morning = TestCalendar.instant(calendar, 2026, 4, 13, 6)
        context.insert(WorkSessionRecord(startedAt: morning, endedAt: morning.addingTimeInterval(600), task: done))
        let dayBefore = TestCalendar.instant(calendar, 2026, 4, 12, 20)
        context.insert(WorkSessionRecord(startedAt: dayBefore, endedAt: dayBefore.addingTimeInterval(600), task: yesterday))
        try context.save()

        let input = try builder.build(now: now, in: context)
        #expect(input.paused.isEmpty)
    }

    @Test("A timer habit counts its logged time against its target and cannot be marked done")
    func timerHabitProgress() throws {
        let context = try context()
        let habit = HabitRecord(name: "IELTS", type: .timer(targetSeconds: 14_400), createdAt: now.addingTimeInterval(-86_400 * 3))
        context.insert(habit)
        let morning = TestCalendar.instant(calendar, 2026, 4, 13, 6)
        context.insert(WorkSessionRecord(startedAt: morning, endedAt: morning.addingTimeInterval(3600), habit: habit))
        // Logged by the run, plus 20 minutes logged by hand.
        context.insert(CompletionRecord(date: morning, value: 4800, habit: habit))
        try context.save()

        let input = try builder.build(now: now, in: context)
        let progress = try #require(input.paused.first)
        #expect(progress.countedSeconds == 4800.0)
        #expect(progress.targetSeconds == 14_400.0)
        #expect(!progress.canMarkDone)
    }

    @Test("A timer habit that reached its target leaves the paused list")
    func timerHabitReached() throws {
        let context = try context()
        let habit = HabitRecord(name: "IELTS", type: .timer(targetSeconds: 3600), createdAt: now.addingTimeInterval(-86_400 * 3))
        context.insert(habit)
        let morning = TestCalendar.instant(calendar, 2026, 4, 13, 6)
        context.insert(WorkSessionRecord(startedAt: morning, endedAt: morning.addingTimeInterval(3600), habit: habit))
        context.insert(CompletionRecord(date: morning, value: 3600, habit: habit))
        try context.save()

        #expect(try builder.build(now: now, in: context).paused.isEmpty)
    }

    @Test("A habit done today leaves the paused list")
    func doneHabitLeaves() throws {
        let context = try context()
        let habit = HabitRecord(name: "Read", type: .binary, createdAt: now.addingTimeInterval(-86_400 * 3))
        context.insert(habit)
        let morning = TestCalendar.instant(calendar, 2026, 4, 13, 6)
        context.insert(WorkSessionRecord(startedAt: morning, endedAt: morning.addingTimeInterval(600), habit: habit))
        try context.save()
        #expect(try builder.build(now: now, in: context).paused.map(\.item.id) == [habit.id])

        context.insert(CompletionRecord(date: morning, value: 1, habit: habit))
        try context.save()
        #expect(try builder.build(now: now, in: context).paused.isEmpty)
    }

    @Test("A session an earlier version paused shows as paused, counted up to its pause")
    func legacyPausedSession() throws {
        let context = try context()
        let task = TaskRecord(title: "Report")
        context.insert(task)
        let morning = TestCalendar.instant(calendar, 2026, 4, 13, 6)
        context.insert(WorkSessionRecord(startedAt: morning, pausedAt: morning.addingTimeInterval(1800), pausedSeconds: 600, task: task))
        try context.save()

        let input = try builder.build(now: now, in: context)
        #expect(input.openSession == nil)
        #expect(input.paused.first?.countedSeconds == 1200.0)
        #expect(input.paused.first?.runs == [DateInterval(start: morning, duration: 1800)])
    }
}
