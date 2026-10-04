import Foundation
import Testing
@testable import Kado

/// What "Add start time" / "Add end time" fill in, and the Today /
/// Tomorrow shortcuts. A time is stored as hour and minute on the
/// planned day (`TaskScheduleDraft`), so a default must never cross
/// midnight: 23:30 + 1 h would come back as 00:30, before the start.
@Suite("ScheduleDefaults")
struct ScheduleDefaultsTests {
    let cal = TestCalendar.utc

    func at(_ day: Date, _ hour: Int, _ minute: Int = 0, calendar: Calendar? = nil) -> Date {
        let calendar = calendar ?? cal
        return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: calendar.startOfDay(for: day))!
    }

    func clock(_ date: Date, calendar: Calendar? = nil) -> [Int] {
        let parts = (calendar ?? cal).dateComponents([.hour, .minute], from: date)
        return [parts.hour!, parts.minute!]
    }

    // MARK: - Start

    @Test("A later day starts at 09:00")
    func laterDayStartsAtNine() {
        let start = ScheduleDefaults.startTime(on: TestCalendar.day(2), now: TestCalendar.referenceDate, calendar: cal)
        #expect(clock(start) == [9, 0])
        #expect(cal.isDate(start, inSameDayAs: TestCalendar.day(2)))
    }

    @Test("Today starts at the next full hour")
    func todayStartsNextHour() {
        let now = at(TestCalendar.day(0), 14, 20)
        let start = ScheduleDefaults.startTime(on: TestCalendar.day(0), now: now, calendar: cal)
        #expect(clock(start) == [15, 0])
    }

    @Test("Today on the hour still moves to the next hour")
    func todayOnTheHour() {
        let now = at(TestCalendar.day(0), 14)
        #expect(clock(ScheduleDefaults.startTime(on: TestCalendar.day(0), now: now, calendar: cal)) == [15, 0])
    }

    @Test("Late tonight caps the start at 23:00")
    func lateTonightCaps() {
        let now = at(TestCalendar.day(0), 23, 30)
        let start = ScheduleDefaults.startTime(on: TestCalendar.day(0), now: now, calendar: cal)
        #expect(clock(start) == [23, 0])
        #expect(cal.isDate(start, inSameDayAs: TestCalendar.day(0)))
    }

    // MARK: - Nearest quarter hour

    @Test("Now rounds to the nearest quarter hour", arguments: [
        (15, 33, [15, 30]), (15, 37, [15, 30]), (15, 38, [15, 45]),
        (15, 0, [15, 0]), (15, 53, [16, 0]), (0, 5, [0, 0]),
    ])
    func nearestQuarterHour(hour: Int, minute: Int, expected: [Int]) {
        let now = at(TestCalendar.day(0), hour, minute)
        let start = ScheduleDefaults.nearestQuarterHour(to: now, calendar: cal)
        #expect(clock(start) == expected)
        #expect(cal.isDate(start, inSameDayAs: now))
    }

    @Test("Just before midnight stays on the same day at 23:45")
    func nearestQuarterHourBeforeMidnight() {
        let now = at(TestCalendar.day(0), 23, 55)
        let start = ScheduleDefaults.nearestQuarterHour(to: now, calendar: cal)
        #expect(clock(start) == [23, 45])
        #expect(cal.isDate(start, inSameDayAs: now))
    }

    // MARK: - End

    @Test("End is one hour after the start")
    func endFollowsStart() {
        let start = at(TestCalendar.day(1), 10, 15)
        let end = ScheduleDefaults.endTime(on: TestCalendar.day(1), start: start, now: TestCalendar.referenceDate, calendar: cal)
        #expect(clock(end) == [11, 15])
    }

    @Test("Without a start, end is one hour after the default start")
    func endWithoutStart() {
        let end = ScheduleDefaults.endTime(on: TestCalendar.day(2), start: nil, now: TestCalendar.referenceDate, calendar: cal)
        #expect(clock(end) == [10, 0])
    }

    @Test("End never crosses midnight", arguments: [(23, 0), (23, 30), (22, 59)])
    func endCapsBeforeMidnight(hour: Int, minute: Int) {
        let start = at(TestCalendar.day(1), hour, minute)
        let end = ScheduleDefaults.endTime(on: TestCalendar.day(1), start: start, now: TestCalendar.referenceDate, calendar: cal)
        #expect(cal.isDate(end, inSameDayAs: TestCalendar.day(1)))
        #expect(end > start)
    }

    @Test("End stays one hour after the start across a spring-forward night")
    func endAcrossDST() {
        let paris = TestCalendar.paris
        let springForward = paris.date(from: DateComponents(year: 2026, month: 3, day: 29))!
        let start = at(springForward, 1, 30, calendar: paris)
        let end = ScheduleDefaults.endTime(on: springForward, start: start, now: springForward, calendar: paris)
        #expect(end.timeIntervalSince(start) == 3600.0)
        #expect(paris.isDate(end, inSameDayAs: springForward))
    }

    // MARK: - Quick days

    @Test("Today and Tomorrow are the starts of consecutive days")
    func quickDays() {
        let picks = ScheduleDefaults.quickDays(today: TestCalendar.referenceDate, calendar: cal)
        #expect(picks.today == cal.startOfDay(for: TestCalendar.day(0)))
        #expect(picks.tomorrow == cal.startOfDay(for: TestCalendar.day(1)))
    }

    @Test("Tomorrow is a whole calendar day, even when the night is 23 hours")
    func tomorrowAcrossDST() {
        let paris = TestCalendar.paris
        let saturday = paris.date(from: DateComponents(year: 2026, month: 3, day: 28, hour: 12))!
        let picks = ScheduleDefaults.quickDays(today: saturday, calendar: paris)
        #expect(paris.component(.day, from: picks.tomorrow) == 29)
        #expect(picks.tomorrow == paris.startOfDay(for: picks.tomorrow))
    }
}
