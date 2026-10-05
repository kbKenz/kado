import Foundation
import Testing
@testable import KadoCore

@Suite("Insights goals")
struct InsightsGoalsTests {
    typealias T = InsightsTestSupport

    private func rows(_ input: InsightsInput, _ context: InsightsContext = T.context()) -> [InsightsGoalRow] {
        InsightsCalculator.goals(T.scope(input, context))
    }

    /// The row of the only goal in `input`.
    private func row(_ input: InsightsInput, _ context: InsightsContext = T.context()) throws -> InsightsGoalRow {
        let result = rows(input, context)
        try #require(result.count == 1)
        return result[0]
    }

    /// A goal created `createdDaysAgo` days before the reference day.
    /// The start and target dates are midnights `offset` days from it.
    private func goal(
        _ name: String = "Goal",
        status: GoalStatus = .active,
        isArchived: Bool = false,
        startOffset: Int? = nil,
        targetOffset: Int? = nil,
        createdDaysAgo: Int = 10,
        progress: Double? = nil,
        tasks: [InsightsTask] = [],
        habits: [InsightsHabit] = [],
        calendar: Calendar = T.calendar
    ) -> InsightsGoal {
        InsightsGoal(
            id: UUID(),
            name: name,
            category: .study,
            status: status,
            isArchived: isArchived,
            startDate: startOffset.map { T.day($0, calendar: calendar) },
            targetDate: targetOffset.map { T.day($0, calendar: calendar) },
            createdAt: T.time(-createdDaysAgo, 8, calendar: calendar),
            progress: progress,
            linkedTaskIDs: tasks.map(\.id),
            linkedHabitIDs: habits.map(\.id)
        )
    }

    @Test("No goals, no rows")
    func empty() {
        #expect(rows(.empty).isEmpty)
    }

    @Test("Only active goals that are not archived get a row")
    func activeOnly() {
        let input = InsightsInput(goals: [
            goal("Active"),
            goal("Paused", status: .paused),
            goal("Completed", status: .completed),
            goal("Archived", isArchived: true),
        ])
        #expect(rows(input).map(\.name) == ["Active"])
    }

    @Test("A row carries the goal's id, name, category and progress")
    func basics() throws {
        let cambridge = goal("Get into Cambridge", progress: 0.4)
        let result = try row(InsightsInput(goals: [cambridge]))
        #expect(result.goalID == cambridge.id)
        #expect(result.name == "Get into Cambridge")
        #expect(result.category == .study)
        #expect(result.progress == 0.4)
    }

    @Test("Linked tasks: done ever, done in the week, and the total")
    func linkedTasks() throws {
        let linked = [
            T.task(completedOffset: -2),
            // Done the day before the week: done, but not in the week.
            T.task(completedOffset: -7),
            T.task(dueOffset: 3),
            // Cancelled imports are skipped.
            T.task(completedOffset: -1, isCancelled: true),
        ]
        let unlinked = T.task(completedOffset: -1)
        let result = try row(InsightsInput(tasks: linked + [unlinked], goals: [goal(tasks: linked)]))
        #expect(result.tasksDone == 2)
        #expect(result.tasksTotal == 3)
        #expect(result.tasksDoneInPeriod == 1)
    }

    @Test("Habit consistency covers the linked habits, today as a grace day")
    func linkedHabits() throws {
        // Done on -6, -4 and -2 out of -6...-1; today is not done yet.
        let read = T.habit("Read", doneOffsets: [-10, -6, -4, -2])
        // Done today, so today counts: 2 of 2.
        let write = T.habit("Write", doneOffsets: [-1, 0])
        // Archived on -5: done on -6, missed on -5.
        let old = T.habit("Old", archivedOffset: -5, doneOffsets: [-10, -6])
        let other = T.habit("Other", doneOffsets: [-10])
        let input = InsightsInput(habits: [read, write, old, other], goals: [goal(habits: [read, write, old])])
        #expect(try row(input).habitConsistency == InsightsRate(done: 6, total: 10))
    }

