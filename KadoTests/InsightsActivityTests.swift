import Foundation
import Testing
@testable import KadoCore

@Suite("Insights activity")
struct InsightsActivityTests {
    typealias T = InsightsTestSupport

    private func activity(_ input: InsightsInput, _ context: InsightsContext = T.context()) -> InsightsActivity {
        InsightsCalculator.activity(T.scope(input, context))
    }

    /// The cell of the day `offset` days from the reference day.
    private func cell(_ activity: InsightsActivity, _ offset: Int) throws -> InsightsActivityDay {
        try #require(activity.days.first { $0.date == T.day(offset) })
    }

    /// The habit fractions of the cells in the period, oldest first.
    private func fractions(_ activity: InsightsActivity) -> [Double?] {
        activity.days.filter(\.isInPeriod).map(\.habitFraction)
    }

    @Test("Cells run from the start of the first week to today")
    func cellLayout() {
        // The week runs from Tuesday (-6) to Monday (0). The calendar's
        // weeks start on Sunday, so the first cell is day -8.
        let result = activity(.empty)
        #expect(result.days.map(\.date) == (-8 ... 0).map { T.day($0) })
        #expect(result.days.map(\.isInPeriod) == [false, false] + Array(repeating: true, count: 7))
        #expect(result.days.allSatisfy { $0.habitFraction == nil && $0.tasksDone == 0 && $0.focusSeconds == 0.0 })
        #expect(result.perfectDays == 0)
        #expect(result.longestPerfectRun == 0)
    }

    @Test("The first week starts on the calendar's first weekday")
    func weekStart() {
        let monday = TestCalendar.utc(firstWeekday: 2)
        let week = activity(.empty, T.context(calendar: monday))
        #expect(week.days.map(\.date) == (-7 ... 0).map { T.day($0, calendar: monday) })
        #expect(week.days.map(\.isInPeriod) == [false] + Array(repeating: true, count: 7))
        // The month starts on Sunday 2026-03-15: no padding.
        let month = activity(.empty, T.context(period: .month))
        #expect(month.days.count == 30)
        #expect(month.days.allSatisfy { $0.isInPeriod })
    }

    @Test("A day's fraction is due habits done over due habits")
    func habitFraction() {
        // Both habits start on day -10, before the week.
        let first = T.habit("A", doneOffsets: [-10, -6, -5, -3, -2, -1])
        let second = T.habit("B", doneOffsets: [-10, -6, -3, -1])
        let result = activity(InsightsInput(habits: [first, second]))
        // Padding -8 and -7, then -6...-1, then today with nothing done yet.
        #expect(result.days.map(\.habitFraction) == [0.0, 0.0, 1.0, 0.5, 0.0, 1.0, 0.5, 1.0, 0.0])
        #expect(result.perfectDays == 3)
        #expect(result.longestPerfectRun == 1)
    }

    @Test("Today shows what is done so far: no grace day")
    func todayPartlyDone() throws {
        let read = T.habit("Read", doneOffsets: [-3, 0])
        // Half of the target, on day -3 and today.
        let water = T.habit("Water", type: .counter(target: 8), doneOffsets: [-3, 0], value: 4)
        // A negative habit never counts today.
        let smoke = T.habit("Smoke", type: .negative)
        let result = activity(InsightsInput(habits: [read, water, smoke]))
        // Read is done today, Water is not: 1 of 2.
        #expect(try cell(result, 0).habitFraction == 0.5)
        #expect(result.perfectDays == 3)
    }

    @Test("Today with only a negative habit has nothing due")
    func todayNegativeOnly() throws {
        let smoke = T.habit("Smoke", type: .negative, doneOffsets: [-2])
        let result = activity(InsightsInput(habits: [smoke]))
        #expect(try cell(result, 0).habitFraction == nil)
        #expect(fractions(result) == [1.0, 1.0, 1.0, 1.0, 0.0, 1.0, nil])
        #expect(result.perfectDays == 5)
        #expect(result.longestPerfectRun == 4)
    }

    @Test("A day with nothing due neither breaks nor extends a run")
    func restDays() {
        // Due on Monday, Wednesday and Friday; day -12 is a Wednesday.
        // The week: Tue -6, Wed -5, Thu -4, Fri -3, Sat -2, Sun -1, Mon 0.
        let habit = T.habit(frequency: .specificDays([.monday, .wednesday, .friday]), doneOffsets: [-12, -5, -3, 0])
        let result = activity(InsightsInput(habits: [habit]))
        #expect(fractions(result) == [nil, 1.0, nil, 1.0, nil, nil, 1.0])
        #expect(result.perfectDays == 3)
        #expect(result.longestPerfectRun == 3)
    }

