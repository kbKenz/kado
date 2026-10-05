import Foundation
import SwiftData
import Testing
@testable import Kado
import KadoCore

/// Guards the data the Insights UI tests start from. A card can only be
/// checked by eye if this data gives it something to say, and nothing
/// else in the suite would notice if the seed drifted.
@Suite("InsightsSeed")
@MainActor
struct InsightsSeedTests {
    private let calendar = TestCalendar.utc
    /// Monday 2026-04-13, 12:00 UTC.
    private let now = TestCalendar.referenceDate
    private var today: Date { calendar.startOfDay(for: now) }

    /// Held for the test's lifetime: a `ModelContext` does not retain its container.
    private let container: ModelContainer

    init() throws {
        container = try Self.seededContainer(calendar: TestCalendar.utc, now: TestCalendar.referenceDate)
    }

    private static func seededContainer(calendar: Calendar, now: Date) throws -> ModelContainer {
        let schema = Schema(versionedSchema: KadoSchemaV9.self)
        let container = try ModelContainer(
            for: schema,
            configurations: ModelConfiguration(UUID().uuidString, schema: schema, isStoredInMemoryOnly: true)
        )
        InsightsSeed.seed(into: container.mainContext, calendar: calendar, now: now)
        return container
    }

    private var context: ModelContext { container.mainContext }

    private func input() throws -> InsightsInput {
        try InsightsInputBuilder(civilToday: today, calendar: calendar).build(in: context)
    }

    private func insightsContext(_ period: InsightsPeriod) -> InsightsContext {
        InsightsTestSupport.context(period: period, today: today, now: now, calendar: calendar)
    }

    private func day(_ offset: Int) -> Date {
        InsightsScope.step(today, by: offset, calendar: calendar)
    }

    // MARK: - Counts

    @Test("Seven habits, two goals, 42 tasks and 61 sessions")
    func counts() throws {
        let input = try input()
        #expect(input.habits.count == 7)
        #expect(input.goals.count == 2)
        #expect(input.tasks.count == 42)
        #expect(input.sessions.count == 61)
        let habits = try context.fetch(FetchDescriptor<HabitRecord>(sortBy: [SortDescriptor(\.sortOrder)]))
        #expect(habits.map(\.sortOrder) == Array(0..<7))
    }

    // MARK: - Habits

    @Test("Habits cover six categories, every type and three kinds of schedule")
    func habits() throws {
        let habits = Dictionary(uniqueKeysWithValues: try input().habits.map { ($0.habit.name, $0) })
        #expect(habits["In bed by 23:30"]?.category == .sleep)
        #expect(habits["Workout"]?.category == .fitness)
        #expect(habits["Workout"]?.habit.frequency == .daysPerWeek(4))
        #expect(habits["Workout"]?.habit.type == .timer(targetSeconds: 2700))
        #expect(habits["Read 20 pages"]?.category == .study)
        #expect(habits["Meditate"]?.category == .mind)
        #expect(habits["Meditate"]?.habit.type == .timer(targetSeconds: 600))
        #expect(habits["Drink water"]?.category == .health)
        #expect(habits["Drink water"]?.habit.type == .counter(target: 8))
        #expect(habits["Tidy up"]?.category == .home)
        #expect(habits["Tidy up"]?.habit.frequency == .specificDays([.wednesday, .saturday]))
        #expect(habits["No sugar"]?.category == .health)
        #expect(habits["No sugar"]?.habit.type == .negative)
    }

    /// Due days done / due days over the 90 days ending today, by the
    /// rule the Insights cards use (`InsightsScope.outcome`).
    private func consistency(of name: String) throws -> Double {
        let input = try input()
        let habit = try #require(input.habits.first { $0.habit.name == name })
        let scope = InsightsScope(input: input, context: insightsContext(.month))
        var done = 0
        var due = 0
        for day in InsightsScope.days(endingAt: today, count: 90, calendar: calendar) {
            guard case .due(let isDone) = scope.outcome(of: habit, on: day) else { continue }
            due += 1
            if isDone { done += 1 }
        }
        return Double(done) / Double(max(due, 1))
    }

    @Test("Each habit lands near its target consistency over 90 days", arguments: [
        ("In bed by 23:30", 0.75...0.85),
        ("Workout", 0.75...0.85),
        ("Read 20 pages", 0.65...0.75),
        ("Meditate", 0.80...0.90),
        ("Drink water", 0.55...0.65),
        ("Tidy up", 0.65...0.85),
        ("No sugar", 0.90...0.97),
    ])
    func consistency(name: String, range: ClosedRange<Double>) throws {
        let rate = try consistency(of: name)
        #expect(range.contains(rate), "\(name) is at \(Int((rate * 100).rounded()))%")
    }

