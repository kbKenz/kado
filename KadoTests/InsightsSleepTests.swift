import Foundation
import Testing
@testable import KadoCore

@Suite("Insights sleep")
struct InsightsSleepTests {
    typealias T = InsightsTestSupport

    private func calculate(_ input: InsightsInput, _ context: InsightsContext = T.context()) -> InsightsSleep {
        InsightsCalculator.sleep(T.scope(input, context))
    }

    /// A sleep interval from `startOffset` at `startHour:startMinute`
    /// to `endOffset` at `endHour:endMinute`.
    private func interval(
        _ startOffset: Int, _ startHour: Int, _ startMinute: Int = 0,
        to endOffset: Int, _ endHour: Int, _ endMinute: Int = 0
    ) -> DateInterval {
        DateInterval(start: T.time(startOffset, startHour, startMinute), end: T.time(endOffset, endHour, endMinute))
    }

    private func connected(_ sleep: [DateInterval]) -> InsightsInput {
        InsightsInput(health: InsightsHealth(isConnected: true, sleep: sleep))
    }

    @Test("Without Health: not connected, no nights, no figures")
    func disconnected() {
        let sleep = calculate(.empty)
        #expect(!sleep.isHealthConnected)
        #expect(sleep.nights.isEmpty)
        #expect(sleep.averageDuration == nil)
        #expect(sleep.previousAverageDuration == nil)
        #expect(sleep.nightsOverSevenHours == .empty)
        #expect(sleep.bedtimeConsistency == .empty)
        #expect(sleep.medianBedtimeMinutes == nil)
        #expect(sleep.medianWakeMinutes == nil)
        #expect(sleep.habits.isEmpty)
    }

    @Test("Connected with no sleep yet: connected, still no nights")
    func connectedWithoutData() {
        let sleep = calculate(connected([]))
        #expect(sleep.isHealthConnected)
        #expect(sleep.nights.isEmpty)
        #expect(sleep.averageDuration == nil)
        #expect(sleep.medianBedtimeMinutes == nil)
    }

    @Test("Nights, average, 7-hour nights, median bedtime and wake time")
    func mainRule() {
        let sleep = calculate(connected([
            interval(-7, 23, to: -6, 7),         // 8 h, bedtime 23:00
            interval(-5, 1, to: -5, 7, 30),      // 6 h 30, bedtime 01:00
            interval(-5, 22, 30, to: -4, 6),     // 7 h 30, bedtime 22:30
            interval(-4, 14, to: -4, 15, 30),    // a 1 h 30 nap: not a night
            interval(-4, 23, 30, to: -3, 8),     // 8 h 30, bedtime 23:30
            interval(-3, 13, to: -3, 16),        // 3 h on the same wake day: the longer one wins
        ]))
        #expect(sleep.nights.map(\.day) == [T.day(-6), T.day(-5), T.day(-4), T.day(-3)])
        #expect(sleep.nights.map(\.duration) == [8.0, 6.5, 7.5, 8.5].map { $0 * 3600 })
        #expect(sleep.averageDuration == 7.625 * 3600)
        #expect(sleep.nightsOverSevenHours == InsightsRate(done: 3, total: 4))
        // Shifted bedtimes are 630, 660, 690 and 780: the median is 675, so 23:15.
        #expect(sleep.medianBedtimeMinutes == 23 * 60 + 15)
        // 01:00 is 105 minutes after the median; the three others are within 45.
        #expect(sleep.bedtimeConsistency == InsightsRate(done: 3, total: 4))
        // Wake times 06:00, 07:00, 07:30 and 08:00: the median is 07:15.
        #expect(sleep.medianWakeMinutes == 7 * 60 + 15)
    }

    @Test("A night needs at least 2 hours, and nights come out oldest first")
    func twoHourMinimum() {
        let sleep = calculate(connected([
            interval(-1, 1, to: -1, 3),          // exactly 2 h: a night
            interval(-3, 23, to: -2, 0, 59),     // 1 h 59: not a night
            interval(-5, 23, to: -4, 7),         // given last, still first
        ]))
        #expect(sleep.nights.map(\.day) == [T.day(-4), T.day(-1)])
    }

