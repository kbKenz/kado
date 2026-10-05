import Foundation
import Testing
@testable import KadoCore

@Suite("Insights rhythm")
struct InsightsRhythmTests {
    typealias T = InsightsTestSupport

    private func calculate(_ input: InsightsInput, _ context: InsightsContext = T.context()) -> InsightsRhythm {
        InsightsCalculator.rhythm(T.scope(input, context))
    }

    @Test("Empty input: seven empty weekdays from the calendar's first day, four empty parts of the day")
    func empty() {
        let rhythm = calculate(.empty)
        #expect(rhythm.weekdays == Weekday.week(startingOn: 1).map { InsightsWeekdayRate(weekday: $0, rate: .empty) })
        #expect(rhythm.bestWeekday == nil)
        #expect(rhythm.focusByPartOfDay == InsightsPartOfDay.allCases.map { InsightsPartOfDayFocus(part: $0, seconds: 0) })
        #expect(rhythm.peakPartOfDay == nil)
    }

    @Test("The weekdays start on the calendar's first weekday")
    func weekOrder() {
        let rhythm = calculate(.empty, T.context(calendar: TestCalendar.utc(firstWeekday: 2)))
        #expect(rhythm.weekdays.map(\.weekday) == [.monday, .tuesday, .wednesday, .thursday, .friday, .saturday, .sunday])
    }

