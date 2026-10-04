import Foundation
import Testing
import KadoCore

@Suite("HealthTimelineClipper")
struct HealthTimelineClippingTests {
    func date(_ calendar: Calendar, _ y: Int, _ m: Int, _ d: Int, _ h: Int, _ min: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }

    func entry(_ start: Date, _ end: Date) -> HealthTimelineEntry {
        HealthTimelineEntry(id: UUID(), kind: .sleep, interval: DateInterval(start: start, end: end))
    }

    @Test("Overnight sleep is split across both days")
    func overnightSplits() {
        let cal = TestCalendar.utc
        let sleep = entry(date(cal, 2026, 4, 13, 23, 30), date(cal, 2026, 4, 14, 7))
        let dayOne = HealthTimelineClipper.entries([sleep], on: date(cal, 2026, 4, 13, 12), calendar: cal)
        let dayTwo = HealthTimelineClipper.entries([sleep], on: date(cal, 2026, 4, 14, 12), calendar: cal)
        #expect(dayOne.map(\.interval) == [DateInterval(start: date(cal, 2026, 4, 13, 23, 30), end: date(cal, 2026, 4, 14, 0))])
        #expect(dayTwo.map(\.interval) == [DateInterval(start: date(cal, 2026, 4, 14, 0), end: date(cal, 2026, 4, 14, 7))])
        #expect(dayTwo.first?.id == sleep.id)
    }

    @Test("Entries outside the day or touching only its edge are dropped")
    func outsideDropped() {
        let cal = TestCalendar.utc
        let before = entry(date(cal, 2026, 4, 12, 22), date(cal, 2026, 4, 13, 0))
        let after = entry(date(cal, 2026, 4, 15, 1), date(cal, 2026, 4, 15, 2))
        #expect(HealthTimelineClipper.entries([before, after], on: date(cal, 2026, 4, 13, 12), calendar: cal).isEmpty)
    }

    @Test("Output is sorted by start")
    func sorted() {
        let cal = TestCalendar.utc
        let late = entry(date(cal, 2026, 4, 13, 18), date(cal, 2026, 4, 13, 19))
        let early = entry(date(cal, 2026, 4, 13, 7), date(cal, 2026, 4, 13, 8))
        let result = HealthTimelineClipper.entries([late, early], on: date(cal, 2026, 4, 13, 12), calendar: cal)
        #expect(result.map(\.id) == [early.id, late.id])
    }

    @Test("Query window reaches 12 hours past each edge of the day")
    func queryWindow() {
        let cal = TestCalendar.utc
        let window = HealthTimelineClipper.queryInterval(around: date(cal, 2026, 4, 13, 12), calendar: cal)
        #expect(window == DateInterval(start: date(cal, 2026, 4, 12, 12), end: date(cal, 2026, 4, 14, 12)))
    }

    @Test("Clipped entries stay inside the civil day across DST shapes",
          arguments: [
            (TestCalendar.paris, 2026, 3, 29),   // 23-hour day
            (TestCalendar.paris, 2026, 10, 25),  // 25-hour day
            (TestCalendar.havana, 2026, 3, 8),   // day starts at 01:00
          ])
    func dstInvariant(calendar: Calendar, year: Int, month: Int, day: Int) {
        let noon = date(calendar, year, month, day, 12)
        let dayInterval = calendar.dateInterval(of: .day, for: noon)!
        let spanning = entry(calendar.date(byAdding: .hour, value: -6, to: dayInterval.start)!,
                             calendar.date(byAdding: .hour, value: 6, to: dayInterval.end)!)
        let result = HealthTimelineClipper.entries([spanning], on: noon, calendar: calendar)
        #expect(result.count == 1)
        #expect(result.first?.interval == dayInterval)
        let window = HealthTimelineClipper.queryInterval(around: noon, calendar: calendar)!
        #expect(window.start < dayInterval.start && window.end > dayInterval.end)
    }
}
