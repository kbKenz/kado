import Foundation
import Testing
@testable import KadoCore

@Suite("Insights all time")
struct InsightsAllTimeTests {
    typealias T = InsightsTestSupport

    private func calculate(_ input: InsightsInput, _ context: InsightsContext = T.context()) -> InsightsAllTime {
        InsightsCalculator.allTime(T.scope(input, context))
    }

    @Test("Without records: no first day and nothing counted")
    func empty() {
        #expect(calculate(.empty) == .empty)
    }

    @Test("The first day is the earliest habit, completion, task or session")
    func firstDay() {
        let habit = T.habit(createdDaysAgo: 10)
        // Logged on day -12, before it was created on day -5.
        let backfilled = T.habit(createdDaysAgo: 5, doneOffsets: [-12])
        let task = T.task(createdDaysAgo: 20)
        let session = T.session(offset: -30, minutes: 10)
        #expect(calculate(InsightsInput(habits: [habit])).firstDay == T.day(-10))
        #expect(calculate(InsightsInput(habits: [backfilled])).firstDay == T.day(-12))
        #expect(calculate(InsightsInput(tasks: [task])).firstDay == T.day(-20))
        #expect(calculate(InsightsInput(sessions: [session])).firstDay == T.day(-30))
        let allTime = calculate(InsightsInput(habits: [habit, backfilled], tasks: [task], sessions: [session]))
        #expect(allTime.firstDay == T.day(-30))
        // Day -30 to today, both included.
        #expect(allTime.daysSinceStart == 31)
    }

    @Test("Empty records, cancelled tasks and sessions without time do not set the first day")
    func ignoredRecords() {
        let habit = T.habit(createdDaysAgo: 5, doneOffsets: [-40], value: 0)
        let cancelled = T.task(createdDaysAgo: 50, isCancelled: true)
        let noTime = T.session(offset: -60, minutes: 0)
        let allTime = calculate(InsightsInput(habits: [habit], tasks: [cancelled], sessions: [noTime]))
        #expect(allTime.firstDay == T.day(-5))
        #expect(allTime.daysSinceStart == 6)
    }

    @Test("A first record today makes one day")
    func startedToday() {
        let allTime = calculate(InsightsInput(habits: [T.habit(createdDaysAgo: 0)]))
        #expect(allTime.firstDay == T.day(0))
        #expect(allTime.daysSinceStart == 1)
    }

    @Test("Times done: one per habit and day with a positive record, archived habits included, never a slip")
    func habitTimesDone() {
        let walk = T.habit("Walk", doneOffsets: [-100, -3, -3, -1])
        let water = T.habit("Water", type: .counter(target: 8), doneOffsets: [-2], value: 4)
        let journal = T.habit("Journal", doneOffsets: [-4], value: 0)
        let smoking = T.habit("Smoking", type: .negative, doneOffsets: [-2])
        let old = T.habit("Old", archivedOffset: -50, doneOffsets: [-60, -55])
        let allTime = calculate(InsightsInput(habits: [walk, water, journal, smoking, old]))
        // Walk 3 days (two records on day -3), water 1, old 2.
        #expect(allTime.habitTimesDone == 6)
    }

    @Test("Tasks done: every completed task, archived or long ago, never a cancelled one")
    func tasksDone() {
        let tasks = [
            T.task(createdDaysAgo: 300, completedOffset: -200),
            T.task(completedOffset: 0),
            T.task(completedOffset: -3, archivedOffset: -1),
            T.task(completedOffset: -2, isCancelled: true),
            T.task(plannedOffsets: [-5]),
        ]
        #expect(calculate(InsightsInput(tasks: tasks)).tasksDone == 3)
    }

    @Test("Focus: every session ever, an open one up to now")
    func focusSeconds() {
        // The context's now is 18:00 today.
        let open = InsightsSession(id: UUID(), session: WorkSession(startedAt: T.time(0, 17)), category: .work)
        let sessions = [
            T.session(offset: -300, minutes: 30),
            T.session(offset: -1, minutes: 45),
            T.session(offset: -2, minutes: 0),
            open,
        ]
        #expect(calculate(InsightsInput(sessions: sessions)).focusSeconds == 135.0 * 60)
    }

    @Test("Best streak: the highest best streak of any habit, archived ones included")
    func bestStreak() {
        // Days -10...-6, a miss on day -5, then days -4...-1: the best run is 5.
        let read = T.habit("Read", doneOffsets: Array(-10 ... -6) + Array(-4 ... -1))
        // 7 days in a row long ago, then archived.
        let old = T.habit("Old", archivedOffset: -20, doneOffsets: Array(-40 ... -34))
        let walk = T.habit("Walk", doneOffsets: [-3, -2, -1])
        #expect(calculate(InsightsInput(habits: [read, walk])).bestStreak == InsightsNamedCount(name: "Read", count: 5))
        #expect(calculate(InsightsInput(habits: [read, old, walk])).bestStreak == InsightsNamedCount(name: "Old", count: 7))
    }

    @Test("Best streak: ties go to the first habit, and there is none below one day")
    func bestStreakTiesAndNone() {
        let read = T.habit("Read", doneOffsets: [-2, -1])
        let walk = T.habit("Walk", doneOffsets: [-5, -4])
        #expect(calculate(InsightsInput(habits: [read, walk])).bestStreak == InsightsNamedCount(name: "Read", count: 2))
        let never = T.habit("Never")
        #expect(calculate(InsightsInput(habits: [never])).bestStreak == nil)
    }

    @Test("Havana: the days since start count the midnight DST day once")
    func havana() {
        let calendar = TestCalendar.havana
        // Day -36 is 2026-03-08, when Havana's clock skips from 00:00 to
        // 01:00, so that day starts at 01:00. Day -32 is 2026-03-12.
        let habit = T.habit(createdDaysAgo: 36, doneOffsets: [-36, -35], calendar: calendar)
        let context = T.context(today: T.day(-32, calendar: calendar), calendar: calendar)
        let allTime = InsightsCalculator.allTime(T.scope(InsightsInput(habits: [habit]), context))
        #expect(allTime.firstDay == T.day(-36, calendar: calendar))
        // March 8 to March 12, both included.
        #expect(allTime.daysSinceStart == 5)
        #expect(allTime.habitTimesDone == 2)
    }
}
