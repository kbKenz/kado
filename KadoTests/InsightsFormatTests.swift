import Foundation
import Testing
@testable import Kado
import KadoCore

/// The text the Insights cards put on numbers. Pinned locales, so the
/// results do not depend on the simulator's region.
@Suite("Insights formats")
@MainActor
struct InsightsFormatTests {
    private let us = Locale(identifier: "en_US")
    private let gb = Locale(identifier: "en_GB")

    @Test("Durations read in hours and minutes, never below zero")
    func durations() {
        #expect(InsightsFormat.duration(12 * 3_600 + 40 * 60, locale: us) == "12h 40m")
        #expect(InsightsFormat.duration(7 * 3_600, locale: us) == "7h")
        #expect(InsightsFormat.duration(0, locale: us) == "0m")
        #expect(InsightsFormat.duration(-90, locale: us) == "0m")
    }

    @Test("Percents round to whole numbers, and a rate with no chance has none")
    func percents() {
        #expect(InsightsFormat.percent(0.8187, locale: us) == "82%")
        #expect(InsightsFormat.percent(InsightsRate(done: 3, total: 4), locale: us) == "75%")
        #expect(InsightsFormat.percent(InsightsRate.empty, locale: us) == nil)
    }

    @Test("A point change compares the percents as shown")
    func pointChanges() {
        // 141 / 172 shows 82%, 129 / 170 shows 76%.
        let current = InsightsRate(done: 141, total: 172)
        #expect(InsightsFormat.pointChange(current, from: InsightsRate(done: 129, total: 170)) == .up(6))
        // 25 / 39 shows 64%, 24 / 36 shows 67%.
        #expect(InsightsFormat.pointChange(InsightsRate(done: 25, total: 39), from: InsightsRate(done: 24, total: 36)) == .down(3))
        #expect(InsightsFormat.pointChange(InsightsRate(done: 27, total: 30), from: InsightsRate(done: 9, total: 10)) == .same)
    }

    @Test("A point change needs a total on both sides")
    func pointChangeWithoutData() {
        let current = InsightsRate(done: 3, total: 4)
        #expect(InsightsFormat.pointChange(current, from: .empty) == .noEarlierData)
        #expect(InsightsFormat.pointChange(.empty, from: current) == .noData)
        #expect(InsightsFormat.pointChange(.empty, from: .empty) == .noData)
    }

    @Test("Durations less than a minute apart count as the same")
    func durationChanges() {
        #expect(InsightsFormat.durationChange(3_630, from: 3_600) == .same)
        #expect(InsightsFormat.durationChange(7_200, from: 3_600) == .more(3_600.0))
        #expect(InsightsFormat.durationChange(1_800, from: 3_600) == .less(1_800.0))
    }

    @Test("A plan ratio within 5% is on plan")
    func planDrift() {
        #expect(InsightsFormat.planDrift(1.0) == .onPlan)
        #expect(InsightsFormat.planDrift(1.04) == .onPlan)
        #expect(InsightsFormat.planDrift(0.96) == .onPlan)
        #expect(InsightsFormat.planDrift(1.5) == .longer(0.5))
        #expect(InsightsFormat.planDrift(0.75) == .shorter(0.25))
    }

    @Test("Minutes after midnight read as a time in the calendar's zone")
    func times() {
        #expect(InsightsFormat.time(minutesAfterMidnight: 23 * 60 + 10, calendar: TestCalendar.utc, locale: gb) == "23:10")
        #expect(InsightsFormat.time(minutesAfterMidnight: 22 * 60 + 45, calendar: TestCalendar.paris, locale: gb) == "22:45")
        // Zero-padding of the hour is up to the system's pattern.
        #expect(InsightsFormat.time(minutesAfterMidnight: 6 * 60 + 40, calendar: TestCalendar.paris, locale: gb).hasSuffix("6:40"))
        // Havana's day can start at 01:00; 1 January has no clock change.
        #expect(InsightsFormat.time(minutesAfterMidnight: 0, calendar: TestCalendar.havana, locale: gb).hasSuffix("0:00"))
        #expect(InsightsFormat.time(minutesAfterMidnight: 24 * 60 + 5, calendar: TestCalendar.utc, locale: gb) == "23:59")
    }

    @Test("Days to finish keep one decimal")
    func days() {
        #expect(InsightsFormat.days(2.44, locale: us) == "2.4")
        #expect(InsightsFormat.days(1, locale: us) == "1.0")
    }
}