    @Test("An odd count takes the middle value")
    func oddMedian() {
        let sleep = calculate(connected([
            interval(-4, 22, to: -3, 6),
            interval(-3, 23, to: -2, 7),
            interval(-1, 0, 15, to: -1, 9),
        ]))
        #expect(sleep.medianBedtimeMinutes == 23 * 60)
        #expect(sleep.medianWakeMinutes == 7 * 60)
        #expect(sleep.bedtimeConsistency == InsightsRate(done: 1, total: 3))
    }

    @Test("An even count takes the mean of the two middle values, rounded down")
    func evenMedianRoundsDown() {
        let sleep = calculate(connected([
            interval(-3, 23, 0, to: -2, 7, 0),
            interval(-2, 23, 1, to: -1, 7, 1),
        ]))
        #expect(sleep.medianBedtimeMinutes == 23 * 60)
        #expect(sleep.medianWakeMinutes == 7 * 60)
    }

    @Test("Bedtimes on both sides of midnight have a median at midnight, not at noon")
    func medianAcrossMidnight() {
        let sleep = calculate(connected([
            interval(-3, 23, 30, to: -2, 7),
            interval(-1, 0, 30, to: -1, 8),
        ]))
        #expect(sleep.medianBedtimeMinutes == 0)
        #expect(sleep.bedtimeConsistency == InsightsRate(done: 2, total: 2))
    }

    @Test("A night belongs to its wake day; the previous average uses the nights just before")
    func previousPeriod() {
        let sleep = calculate(connected([
            interval(-15, 22, to: -14, 6),  // ends before both periods
            interval(-14, 23, to: -13, 7),  // 8 h, first day of the previous period
            interval(-8, 23, to: -7, 5),    // 6 h, last day of the previous period
            interval(-7, 22, to: -6, 6),    // 8 h, starts before the period, ends in it
        ]))
        #expect(sleep.nights.map(\.day) == [T.day(-6)])
        #expect(sleep.averageDuration == 8.0 * 3600)
        #expect(sleep.previousAverageDuration == 7.0 * 3600)
    }

    @Test("Last night counts for today as soon as it ends")
    func lastNight() {
        let sleep = calculate(connected([interval(-1, 23, to: 0, 7)]))
        #expect(sleep.nights == [InsightsNight(day: T.day(0), start: T.time(-1, 23), end: T.time(0, 7))])
        #expect(sleep.averageDuration == 8.0 * 3600)
    }

    @Test("Sleep habits: active ones only, with their consistency; today is a grace day")
    func habits() {
        let lightsOut = T.habit(
            "Lights out", category: .sleep, doneOffsets: [-6, -5, -3, -1], color: .teal, icon: "moon.fill"
        )
        let archived = T.habit("Old routine", category: .sleep, archivedOffset: -2, doneOffsets: [-6])
        let run = T.habit("Run", category: .fitness, doneOffsets: [-1])
        let sleep = calculate(InsightsInput(habits: [lightsOut, archived, run]))
        // Due from day -6 to day -1; today is not done yet, so it does not count.
        #expect(sleep.habits == [
            InsightsHabitConsistency(
                habitID: lightsOut.id, name: "Lights out", icon: "moon.fill", color: .teal,
                rate: InsightsRate(done: 4, total: 6)
            ),
        ])
    }

    @Test("Havana: a night that ends on the midnight DST day keys to that day's start")
    func havana() {
        let calendar = TestCalendar.havana
        let today = TestCalendar.instant(calendar, 2026, 3, 12)
        // On 2026-03-08 Havana's clock skips from 00:00 to 01:00.
        let night = DateInterval(
            start: TestCalendar.instant(calendar, 2026, 3, 7, 23),
            end: TestCalendar.instant(calendar, 2026, 3, 8, 7)
        )
        let input = InsightsInput(health: InsightsHealth(isConnected: true, sleep: [night]))
        let sleep = InsightsCalculator.sleep(T.scope(input, T.context(period: .month, today: today, calendar: calendar)))
        #expect(sleep.nights.map(\.day) == [calendar.startOfDay(for: night.end)])
        // 8 hours on the wall clock, 7 hours in fact.
        #expect(sleep.averageDuration == 7.0 * 3600)
        #expect(sleep.medianBedtimeMinutes == 23 * 60)
        #expect(sleep.medianWakeMinutes == 7 * 60)
    }
}