    @Test("Meditate is on its best streak, today included")
    func meditationStreak() throws {
        let meditate = try #require(try input().habits.first { $0.habit.name == "Meditate" })
        let streaks = DefaultStreakCalculator(calendar: calendar)
        #expect(streaks.current(for: meditate.habit, completions: meditate.completions, asOf: today) == InsightsSeed.meditationStreak)
        #expect(streaks.best(for: meditate.habit, completions: meditate.completions, asOf: today) == InsightsSeed.meditationStreak)
    }

    @Test("The negative habit has a few slips, none in the last week")
    func sugarSlips() throws {
        let sugar = try #require(try input().habits.first { $0.habit.name == "No sugar" })
        #expect(sugar.completions.count == InsightsSeed.sugarSlips.count)
        let lastSlip = try #require(sugar.completions.map(\.date).max())
        #expect(lastSlip < day(-7))
    }

    @Test("The last 30 days have perfect days, but not only perfect days")
    func perfectDays() throws {
        let input = try input()
        let scope = InsightsScope(input: input, context: insightsContext(.month))
        let perfect = scope.days.filter { day in
            let outcomes = input.habits.map { scope.outcome(of: $0, on: day) }
            let due = outcomes.compactMap { outcome -> Bool? in
                if case .due(let done) = outcome { return done }
                return nil
            }
            return !due.isEmpty && due.allSatisfy { $0 }
        }
        #expect(perfect.count >= 5)
        #expect(perfect.count <= 20)
    }

    // MARK: - Tasks

    @Test("Tasks are done on time, done late, left undone and still to come")
    func taskStates() throws {
        let tasks = try input().tasks
        let done = tasks.filter { $0.completedAt != nil }
        let late = done.filter { task in
            guard let target = task.targetDay, let completed = task.completedAt else { return false }
            return calendar.startOfDay(for: completed) > target
        }
        let undone = tasks.filter { task in
            task.completedAt == nil && (task.targetDay.map { $0 < today } ?? false)
        }
        let upcoming = tasks.filter { task in
            task.completedAt == nil && (task.targetDay.map { $0 > today } ?? false)
        }
        #expect(done.count == 26)
        #expect(late.count == 7)
        #expect(undone.count == 7)
        #expect(upcoming.count == 8)
        #expect(tasks.filter { $0.targetDay == nil }.count == 1)
    }

    @Test("Tasks span seven categories; some get theirs from the goal or the keywords")
    func taskCategories() throws {
        let counts = Dictionary(grouping: try input().tasks, by: \.category).mapValues(\.count)
        #expect(counts == [.study: 12, .fitness: 2, .work: 9, .errands: 6, .home: 5, .social: 4, .money: 4])
        let unset = try context.fetch(FetchDescriptor<TaskRecord>()).filter { $0.category == nil }
        #expect(unset.count == 18)
    }

    @Test("Errands are the category most often left undone")
    func errandsLeftUndone() throws {
        let tasks = try input().tasks
        let undone = Dictionary(grouping: tasks.filter { task in
            task.completedAt == nil && (task.targetDay.map { $0 < today } ?? false)
        }, by: \.category).mapValues(\.count)
        #expect(undone[.errands] == 3)
        #expect(undone.values.allSatisfy { $0 <= 3 })
    }

    // MARK: - Goals

    @Test("Both goals are measured and under way")
    func goals() throws {
        let goals = Dictionary(uniqueKeysWithValues: try input().goals.map { ($0.name, $0) })
        let cambridge = try #require(goals["Get into Cambridge"])
        #expect(cambridge.category == .study)
        #expect(cambridge.linkedTaskIDs.count == 12)
        #expect(cambridge.progress == 7.0 / 12.0)
        #expect(cambridge.targetDate == day(120))
        let marathon = try #require(goals["Run a half marathon"])
        #expect(marathon.category == .fitness)
        #expect(marathon.linkedHabitIDs.count == 1)
        let progress = try #require(marathon.progress)
        #expect(progress > 0.4 && progress < 0.7)
    }

    // MARK: - Sessions

    @Test("Sessions run on tasks and timer habits, in every part of the day, none left open")
    func sessions() throws {
        let sessions = try input().sessions
        #expect(sessions.filter { $0.taskID != nil }.count == 45)
        #expect(sessions.filter { $0.habitID != nil }.count == 16)
        #expect(sessions.allSatisfy { !$0.session.isOpen })
        #expect(Set(sessions.map(\.category)) == [.study, .work, .fitness, .mind, .home, .money, .social, .errands])
        let parts = Set(sessions.map { InsightsPartOfDay.of(hour: calendar.component(.hour, from: $0.session.startedAt)) })
        #expect(parts == Set(InsightsPartOfDay.allCases))
    }

    @Test("Fifteen sessions ran from a timed block, some longer and some shorter than planned")
    func plannedSessions() throws {
        let planned = try input().sessions.compactMap { session -> (tracked: TimeInterval, planned: TimeInterval)? in
            guard let range = session.plannedRange else { return nil }
            return (session.session.elapsed(at: now), range.duration)
        }
        #expect(planned.count == 15)
        #expect(planned.filter { $0.tracked > $0.planned }.count == 8)
        #expect(planned.filter { $0.tracked < $0.planned }.count == 6)
    }