    @Test("Pace compares progress with the share of time gone")
    func pace() throws {
        // Created on day -10 with a target on day 10: half the time is gone.
        func paceFor(_ progress: Double?) throws -> InsightsGoalPace? {
            try row(InsightsInput(goals: [goal(targetOffset: 10, createdDaysAgo: 10, progress: progress)])).pace
        }
        #expect(try paceFor(0.5) == .onTrack)
        #expect(try paceFor(0.8) == .ahead)
        #expect(try paceFor(0.2) == .behind)
        // The edges: 0.1 ahead is ahead, 0.1 behind is still on track.
        #expect(try paceFor(0.6) == .ahead)
        #expect(try paceFor(0.4) == .onTrack)
        #expect(try paceFor(0.39) == .behind)
        #expect(try paceFor(nil) == nil)
    }

    @Test("The start date wins over the creation day")
    func startDate() throws {
        // Started on day -5 for a target on day 5: half the time is gone.
        // Counted from the creation day (-15), it would be three quarters.
        let started = goal(startOffset: -5, targetOffset: 5, createdDaysAgo: 15, progress: 0.5)
        #expect(try row(InsightsInput(goals: [started])).pace == .onTrack)
    }

    @Test("No pace without a target date, or without days between start and target")
    func noPace() {
        let input = InsightsInput(goals: [
            goal("No target", progress: 0.5),
            goal("Same day", startOffset: 3, targetOffset: 3, progress: 0.5),
            goal("Backwards", startOffset: 3, targetOffset: 1, progress: 0.5),
        ])
        #expect(rows(input).map(\.pace) == [nil, nil, nil])
    }

    @Test("The share of time gone stays between 0 and 1")
    func clampedShare() {
        let input = InsightsInput(goals: [
            // Past its target: all the time is gone, 0.95 is on track.
            goal("Late", startOffset: -10, targetOffset: -2, progress: 0.95),
            // Not started yet: no time is gone, 0.05 is on track.
            goal("Later", startOffset: 5, targetOffset: 15, progress: 0.05),
        ])
        #expect(rows(input).map(\.pace) == [.onTrack, .onTrack])
    }

    @Test("Days left count civil days to the target, 0 on the day, none after it")
    func daysLeft() {
        var evening = goal("Evening")
        evening.targetDate = T.time(10, 15)
        let input = InsightsInput(goals: [
            goal("Today", targetOffset: 0),
            goal("Soon", targetOffset: 3),
            evening,
            goal("Past", targetOffset: -1),
            goal("Open"),
        ])
        let result = rows(input)
        #expect(result.map(\.name) == ["Past", "Today", "Soon", "Evening", "Open"])
        #expect(result.map(\.daysLeft) == [nil, 0, 3, 10, nil])
    }

    @Test("Rows sort by target date, then name, with no target date last")
    func sorting() {
        let input = InsightsInput(goals: [
            goal("Zeta"),
            goal("Beta", targetOffset: 20),
            goal("Alpha", targetOffset: 20),
            goal("Gamma", targetOffset: 5),
            goal("Delta"),
        ])
        #expect(rows(input).map(\.name) == ["Gamma", "Alpha", "Beta", "Delta", "Zeta"])
    }

    @Test("Pace and days left count whole days across a midnight DST change")
    func havana() throws {
        let calendar = TestCalendar.havana
        // Started 2026-03-08 (day -36), a day that starts at 01:00, only
        // 23 hours before the next midnight. Target 03-20 (-24): 12 days.
        let cambridge = goal(startOffset: -36, targetOffset: -24, progress: 0.39, calendar: calendar)
        let input = InsightsInput(goals: [cambridge])
        // Today 03-14 (-30): 6 of the 12 days are gone, so 0.39 is behind.
        let midway = try row(input, T.context(today: T.day(-30, calendar: calendar), calendar: calendar))
        #expect(midway.pace == .behind)
        #expect(midway.daysLeft == 6)
        // Today 03-08: 12 days left.
        let first = try row(input, T.context(today: T.day(-36, calendar: calendar), calendar: calendar))
        #expect(first.daysLeft == 12)
    }
}
