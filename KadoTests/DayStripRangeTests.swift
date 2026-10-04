import Foundation
import Testing
import KadoCore

@Suite("DayStripRange")
struct DayStripRangeTests {
    @Test("No data: today through 60 days ahead")
    func noData() {
        let cal = TestCalendar.utc
        let today = TestCalendar.referenceDate
        let days = DayStripRange.days(from: nil, today: today, calendar: cal)
        #expect(days.count == 61)
        #expect(days.first == cal.startOfDay(for: today))
        #expect(days.last == cal.startOfDay(for: TestCalendar.day(60)))
    }

    @Test("Starts at the earliest day's midnight")
    func earliestInPast() {
        let cal = TestCalendar.utc
        let earliest = cal.date(byAdding: .hour, value: 3, to: TestCalendar.day(-3))!
        let days = DayStripRange.days(from: earliest, today: TestCalendar.referenceDate, calendar: cal)
        #expect(days.first == cal.startOfDay(for: TestCalendar.day(-3)))
        #expect(days.count == 64)
    }

    @Test("A future earliest date never moves the start past today")
    func earliestInFuture() {
        let cal = TestCalendar.utc
        let days = DayStripRange.days(from: TestCalendar.day(5), today: TestCalendar.referenceDate, calendar: cal)
        #expect(days.first == cal.startOfDay(for: TestCalendar.referenceDate))
    }

    @Test("Every day is a midnight, one calendar day apart, across DST", arguments: [
        (TestCalendar.paris, 2026, 10, 20, 2026, 10, 30),
        (TestCalendar.havana, 2026, 3, 4, 2026, 3, 12),
    ])
    func dstInvariant(_ cal: Calendar, _ y1: Int, _ m1: Int, _ d1: Int, _ y2: Int, _ m2: Int, _ d2: Int) {
        let earliest = TestCalendar.instant(cal, y1, m1, d1, 12)
        let today = TestCalendar.instant(cal, y2, m2, d2, 12)
        let days = DayStripRange.days(from: earliest, today: today, futureDays: 3, calendar: cal)
        let back = cal.ordinality(of: .day, in: .era, for: today)! - cal.ordinality(of: .day, in: .era, for: earliest)!
        #expect(days.count == back + 1 + 3)
        for day in days { #expect(day == cal.startOfDay(for: day)) }
        for (a, b) in zip(days, days.dropFirst()) {
            // `ordinality` counts calendar days; `dateComponents(.day)` between two
            // startOfDay values reads 0 across Havana's midnight DST jump.
            let ordA = cal.ordinality(of: .day, in: .era, for: a)!
            let ordB = cal.ordinality(of: .day, in: .era, for: b)!
            #expect(ordB - ordA == 1)
        }
    }

    @Test("Clamp returns the nearest end")
    func clamp() {
        let cal = TestCalendar.utc
        let days = DayStripRange.days(from: TestCalendar.day(-2), today: TestCalendar.referenceDate, futureDays: 2, calendar: cal)
        #expect(DayStripRange.clamp(TestCalendar.day(-10), to: days) == days.first)
        #expect(DayStripRange.clamp(TestCalendar.day(10), to: days) == days.last)
        #expect(DayStripRange.clamp(days[1], to: days) == days[1])
        #expect(DayStripRange.clamp(TestCalendar.day(0), to: []) == nil)
    }
}