    @Test("A timer habit's session lasts what its day's record holds")
    func habitSessionsMatchTheirRecords() throws {
        let input = try input()
        for session in input.sessions {
            guard let habitID = session.habitID else { continue }
            let habit = try #require(input.habits.first { $0.id == habitID })
            let record = habit.completions.first { calendar.isDate($0.date, inSameDayAs: session.session.startedAt) }
            #expect(record?.value == session.session.elapsed(at: now))
        }
    }

    // MARK: - Time

    @Test("Nothing is stamped after now, whatever the time of day", arguments: [0, 6, 12, 23])
    func nothingAfterNow(hour: Int) throws {
        let now = calendar.date(bySettingHour: hour, minute: 30, second: 0, of: today)!
        let container = try Self.seededContainer(calendar: calendar, now: now)
        let context = container.mainContext
        let completions = try context.fetch(FetchDescriptor<CompletionRecord>())
        let tasks = try context.fetch(FetchDescriptor<TaskRecord>())
        let sessions = try context.fetch(FetchDescriptor<WorkSessionRecord>())
        #expect(completions.allSatisfy { $0.date <= now })
        #expect(tasks.allSatisfy { $0.createdAt <= now && ($0.completedAt ?? now) <= now })
        #expect(sessions.allSatisfy { ($0.endedAt ?? .distantFuture) <= now })
        // Today's records stay on today, even when stamped early.
        let todays = completions.filter { $0.date >= today }
        #expect(todays.allSatisfy { calendar.isDate($0.date, inSameDayAs: today) })
        #expect(todays.count == 2)
    }

    @Test("Seeding twice from the same moment gives the same data")
    func isDeterministic() throws {
        let other = try Self.seededContainer(calendar: calendar, now: now)
        #expect(try Self.fingerprint(context) == Self.fingerprint(other.mainContext))
    }

    private static func fingerprint(_ context: ModelContext) throws -> [String] {
        func stamp(_ date: Date?) -> String { date.map { "\($0.timeIntervalSince1970)" } ?? "-" }
        let completions = try context.fetch(FetchDescriptor<CompletionRecord>()).map {
            "\($0.habit?.name ?? "")|\(stamp($0.date))|\($0.value)"
        }
        let tasks = try context.fetch(FetchDescriptor<TaskRecord>()).map { task in
            let blocks = (task.scheduleBlocks ?? []).map { "\(stamp($0.plannedDay))/\(stamp($0.startAt))/\(stamp($0.endAt))" }.sorted()
            return "\(task.title)|\(task.categoryRaw)|\(stamp(task.createdAt))|\(stamp(task.completedAt))|\(blocks)"
        }
        let sessions = try context.fetch(FetchDescriptor<WorkSessionRecord>()).map {
            "\($0.task?.title ?? $0.habit?.name ?? "")|\(stamp($0.startedAt))|\(stamp($0.endedAt))"
        }
        return (completions + tasks + sessions).sorted()
    }

    // MARK: - Report

    @Test("A report on the seed is not the first-run state", arguments: InsightsPeriod.allCases)
    func reportIsNotEmpty(period: InsightsPeriod) throws {
        let report = InsightsCalculator().report(input: try input(), context: insightsContext(period))
        #expect(!report.isEmpty)
        #expect(report.days.count == period.dayCount)
    }

    /// Every card's content, on a month report. The calculator sections
    /// are built on other branches; until they are all merged here, most
    /// of them still return their empty value.
    @Test("Every section of a month report has something to show",
          .disabled("Turn on once every Insights calculator section is merged"))
    func everySectionHasContent() throws {
        let report = InsightsCalculator().report(input: try input(), context: insightsContext(.month))
        #expect(report.pulse.consistency.total > 0)
        #expect(report.pulse.previousConsistency.total > 0)
        #expect(report.pulse.followThrough.total > 0)
        #expect(report.pulse.activeDays.done > 0)
        #expect(!report.highlights.isEmpty)
        #expect(report.activity.perfectDays > 0)
        #expect(report.focus.total > 0)
        #expect(report.focus.planRatio != nil)
        #expect(report.categories.count >= 6)
        #expect(!report.sleep.habits.isEmpty)
        #expect(!report.movement.habits.isEmpty)
        #expect(report.movement.fitnessTimesDone > 0)
        #expect(report.habits.count == 7)
        #expect(report.tasks.done > 0)
        #expect(report.tasks.undone > 0)
        #expect(!report.tasks.undoneByCategory.isEmpty)
        #expect(report.tasks.overdueOpen > 0)
        #expect(report.goals.count == 2)
        #expect(report.goals.allSatisfy { $0.pace != nil && $0.progress != nil })
        #expect(report.rhythm.bestWeekday != nil)
        #expect(report.rhythm.peakPartOfDay != nil)
        #expect(report.allTime.daysSinceStart > 90)
        #expect(report.allTime.bestStreak != nil)
    }
}
