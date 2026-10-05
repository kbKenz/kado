import Foundation
import Testing
@testable import KadoCore

@Suite("Insights pulse")
struct InsightsPulseTests {
    typealias T = InsightsTestSupport

    private func pulse(_ input: InsightsInput, _ context: InsightsContext = T.context()) -> InsightsPulse {
        InsightsCalculator.pulse(T.scope(input, context))
    }

    @Test("Empty input gives empty dials")
    func empty() {
        #expect(pulse(.empty) == .empty)
    }

    @Test("Consistency counts due habit-days done, this week and the week before")
    func consistency() {
        // The first record is on day -13, so both weeks are fully tracked.
        let habit = T.habit(doneOffsets: [-13, -12, -10, -6, -5, -3, -1])
        let result = pulse(InsightsInput(habits: [habit]))
        // Days -6...-1: done on -6, -5, -3 and -1. Today is not done yet, so it waits.
        #expect(result.consistency == InsightsRate(done: 4, total: 6))
        // Days -13...-7: done on -13, -12 and -10.
        #expect(result.previousConsistency == InsightsRate(done: 3, total: 7))
    }

    @Test("Today counts once it is done, never before")
    func todayGrace() {
        let doneToday = T.habit(doneOffsets: [-6, 0])
        let notYet = T.habit(doneOffsets: [-6])
        #expect(pulse(InsightsInput(habits: [doneToday])).consistency == InsightsRate(done: 2, total: 7))
        #expect(pulse(InsightsInput(habits: [notYet])).consistency == InsightsRate(done: 1, total: 6))
    }

    @Test("A negative habit is done on every day without a slip")
    func negativeHabit() {
        let habit = T.habit(type: .negative, doneOffsets: [-2])
        let result = pulse(InsightsInput(habits: [habit]))
        #expect(result.consistency == InsightsRate(done: 5, total: 6))
        #expect(result.previousConsistency == InsightsRate(done: 7, total: 7))
    }

    @Test("An archived habit counts up to the day it was archived")
    func archivedHabit() {
        let habit = T.habit(archivedOffset: -3, doneOffsets: [-6, -5, -4])
        // Due -6...-3 (the archive day still counts), done -6, -5 and -4.
        #expect(pulse(InsightsInput(habits: [habit])).consistency == InsightsRate(done: 3, total: 4))
    }

    @Test("Follow-through is done / (done + left undone), for both weeks")
    func followThrough() {
        let tasks = [
            T.task(completedOffset: -2),
            // Done late is still done.
            T.task(completedOffset: -1, dueOffset: -3),
            // Left undone.
            T.task(plannedOffsets: [-3]),
            // The last planned day (-2) decides, not the first one.
            T.task(plannedOffsets: [-9, -2]),
            // Due today: not left undone yet.
            T.task(dueOffset: 0),
            T.task(dueOffset: 2),
            T.task(),
            // The week before: one done, one left undone.
            T.task(completedOffset: -10),
            T.task(plannedOffsets: [-9]),
        ]
        let result = pulse(InsightsInput(tasks: tasks))
        #expect(result.followThrough == InsightsRate(done: 2, total: 4))
        #expect(result.previousFollowThrough == InsightsRate(done: 1, total: 2))
    }

    @Test("A day just outside the week belongs to the week before")
    func periodEdge() {
        let tasks = [T.task(completedOffset: -7), T.task(dueOffset: -7)]
        // The habit starts on day -7.
        let habit = T.habit(doneOffsets: [-7])
        let result = pulse(InsightsInput(habits: [habit], tasks: tasks))
        #expect(result.followThrough == .empty)
        #expect(result.previousFollowThrough == InsightsRate(done: 1, total: 2))
        #expect(result.previousConsistency == InsightsRate(done: 1, total: 1))
        #expect(result.consistency == InsightsRate(done: 0, total: 6))
    }

    @Test("Cancelled imports are skipped")
    func cancelledTasks() {
        let tasks = [
            T.task(createdDaysAgo: 5, completedOffset: -2, isCancelled: true),
            T.task(createdDaysAgo: 5, plannedOffsets: [-3], isCancelled: true),
        ]
        #expect(pulse(InsightsInput(tasks: tasks)) == .empty)
    }

    @Test("Active days start at the first record, and today waits until it is active")
    func activeDays() {
        let task = T.task(createdDaysAgo: 4, completedOffset: -2)
        let session = T.session(offset: -3, minutes: 30)
        let result = pulse(InsightsInput(tasks: [task], sessions: [session]))
        // Counted: -4...-1 (today is not active yet). Active: -3 (session) and -2 (task).
        #expect(result.activeDays == InsightsRate(done: 2, total: 4))
        #expect(result.previousActiveDays == .empty)

        let todaySession = T.session(offset: 0, hour: 9, minutes: 20)
        let withToday = pulse(InsightsInput(tasks: [task], sessions: [session, todaySession]))
        #expect(withToday.activeDays == InsightsRate(done: 3, total: 5))
    }

    @Test("A habit record makes a day active, a slip on a negative habit does not")
    func habitActivity() {
        let habit = T.habit(createdDaysAgo: 10, doneOffsets: [-5])
        let negative = T.habit(type: .negative, createdDaysAgo: 10, doneOffsets: [-4])
        let result = pulse(InsightsInput(habits: [habit, negative]))
        // The first record is the creation on day -10. Counted: -6...-1. Active: -5.
        #expect(result.activeDays == InsightsRate(done: 1, total: 6))
        // The week before: -10...-7 are counted, none is active.
        #expect(result.previousActiveDays == InsightsRate(done: 0, total: 4))
    }

    @Test("The week before counts every day from the first record")
    func previousActiveDays() {
        let task = T.task(createdDaysAgo: 9, completedOffset: -8)
        let result = pulse(InsightsInput(tasks: [task]))
        // -9...-7 are counted, -8 is active.
        #expect(result.previousActiveDays == InsightsRate(done: 1, total: 3))
        #expect(result.activeDays == InsightsRate(done: 0, total: 6))
    }

    @Test("A task done before it was created still makes its day active")
    func importedTask() {
        // An import created today for a task done on day -3.
        let task = T.task(createdDaysAgo: 0, completedOffset: -3)
        // Counted: -3...-1 (today is not active). Active: -3.
        #expect(pulse(InsightsInput(tasks: [task])).activeDays == InsightsRate(done: 1, total: 3))
    }

    @Test("A session with no tracked time is not a record")
    func emptySession() {
        let session = T.session(offset: -2, minutes: 0)
        #expect(pulse(InsightsInput(sessions: [session])).activeDays == .empty)
    }

    @Test("Every day of a month across a midnight DST change counts once")
    func havanaMonth() {
        let calendar = TestCalendar.havana
        // Today is 2026-03-12. The month runs 02-11...03-12 and holds
        // 03-08 (day -36), a day that starts at 01:00.
        let context = T.context(period: .month, today: T.day(-32, calendar: calendar), calendar: calendar)
        let habit = T.habit(createdDaysAgo: 61, doneOffsets: Array(-61 ... -32), calendar: calendar)
        let task = T.task(createdDaysAgo: 61, completedOffset: -36, calendar: calendar)
        let result = pulse(InsightsInput(habits: [habit], tasks: [task]), context)
        #expect(result.consistency == InsightsRate(done: 30, total: 30))
        #expect(result.activeDays == InsightsRate(done: 30, total: 30))
        #expect(result.followThrough == InsightsRate(done: 1, total: 1))
    }
}