    @Test("A day partly done breaks the run")
    func brokenRun() {
        let habit = T.habit(doneOffsets: [-10, -6, -5, -3, -2, -1])
        let result = activity(InsightsInput(habits: [habit]))
        // Perfect: -6, -5 | missed: -4 | perfect: -3, -2, -1 | today: not done yet.
        #expect(result.perfectDays == 5)
        #expect(result.longestPerfectRun == 3)
    }

    @Test("Cells count tasks done that civil day and focus started that logical day")
    func tasksAndFocus() throws {
        let tasks = [
            T.task(completedOffset: -2),
            T.task(completedOffset: -2),
            T.task(completedOffset: -1),
            T.task(completedOffset: -2, isCancelled: true),
        ]
        let open = InsightsSession(id: UUID(), session: WorkSession(startedAt: T.time(0, 17)), category: .work)
        let sessions = [
            T.session(offset: -2, hour: 10, minutes: 30),
            // Runs past midnight and stays on the day it started.
            T.session(offset: -2, hour: 23, minute: 30, minutes: 60),
            // No tracked time.
            T.session(offset: -1, minutes: 0),
            // Open since 17:00; now is 18:00.
            open,
        ]
        let result = activity(InsightsInput(tasks: tasks, sessions: sessions))
        #expect(try cell(result, -2).tasksDone == 2)
        #expect(try cell(result, -1).tasksDone == 1)
        #expect(try cell(result, -2).focusSeconds == 5400.0)
        #expect(try cell(result, -1).focusSeconds == 0.0)
        #expect(try cell(result, 0).focusSeconds == 3600.0)
    }

    @Test("Sessions follow the day start hour, tasks keep their civil day")
    func dayStartHour() throws {
        let task = InsightsTask(id: UUID(), title: "Late", category: .other, createdAt: T.time(-5, 8), completedAt: T.time(-1, 2))
        let session = T.session(offset: -1, hour: 2, minutes: 30)
        let result = activity(InsightsInput(tasks: [task], sessions: [session]), T.context(startHour: 4))
        #expect(try cell(result, -2).focusSeconds == 1800.0)
        #expect(try cell(result, -1).focusSeconds == 0.0)
        #expect(try cell(result, -1).tasksDone == 1)
    }

    @Test("Padding cells are outside the period and never perfect")
    func paddingCells() throws {
        let habit = T.habit(doneOffsets: [-8, -7])
        let result = activity(InsightsInput(habits: [habit]))
        let padding = try cell(result, -7)
        #expect(padding.isInPeriod == false)
        #expect(padding.habitFraction == 1.0)
        #expect(result.perfectDays == 0)
        #expect(result.longestPerfectRun == 0)
    }

    @Test("An archived habit stops counting after its archive day")
    func archivedHabit() {
        let habit = T.habit(archivedOffset: -3, doneOffsets: [-10, -6, -5, -4])
        let result = activity(InsightsInput(habits: [habit]))
        #expect(fractions(result) == [1.0, 1.0, 1.0, 0.0, nil, nil, nil])
        #expect(result.perfectDays == 3)
        #expect(result.longestPerfectRun == 3)
    }

    @Test("Cells stay true day starts across a midnight DST change")
    func havanaMonth() {
        let calendar = TestCalendar.havana
        // Today is Thursday 2026-03-12 (day -32). The month starts on
        // Wednesday 02-11 (-61), its week on Monday 02-09 (-63), and it
        // holds 03-08 (-36), a day that starts at 01:00.
        let context = T.context(period: .month, today: T.day(-32, calendar: calendar), calendar: calendar)
        let habit = T.habit(createdDaysAgo: 70, doneOffsets: Array(-63 ... -32), calendar: calendar)
        let result = activity(InsightsInput(habits: [habit]), context)
        #expect(result.days.map(\.date) == (-63 ... -32).map { T.day($0, calendar: calendar) })
        #expect(result.days.filter(\.isInPeriod).count == 30)
        #expect(result.perfectDays == 30)
        #expect(result.longestPerfectRun == 30)
    }
}
