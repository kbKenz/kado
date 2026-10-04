import Foundation
import KadoCore
import Testing

@Suite("Task schedule draft")
struct TaskScheduleDraftTests {
    private let calendar = TestCalendar.utc

    @Test("Each optional time is preserved independently", arguments: [(false, false), (true, false), (false, true), (true, true)])
    func optionalTimes(flags: (Bool, Bool)) throws {
        let day = TestCalendar.referenceDate
        let start = TestCalendar.instant(calendar, 2026, 4, 1, 9, 15)
        let end = TestCalendar.instant(calendar, 2026, 5, 12, 10, 45)
        let normalized = try TaskScheduleDraft(
            title: "  Meet Thomas \n", day: day,
            startTime: flags.0 ? start : nil, endTime: flags.1 ? end : nil
        ).normalized(using: calendar)
        #expect(normalized.title == "Meet Thomas")
        #expect(normalized.plannedDay == calendar.startOfDay(for: day))
        #expect(normalized.startAt == (flags.0 ? TestCalendar.instant(calendar, 2026, 4, 13, 9, 15) : nil))
        #expect(normalized.endAt == (flags.1 ? TestCalendar.instant(calendar, 2026, 4, 13, 10, 45) : nil))
    }

    @Test("An inbox task creates no day or time")
    func undatedTask() throws {
        let result = try TaskScheduleDraft(title: "Buy groceries").normalized(using: calendar)
        #expect(result.plannedDay == nil)
        #expect(result.startAt == nil)
        #expect(result.endAt == nil)
    }

    @Test("A clock time requires a selected day")
    func missingDay() {
        #expect(throws: TaskScheduleDraft.ValidationError.dayRequired) {
            try TaskScheduleDraft(title: "Meet Thomas", startTime: TestCalendar.referenceDate).normalized(using: calendar)
        }
    }

    @Test("Whitespace is not a task title")
    func emptyTitle() {
        #expect(throws: TaskScheduleDraft.ValidationError.emptyTitle) {
            try TaskScheduleDraft(title: " \n ").normalized(using: calendar)
        }
    }

    @Test("Equal and reversed bounds are rejected", arguments: [9, 10])
    func invalidRange(endHour: Int) {
        let day = TestCalendar.referenceDate
        let start = TestCalendar.instant(calendar, 2026, 4, 13, 10)
        let end = TestCalendar.instant(calendar, 2026, 4, 13, endHour)
        #expect(throws: TaskScheduleDraft.ValidationError.endMustFollowStart) {
            try TaskScheduleDraft(title: "Meet Thomas", day: day, startTime: start, endTime: end).normalized(using: calendar)
        }
    }

    @Test("Day normalization survives midnight DST transitions")
    func midnightTransition() throws {
        let calendar = TestCalendar.havana
        let day = TestCalendar.instant(calendar, 2026, 3, 8, 12)
        let start = TestCalendar.instant(calendar, 2026, 3, 7, 9, 30)
        let result = try TaskScheduleDraft(title: "Walk", day: day, startTime: start).normalized(using: calendar)
        #expect(result.plannedDay == calendar.startOfDay(for: day))
        #expect(result.startAt == TestCalendar.instant(calendar, 2026, 3, 8, 9, 30))
        #expect(result.endAt == nil)
    }

    @Test("Unavailable DST clock time is rejected instead of moved")
    func nonexistentClockTime() {
        let calendar = TestCalendar.paris
        let day = TestCalendar.instant(calendar, 2026, 3, 29, 12)
        let clock = TestCalendar.instant(calendar, 2026, 3, 28, 2, 30)
        #expect(throws: TaskScheduleDraft.ValidationError.timeUnavailableOnDay) {
            try TaskScheduleDraft(title: "Read", day: day, startTime: clock).normalized(using: calendar)
        }
    }
}
