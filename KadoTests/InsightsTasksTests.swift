import Foundation
import Testing
@testable import KadoCore

@Suite("Insights tasks")
struct InsightsTasksTests {
    typealias T = InsightsTestSupport

    private func tasks(_ tasks: [InsightsTask], _ context: InsightsContext = T.context()) -> InsightsTasks {
        InsightsCalculator.tasks(T.scope(InsightsInput(tasks: tasks), context))
    }

    @Test("No tasks, empty figures")
    func empty() {
        #expect(tasks([]) == .empty)
    }

    @Test("Done and left undone, this week and the week before")
    func doneAndUndone() {
        let result = tasks([
            T.task(completedOffset: -6),
            // Done late is still done.
            T.task(completedOffset: -1, dueOffset: -4),
            // Completed today: done.
            T.task(completedOffset: 0),
            T.task(plannedOffsets: [-2]),
            T.task(dueOffset: -5),
            // The last planned day (-3) decides, not the first one.
            T.task(plannedOffsets: [-8, -3]),
            // Due today, later, or never: not left undone.
            T.task(dueOffset: 0),
            T.task(dueOffset: 3),
            T.task(),
            // The week before.
            T.task(completedOffset: -7),
            T.task(completedOffset: -13),
            T.task(plannedOffsets: [-10]),
            // Two weeks ago: in neither week.
            T.task(completedOffset: -14),
            T.task(dueOffset: -14),
        ])
        #expect(result.done == 3)
        #expect(result.undone == 3)
        #expect(result.previousDone == 2)
        #expect(result.previousUndone == 1)
    }

    @Test("Archived tasks still count as done or left undone, but never as overdue")
    func archived() {
        let result = tasks([
            T.task(completedOffset: -2, archivedOffset: -1),
            T.task(dueOffset: -3, archivedOffset: -1),
        ])
        #expect(result.done == 1)
        #expect(result.undone == 1)
        #expect(result.overdueOpen == 0)
    }

    @Test("Cancelled imports are skipped everywhere")
    func cancelled() {
        let result = tasks([
            T.task(completedOffset: -2, dueOffset: -3, isCancelled: true),
            T.task(dueOffset: -2, isCancelled: true),
            T.task(dueOffset: -20, isCancelled: true),
        ])
        #expect(result == .empty)
    }

    @Test("On time: done on or before the target day, among done tasks that have one")
    func onTime() {
        let result = tasks([
            T.task(completedOffset: -2, dueOffset: -1),
            T.task(completedOffset: -2, dueOffset: -2),
            // Late: planned on -3, done on -1.
            T.task(completedOffset: -1, plannedOffsets: [-3]),
            // The last planned day (today) decides.
            T.task(completedOffset: -1, plannedOffsets: [-4, 0]),
            // No target day: not judged.
            T.task(completedOffset: -3),
            // Done the week before: not this week's figure.
            T.task(completedOffset: -9, dueOffset: -12),
        ])
        #expect(result.onTime == InsightsRate(done: 3, total: 4))
    }

    @Test("Days to finish count whole civil days, never below zero")
    func averageDaysToFinish() {
        let result = tasks([
            // Created on -5 at 08:00, done on -2 at 17:00: 3 days.
            T.task(createdDaysAgo: 5, completedOffset: -2),
            // The same day: 0.
            T.task(createdDaysAgo: 2, completedOffset: -2),
            // Created after it was done, as an import can be: 0, not -1.
            T.task(createdDaysAgo: 0, completedOffset: -1),
            // Done the week before, or still open: not counted.
            T.task(createdDaysAgo: 20, completedOffset: -8),
            T.task(createdDaysAgo: 9),
        ])
        #expect(result.averageDaysToFinish == 1.0)
        #expect(tasks([T.task(dueOffset: -2)]).averageDaysToFinish == nil)
    }

    @Test("Categories most often left undone: share, then count, at most 3")
    func undoneByCategory() {
        func batch(_ category: ItemCategory, done: Int, undone: Int) -> [InsightsTask] {
            (0 ..< done).map { _ in T.task(category: category, completedOffset: -2) }
                + (0 ..< undone).map { _ in T.task(category: category, dueOffset: -3) }
        }
        let input = batch(.fitness, done: 0, undone: 2)
            + batch(.errands, done: 1, undone: 3)
            + batch(.social, done: 3, undone: 3)
            + batch(.work, done: 2, undone: 2)
            // A single task is too few to judge.
            + batch(.home, done: 0, undone: 1)
            // Nothing left undone.
            + batch(.money, done: 2, undone: 0)
        #expect(tasks(input).undoneByCategory == [
            InsightsCategoryUndone(category: .fitness, undone: 2, total: 2),
            InsightsCategoryUndone(category: .errands, undone: 3, total: 4),
            InsightsCategoryUndone(category: .social, undone: 3, total: 6),
        ])
    }

    @Test("Equal shares and counts follow the category order")
    func undoneTies() {
        let input = [
            T.task(category: .creative, completedOffset: -2),
            T.task(category: .creative, dueOffset: -3),
            // The week before: not this week's figure.
            T.task(category: .creative, dueOffset: -9),
            T.task(category: .study, completedOffset: -2),
            T.task(category: .study, dueOffset: -3),
        ]
        #expect(tasks(input).undoneByCategory == [
            InsightsCategoryUndone(category: .study, undone: 1, total: 2),
            InsightsCategoryUndone(category: .creative, undone: 1, total: 2),
        ])
    }

    @Test("Open overdue tasks count whatever the period")
    func overdueOpen() {
        let result = tasks([
            T.task(plannedOffsets: [-20]),
            T.task(dueOffset: -1),
            // Archived, done, due today, without a target day, or cancelled: not overdue.
            T.task(dueOffset: -1, archivedOffset: 0),
            T.task(completedOffset: -1, dueOffset: -3),
            T.task(dueOffset: 0),
            T.task(),
            T.task(dueOffset: -2, isCancelled: true),
        ])
        #expect(result.overdueOpen == 2)
    }

    @Test("Tasks keep their civil day whatever the day start hour")
    func dayStartHour() {
        // Completed at 01:00 on day -6: civil day -6, inside the week,
        // though the logical day is still -7.
        let late = InsightsTask(id: UUID(), title: "Late", category: .other, createdAt: T.time(-9, 8), completedAt: T.time(-6, 1))
        let result = tasks([late], T.context(startHour: 4))
        #expect(result.done == 1)
        #expect(result.previousDone == 0)
    }

    @Test("Days to finish stay whole across a midnight DST change")
    func havanaMonth() {
        let calendar = TestCalendar.havana
        // Today is 2026-03-12 (day -32). 03-08 (day -36) starts at 01:00.
        let context = T.context(period: .month, today: T.day(-32, calendar: calendar), calendar: calendar)
        let result = tasks([
            // 03-07 to 03-09: 2 days.
            T.task(createdDaysAgo: 37, completedOffset: -35, calendar: calendar),
            // 03-08 to 03-09: 1 day, though the two day starts are 23 hours apart.
            T.task(createdDaysAgo: 36, completedOffset: -35, calendar: calendar),
            // Due on 03-08 and still open: left undone, and overdue.
            T.task(createdDaysAgo: 40, dueOffset: -36, calendar: calendar),
        ], context)
        #expect(result.averageDaysToFinish == 1.5)
        #expect(result.done == 2)
        #expect(result.undone == 1)
        #expect(result.overdueOpen == 1)
    }
}
