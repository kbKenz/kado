import Foundation
import SwiftData
import Testing
@testable import Kado
import KadoCore

@Suite("InsightsInputBuilder")
@MainActor
struct InsightsInputBuilderTests {
    private let calendar = TestCalendar.utc
    private var today: Date { calendar.startOfDay(for: TestCalendar.referenceDate) }

    /// Held for the test's lifetime: a `ModelContext` does not retain its container.
    private let container: ModelContainer

    init() throws {
        let schema = Schema(versionedSchema: KadoSchemaV10.self)
        container = try ModelContainer(for: schema, configurations: ModelConfiguration(UUID().uuidString, schema: schema, isStoredInMemoryOnly: true))
    }

    private var context: ModelContext { container.mainContext }

    /// Midnight `offset` days from the reference day.
    private func day(_ offset: Int) -> Date {
        calendar.date(byAdding: .day, value: offset, to: today)!
    }

    /// `hour:minute` on the day `offset` days from the reference day.
    private func time(_ offset: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day(offset))!
    }

    private func build() throws -> InsightsInput {
        try context.save()
        return try InsightsInputBuilder(civilToday: today, calendar: calendar).build(in: context)
    }

    @Test("An empty store gives an empty input, with Health left to the loader")
    func emptyStore() throws {
        #expect(try build() == .empty)
    }

    // MARK: - Categories

    @Test("A task's category: stored, else its goal's, else keywords, else Other")
    func taskCategories() throws {
        let study = GoalRecord(name: "Get into Cambridge", category: .study)
        let unsorted = GoalRecord(name: "Someday")
        [study, unsorted].forEach(context.insert)
        let stored = TaskRecord(title: "Run 5k", goal: study, category: .money)
        let fromGoal = TaskRecord(title: "Run 5k", goal: study)
        let goalWithoutCategory = TaskRecord(title: "Pay rent", goal: unsorted)
        let fromKeywords = TaskRecord(title: "Run 5k")
        let other = TaskRecord(title: "zzz qwerty")
        let storedOther = TaskRecord(title: "Run 5k", category: .other)
        [stored, fromGoal, goalWithoutCategory, fromKeywords, other, storedOther].forEach(context.insert)

        let categories = Dictionary(uniqueKeysWithValues: try build().tasks.map { ($0.id, $0.category) })

        #expect(categories[stored.id] == .money)
        #expect(categories[fromGoal.id] == .study)
        #expect(categories[goalWithoutCategory.id] == .money)
        #expect(categories[fromKeywords.id] == .fitness)
        #expect(categories[other.id] == .other)
        #expect(categories[storedOther.id] == .other)
    }

    @Test("A habit's category: stored, else its goal's, else keywords, else Other")
    func habitCategories() throws {
        let fitness = GoalRecord(name: "Run a half marathon", category: .fitness)
        context.insert(fitness)
        let stored = HabitRecord(name: "Run 5k", goal: fitness, category: .mind)
        let fromGoal = HabitRecord(name: "Take vitamins", goal: fitness)
        let fromKeywords = HabitRecord(name: "Take vitamins")
        let other = HabitRecord(name: "zzz qwerty")
        [stored, fromGoal, fromKeywords, other].forEach(context.insert)

        let categories = Dictionary(uniqueKeysWithValues: try build().habits.map { ($0.id, $0.category) })

        #expect(categories[stored.id] == .mind)
        #expect(categories[fromGoal.id] == .fitness)
        #expect(categories[fromKeywords.id] == .health)
        #expect(categories[other.id] == .other)
    }

    @Test("A goal's category: stored, else keywords, else Other")
    func goalCategories() throws {
        let stored = GoalRecord(name: "Get into Cambridge", category: .study)
        let fromKeywords = GoalRecord(name: "Run 5k")
        let other = GoalRecord(name: "Get into Cambridge")
        [stored, fromKeywords, other].forEach(context.insert)

        let categories = Dictionary(uniqueKeysWithValues: try build().goals.map { ($0.id, $0.category) })

        #expect(categories[stored.id] == .study)
        #expect(categories[fromKeywords.id] == .fitness)
        #expect(categories[other.id] == .other)
    }

    @Test("Resolving never writes a category back")
    func readsNeverWrite() throws {
        let goal = GoalRecord(name: "Get into Cambridge", category: .study)
        context.insert(goal)
        let task = TaskRecord(title: "Contact professors at Cambridge", goal: goal)
        let habit = HabitRecord(name: "Run 5k")
        context.insert(task)
        context.insert(habit)

        _ = try build()

        // build() saves first, so any change here was made by the builder.
        #expect(!context.hasChanges)
        #expect(task.categoryRaw.isEmpty)
        #expect(habit.categoryRaw.isEmpty)
        #expect(goal.categoryRaw == ItemCategory.study.rawValue)
    }

    // MARK: - Tasks

    @Test("Planned days are sorted unique civil midnights; the due day is a midnight too")
    func plannedDays() throws {
        let task = TaskRecord(title: "Essay", dueDate: time(4, 15, 30))
        context.insert(task)
        for planned in [time(3, 15), day(1), time(3, 9), time(2, 23, 59)] {
            context.insert(ScheduleBlockRecord(plannedDay: planned, task: task))
        }

        let built = try #require(try build().tasks.first)

        #expect(built.plannedDays == [day(1), day(2), day(3)])
        #expect(built.dueDay == day(4))
        #expect(built.targetDay == day(3))
    }

    @Test("A task carries its dates, its goal and its title")
    func taskFields() throws {
        let goal = GoalRecord(name: "Get into Cambridge", category: .study)
        context.insert(goal)
        let task = TaskRecord(
            title: "Order transcripts",
            createdAt: time(-10, 8),
            completedAt: time(-2, 17),
            archivedAt: time(-1, 20),
            goal: goal
        )
        let inbox = TaskRecord(title: "Renew passport", createdAt: time(-3, 9))
        [task, inbox].forEach(context.insert)

        let tasks = try build().tasks
        let built = try #require(tasks.first { $0.id == task.id })
        let undated = try #require(tasks.first { $0.id == inbox.id })

        #expect(built.title == "Order transcripts")
        #expect(built.createdAt == time(-10, 8))
        #expect(built.completedAt == time(-2, 17))
        #expect(built.archivedAt == time(-1, 20))
        #expect(built.goalID == goal.id)
        #expect(undated.dueDay == nil)
        #expect(undated.plannedDays.isEmpty)
        #expect(undated.goalID == nil)
        #expect(undated.completedAt == nil)
    }

    @Test("Cancelled imports are flagged; everything else is not")
    func cancelledImports() throws {
        let cancelled = TaskRecord(title: "Team lunch", externalEventID: "event-1", externalCancelledAt: time(-1, 12))
        let imported = TaskRecord(title: "Standup", externalEventID: "event-2")
        let local = TaskRecord(title: "Pay rent")
        [cancelled, imported, local].forEach(context.insert)

        let flags = Dictionary(uniqueKeysWithValues: try build().tasks.map { ($0.id, $0.isCancelled) })

        #expect(flags[cancelled.id] == true)
        #expect(flags[imported.id] == false)
        #expect(flags[local.id] == false)
    }

    // MARK: - Sessions

    @Test("A session takes its task's category and its block's planned range")
    func taskSession() throws {
        let goal = GoalRecord(name: "Get into Cambridge", category: .study)
        context.insert(goal)
        let task = TaskRecord(title: "Draft the personal statement", goal: goal)
        context.insert(task)
        let block = ScheduleBlockRecord(plannedDay: day(-1), startAt: time(-1, 9), endAt: time(-1, 10), task: task)
        context.insert(block)
        let record = WorkSessionRecord(startedAt: time(-1, 9, 5), endedAt: time(-1, 10, 20), pausedSeconds: 120, task: task, scheduleBlock: block)
        context.insert(record)

        let session = try #require(try build().sessions.first)

        #expect(session.id == record.id)
        #expect(session.category == .study)
        #expect(session.taskID == task.id)
        #expect(session.habitID == nil)
        #expect(session.plannedRange == DateInterval(start: time(-1, 9), end: time(-1, 10)))
        #expect(session.session == WorkSession(startedAt: time(-1, 9, 5), endedAt: time(-1, 10, 20), pausedSeconds: 120))
    }

    @Test("A session takes its habit's category; no timed block, no planned range")
    func habitSession() throws {
        let habit = HabitRecord(name: "Workout", type: .timer(targetSeconds: 2700), category: .fitness)
        context.insert(habit)
        let untimed = ScheduleBlockRecord(plannedDay: day(-2), startAt: time(-2, 18), habit: habit)
        context.insert(untimed)
        let open = WorkSessionRecord(startedAt: time(0, 7), habit: habit)
        let fromUntimedBlock = WorkSessionRecord(startedAt: time(-2, 18), endedAt: time(-2, 19), habit: habit, scheduleBlock: untimed)
        let orphan = WorkSessionRecord(startedAt: time(-3, 8), endedAt: time(-3, 9))
        [open, fromUntimedBlock, orphan].forEach(context.insert)

        let sessions = Dictionary(uniqueKeysWithValues: try build().sessions.map { ($0.id, $0) })

        let openSession = try #require(sessions[open.id])
        #expect(openSession.category == .fitness)
        #expect(openSession.habitID == habit.id)
        #expect(openSession.taskID == nil)
        #expect(openSession.plannedRange == nil)
        #expect(openSession.session.isOpen)
        #expect(sessions[fromUntimedBlock.id]?.plannedRange == nil)
        #expect(sessions[orphan.id]?.category == .other)
    }

    // MARK: - Goals

    @Test("Goal progress only when the measurement is on and available")
    func goalProgress() throws {
        let measured = GoalRecord(name: "Get into Cambridge", startDate: day(-30), targetDate: day(90), category: .study)
        measured.measurement = GoalMeasurement(enabled: true, mode: .tasks, target: 4, unit: "tasks")
        let off = GoalRecord(name: "Read more")
        off.measurement = GoalMeasurement(enabled: false, mode: .tasks, target: 4, unit: "tasks")
        let unavailable = GoalRecord(name: "Meditate daily")
        [measured, off, unavailable].forEach(context.insert)
        let binary = HabitRecord(name: "Meditate", goal: unavailable)
        context.insert(binary)
        // A habit-measured goal needs a counter or timer habit.
        unavailable.measurement = GoalMeasurement(enabled: true, mode: .habit, target: 10, unit: "times", habitID: binary.id)
        let done = TaskRecord(title: "Book the IELTS exam", completedAt: time(-5, 17), goal: measured)
        let open = TaskRecord(title: "Order transcripts", goal: measured)
        let offDone = TaskRecord(title: "Finish a novel", completedAt: time(-5, 17), goal: off)
        [done, open, offDone].forEach(context.insert)

        let goals = Dictionary(uniqueKeysWithValues: try build().goals.map { ($0.id, $0) })

        #expect(goals[measured.id]?.progress == 0.25)
        #expect(goals[off.id]?.progress == nil)
        #expect(goals[unavailable.id]?.progress == nil)
        let built = try #require(goals[measured.id])
        #expect(Set(built.linkedTaskIDs) == [done.id, open.id])
        #expect(built.startDate == day(-30))
        #expect(built.targetDate == day(90))
        #expect(goals[unavailable.id]?.linkedHabitIDs == [binary.id])
    }

    @Test("Without goal progress the input is the same, progress aside")
    func withoutGoalProgress() throws {
        let measured = GoalRecord(name: "Get into Cambridge", startDate: day(-30), targetDate: day(90), category: .study)
        measured.measurement = GoalMeasurement(enabled: true, mode: .tasks, target: 4, unit: "tasks")
        let plain = GoalRecord(name: "Read more")
        [measured, plain].forEach(context.insert)
        let habit = HabitRecord(name: "Read 20 pages", createdAt: day(-20), goal: plain)
        context.insert(habit)
        context.insert(CompletionRecord(date: time(-1, 21), value: 1, habit: habit))
        let task = TaskRecord(title: "Book the IELTS exam", completedAt: time(-5, 17), goal: measured)
        context.insert(task)
        context.insert(ScheduleBlockRecord(plannedDay: day(-6), startAt: time(-6, 9), endAt: time(-6, 10), task: task))
        context.insert(WorkSessionRecord(startedAt: time(-6, 9), endedAt: time(-6, 10), task: task))
        try context.save()

        let full = try build()
        let skipped = try InsightsInputBuilder(civilToday: today, calendar: calendar)
            .build(in: context, includeGoalProgress: false)

        #expect(full.goals.contains { $0.progress != nil })
        var expected = full
        expected.goals = full.goals.map { goal in
            var goal = goal
            goal.progress = nil
            return goal
        }
        #expect(skipped == expected)
        #expect(skipped.habits.map(\.completions) == full.habits.map(\.completions))
        #expect(skipped.goals.map(\.linkedTaskIDs) == full.goals.map(\.linkedTaskIDs))
    }

    @Test("A goal carries its status and whether it is archived")
    func goalStatus() throws {
        let paused = GoalRecord(name: "Learn Japanese", status: .paused)
        let archived = GoalRecord(name: "Plan a trip", archivedAt: time(-2, 10))
        [paused, archived].forEach(context.insert)

        let goals = Dictionary(uniqueKeysWithValues: try build().goals.map { ($0.id, $0) })

        #expect(goals[paused.id]?.status == .paused)
        #expect(goals[paused.id]?.isArchived == false)
        #expect(goals[archived.id]?.isArchived == true)
    }

    // MARK: - Habits

    @Test("Archived habits are included, each with its own completions")
    func archivedHabits() throws {
        let active = HabitRecord(name: "Read 20 pages", createdAt: day(-20))
        let archived = HabitRecord(name: "Old gym routine", createdAt: day(-60), archivedAt: time(-10, 9))
        [active, archived].forEach(context.insert)
        let note = CompletionRecord(date: time(-2, 21), value: 0, note: "Too tired", habit: active)
        [
            CompletionRecord(date: time(-1, 21), value: 1, habit: active),
            note,
            CompletionRecord(date: time(-12, 18), value: 1, habit: archived),
        ].forEach(context.insert)

        let habits = Dictionary(uniqueKeysWithValues: try build().habits.map { ($0.id, $0) })

        let builtArchived = try #require(habits[archived.id])
        #expect(builtArchived.habit.archivedAt == time(-10, 9))
        #expect(builtArchived.completions.map(\.date) == [time(-12, 18)])
        let builtActive = try #require(habits[active.id])
        // Note-only records stay; the calculators skip them.
        #expect(Set(builtActive.completions.map(\.id)).contains(note.id))
        #expect(builtActive.completions.allSatisfy { $0.habitID == active.id })
        #expect(builtActive.completions.count == 2)
    }
}
