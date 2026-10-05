import Foundation
import Testing
@testable import KadoCore

@Suite("Insights categories")
struct InsightsCategoriesTests {
    typealias T = InsightsTestSupport

    private func rows(_ input: InsightsInput, _ context: InsightsContext = T.context()) -> [InsightsCategoryRow] {
        InsightsCalculator.categories(T.scope(input, context))
    }

    @Test("No records, no rows")
    func empty() {
        #expect(rows(.empty).isEmpty)
    }

    @Test("Each category adds up its focus, habits and tasks in the week")
    func mainRule() {
        let input = InsightsInput(
            habits: [
                // Done on -6, -5, -3 and today; missed on -4, -2 and -1.
                T.habit("Read", category: .study, doneOffsets: [-10, -6, -5, -3, 0]),
                // No slip on 5 of the 6 days before today. A slip is not a time done.
                T.habit("Smoke", type: .negative, category: .health, doneOffsets: [-2]),
            ],
            tasks: [
                T.task(category: .study, completedOffset: -2),
                T.task(category: .work, plannedOffsets: [-1]),
                // Due today: not left undone yet.
                T.task(category: .work, dueOffset: 0),
            ],
            sessions: [
                T.session(offset: -1, minutes: 90, category: .study),
                T.session(offset: -3, minutes: 120, category: .work),
            ]
        )
        #expect(rows(input) == [
            InsightsCategoryRow(category: .work, focusSeconds: 7200.0, tasksUndone: 1),
            InsightsCategoryRow(
                category: .study,
                focusSeconds: 5400.0,
                habitConsistency: InsightsRate(done: 4, total: 7),
                habitTimesDone: 4,
                tasksDone: 1
            ),
            InsightsCategoryRow(category: .health, habitConsistency: InsightsRate(done: 5, total: 6)),
        ])
    }

    @Test("Times done add up each habit's days, and slips are not times done")
    func timesDoneAcrossHabits() throws {
        let input = InsightsInput(habits: [
            T.habit("Read", category: .study, doneOffsets: [-2, -1]),
            T.habit("Flashcards", category: .study, doneOffsets: [-1]),
            T.habit("Doomscroll", type: .negative, category: .study, doneOffsets: [-1]),
        ])
        let row = try #require(rows(input).first)
        #expect(row.habitTimesDone == 3)
        // Read: 2 of 2. Flashcards: 1 of 1. Doomscroll: no slip on 5 of 6 days.
        #expect(row.habitConsistency == InsightsRate(done: 8, total: 9))
    }

    @Test("Rows sort by focus, then times done, then the category order")
    func sorting() {
        let input = InsightsInput(
            habits: [T.habit("Call", category: .social, doneOffsets: [-1])],
            tasks: [
                T.task(category: .home, completedOffset: -2),
                T.task(category: .money, completedOffset: -2),
                T.task(category: .money, completedOffset: -3),
                T.task(category: .creative, completedOffset: -1),
                T.task(category: .other, dueOffset: -2),
            ],
            sessions: [
                T.session(offset: -4, minutes: 30, category: .work),
                T.session(offset: -5, minutes: 30, category: .creative),
            ]
        )
        // Creative and Work tie on focus; Social and Home tie on times done.
        #expect(rows(input).map(\.category) == [.creative, .work, .money, .social, .home, .other])
    }

    @Test("Today joins a category's consistency only once it is done")
    func todayGrace() {
        let notYet = T.habit("Stretch", category: .fitness, doneOffsets: [-1])
        let doneToday = T.habit("Journal", category: .mind, doneOffsets: [-1, 0])
        #expect(rows(InsightsInput(habits: [notYet, doneToday])) == [
            InsightsCategoryRow(category: .mind, habitConsistency: InsightsRate(done: 2, total: 2), habitTimesDone: 2),
            InsightsCategoryRow(category: .fitness, habitConsistency: InsightsRate(done: 1, total: 1), habitTimesDone: 1),
        ])
    }

    @Test("An archived habit counts up to the day it was archived")
    func archivedHabit() {
        // Done on -6 and -5, missed on -4, the archive day.
        let run = T.habit("Run", category: .fitness, archivedOffset: -4, doneOffsets: [-12, -6, -5])
        // Archived before the week: nothing to show.
        let old = T.habit("Sleep early", category: .sleep, archivedOffset: -8, doneOffsets: [-9, -8])
        #expect(rows(InsightsInput(habits: [run, old])) == [
            InsightsCategoryRow(category: .fitness, habitConsistency: InsightsRate(done: 2, total: 3), habitTimesDone: 2),
        ])
    }

    @Test("A day just outside the week adds nothing")
    func periodEdge() {
        let input = InsightsInput(
            tasks: [
                T.task(category: .errands, completedOffset: -7),
                T.task(category: .errands, dueOffset: -7),
                T.task(category: .money, dueOffset: -6),
            ],
            sessions: [
                // Starts the day before the week and runs into it: it stays on its start day.
                T.session(offset: -7, hour: 23, minute: 30, minutes: 60, category: .mind),
                T.session(offset: -6, hour: 0, minutes: 15, category: .work),
            ]
        )
        #expect(rows(input) == [
            InsightsCategoryRow(category: .work, focusSeconds: 900.0),
            InsightsCategoryRow(category: .money, tasksUndone: 1),
        ])
    }

    @Test("Cancelled imports and sessions with no tracked time add nothing")
    func skipped() {
        let input = InsightsInput(
            tasks: [
                T.task(category: .work, completedOffset: -2, isCancelled: true),
                T.task(category: .work, plannedOffsets: [-3], isCancelled: true),
            ],
            sessions: [T.session(offset: -2, minutes: 0, category: .creative)]
        )
        #expect(rows(input).isEmpty)
    }

    @Test("An open session counts up to now")
    func openSession() {
        // Open since 17:00; now is 18:00.
        let open = InsightsSession(id: UUID(), session: WorkSession(startedAt: T.time(0, 17)), category: .work)
        #expect(rows(InsightsInput(sessions: [open])) == [InsightsCategoryRow(category: .work, focusSeconds: 3600.0)])
    }

    @Test("Sessions follow the day start hour, tasks keep their civil day")
    func dayStartHour() {
        // 02:00 on day -6 still belongs to day -7, outside the week.
        let session = T.session(offset: -6, hour: 2, minutes: 30, category: .work)
        // Completed at 02:00 on day -6: civil day -6, inside the week.
        let task = InsightsTask(id: UUID(), title: "Late", category: .home, createdAt: T.time(-9, 8), completedAt: T.time(-6, 2))
        let input = InsightsInput(tasks: [task], sessions: [session])
        #expect(rows(input, T.context(startHour: 4)) == [InsightsCategoryRow(category: .home, tasksDone: 1)])
    }

    @Test("A month across a midnight DST change counts every day once")
    func havanaMonth() {
        let calendar = TestCalendar.havana
        // Today is 2026-03-12 (day -32); the month runs 02-11 (-61) to
        // 03-12 and holds 03-08 (-36), a day that starts at 01:00.
        let context = T.context(period: .month, today: T.day(-32, calendar: calendar), calendar: calendar)
        let input = InsightsInput(
            habits: [T.habit("Read", category: .study, createdDaysAgo: 61, doneOffsets: Array(-61 ... -32), calendar: calendar)],
            tasks: [T.task(category: .study, createdDaysAgo: 40, completedOffset: -36, calendar: calendar)],
            sessions: [
                T.session(offset: -36, minutes: 60, category: .study, calendar: calendar),
                // The day before the month.
                T.session(offset: -62, minutes: 60, category: .study, calendar: calendar),
            ]
        )
        #expect(rows(input, context) == [
            InsightsCategoryRow(
                category: .study,
                focusSeconds: 3600.0,
                habitConsistency: InsightsRate(done: 30, total: 30),
                habitTimesDone: 30,
                tasksDone: 1
            ),
        ])
    }
}