    @Test("Each weekday tallies the due days of every habit; today counts only once done")
    func weekdayTallies() {
        // Day 0 is a Monday, so the week runs from Tuesday (day -6) to Monday.
        let walk = T.habit("Walk", doneOffsets: [-6, -5, -3, -1])
        let read = T.habit("Read", doneOffsets: [-6, -4])
        let stretch = T.habit("Stretch", doneOffsets: [0])
        let rhythm = calculate(InsightsInput(habits: [walk, read, stretch]))
        #expect(rhythm.weekdays.map(\.rate) == [
            InsightsRate(done: 1, total: 2), // Sunday
            InsightsRate(done: 1, total: 1), // Monday (today): only the habit already done
            InsightsRate(done: 2, total: 2), // Tuesday
            InsightsRate(done: 1, total: 2), // Wednesday
            InsightsRate(done: 1, total: 2), // Thursday
            InsightsRate(done: 1, total: 2), // Friday
            InsightsRate(done: 0, total: 2), // Saturday
        ])
        // No best weekday over a single week.
        #expect(rhythm.bestWeekday == nil)
    }

    @Test("Best weekday: the highest share; ties go to the day that comes first in the week")
    func bestWeekdayTies() {
        // Days -29...0 run from a Sunday to a Monday (today, not done yet).
        // Every Sunday and every past Monday is done: both are at 100%.
        let habit = T.habit(doneOffsets: [-29, -22, -15, -8, -1, -28, -21, -14, -7])
        let input = InsightsInput(habits: [habit])
        let sundayFirst = calculate(input, T.context(period: .month))
        #expect(sundayFirst.bestWeekday == .sunday)
        #expect(sundayFirst.weekdays.first { $0.weekday == .monday }?.rate == InsightsRate(done: 4, total: 4))
        let mondayFirst = calculate(input, T.context(period: .month, calendar: TestCalendar.utc(firstWeekday: 2)))
        #expect(mondayFirst.bestWeekday == .monday)
    }

    @Test("A weekday needs at least two due habit-days to be the best")
    func bestWeekdayNeedsTwoDueDays() {
        // The first record is on day -3, a Friday: Friday, Saturday and
        // Sunday have one due day each.
        let walk = T.habit("Walk", doneOffsets: [-3, -1])
        #expect(calculate(InsightsInput(habits: [walk]), T.context(period: .month)).bestWeekday == nil)
        // A second habit done on Sunday gives Sunday two due days.
        let read = T.habit("Read", doneOffsets: [-1])
        #expect(calculate(InsightsInput(habits: [walk, read]), T.context(period: .month)).bestWeekday == .sunday)
    }

    @Test("Best weekday also over a quarter")
    func bestWeekdayQuarter() {
        // Every Tuesday of the quarter is done, nothing else.
        let tuesdays = stride(from: -6, through: -89, by: -7).map { $0 }
        let habit = T.habit(createdDaysAgo: 120, doneOffsets: tuesdays + [-97])
        let rhythm = calculate(InsightsInput(habits: [habit]), T.context(period: .quarter))
        #expect(rhythm.bestWeekday == .tuesday)
        #expect(rhythm.weekdays.first { $0.weekday == .tuesday }?.rate == InsightsRate(done: 12, total: 12))
    }

    @Test("An archived habit still counts on its days before the archive, never outside the period")
    func archived() {
        // Done every day from day -31 to its archive on day -24; only
        // days -29...-24 are in the period.
        let old = T.habit("Old", archivedOffset: -24, doneOffsets: Array(-31 ... -24))
        let rhythm = calculate(InsightsInput(habits: [old]), T.context(period: .month))
        #expect(rhythm.weekdays.reduce(0) { $0 + $1.rate.total } == 6)
        #expect(rhythm.weekdays.reduce(0) { $0 + $1.rate.done } == 6)
    }

    @Test("Focus by part of the day, by the hour each session of the period started")
    func partsOfDay() {
        let input = InsightsInput(sessions: [
            T.session(offset: -5, hour: 5, minutes: 60),               // morning
            T.session(offset: -4, hour: 11, minute: 30, minutes: 30),  // morning
            T.session(offset: -3, hour: 13, minutes: 45),              // afternoon
            T.session(offset: -2, hour: 18, minutes: 20),              // evening
            T.session(offset: -2, hour: 23, minutes: 50),              // night
            T.session(offset: -1, hour: 4, minutes: 10),               // night
            T.session(offset: -7, hour: 6, minutes: 500),              // before the period
        ])
        let rhythm = calculate(input)
        #expect(rhythm.focusByPartOfDay == [
            InsightsPartOfDayFocus(part: .morning, seconds: 90.0 * 60),
            InsightsPartOfDayFocus(part: .afternoon, seconds: 45.0 * 60),
            InsightsPartOfDayFocus(part: .evening, seconds: 20.0 * 60),
            InsightsPartOfDayFocus(part: .night, seconds: 60.0 * 60),
        ])
        #expect(rhythm.peakPartOfDay == .morning)
    }

    @Test("A session before the day-start hour counts on the day before, by its wall-clock hour")
    func dayStartHour() {
        // Days start at 04:00. 02:00 on day -6 is still day -7, outside
        // the period; 02:00 on day -5 is day -6, inside it.
        let input = InsightsInput(sessions: [
            T.session(offset: -6, hour: 2, minutes: 40),
            T.session(offset: -5, hour: 2, minutes: 30),
        ])
        let rhythm = calculate(input, T.context(startHour: 4))
        #expect(rhythm.focusByPartOfDay.first { $0.part == .night }?.seconds == 30.0 * 60)
        #expect(rhythm.focusByPartOfDay.reduce(0) { $0 + $1.seconds } == 30.0 * 60)
    }

    @Test("Peak part of the day: needs three sessions; ties go to the earlier part")
    func peak() {
        let two = InsightsInput(sessions: [
            T.session(offset: -2, hour: 9, minutes: 60),
            T.session(offset: -1, hour: 9, minutes: 60),
        ])
        #expect(calculate(two).peakPartOfDay == nil)
        let tie = InsightsInput(sessions: [
            T.session(offset: -3, hour: 22, minutes: 30), // night
            T.session(offset: -2, hour: 14, minutes: 30), // afternoon
            T.session(offset: -1, hour: 19, minutes: 10), // evening
        ])
        #expect(calculate(tie).peakPartOfDay == .afternoon)
    }

    @Test("Havana: the midnight DST day still counts as a Sunday")
    func havana() {
        let calendar = TestCalendar.havana
        // Day -36 is Sunday 2026-03-08, when Havana's clock skips from
        // 00:00 to 01:00; day -32 is Thursday 2026-03-12, today.
        let habit = T.habit(doneOffsets: [-36, -34], calendar: calendar)
        let session = InsightsSession(
            id: UUID(),
            session: WorkSession(
                startedAt: TestCalendar.instant(calendar, 2026, 3, 8, 10),
                endedAt: TestCalendar.instant(calendar, 2026, 3, 8, 10, 30)
            ),
            category: .work
        )
        let context = T.context(today: T.day(-32, calendar: calendar), calendar: calendar)
        let rhythm = InsightsCalculator.rhythm(T.scope(InsightsInput(habits: [habit], sessions: [session]), context))
        // Havana's test calendar starts the week on Monday.
        #expect(rhythm.weekdays.map(\.weekday) == [.monday, .tuesday, .wednesday, .thursday, .friday, .saturday, .sunday])
        #expect(rhythm.weekdays.map(\.rate) == [
            InsightsRate(done: 0, total: 1), // Monday 9
            InsightsRate(done: 1, total: 1), // Tuesday 10
            InsightsRate(done: 0, total: 1), // Wednesday 11
            .empty,                          // Thursday 12, today, not done yet
            .empty,                          // Friday 6, before the first record
            .empty,                          // Saturday 7, before the first record
            InsightsRate(done: 1, total: 1), // Sunday 8
        ])
        #expect(rhythm.focusByPartOfDay.first { $0.part == .morning }?.seconds == 1800.0)
    }
}
