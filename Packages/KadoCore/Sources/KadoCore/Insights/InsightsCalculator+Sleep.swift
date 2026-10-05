import Foundation

extension InsightsCalculator {
    /// Apple Health nights and Sleep-category habits.
    /// Rules: see `InsightsSleep` in InsightsReport.swift.
    static func sleep(_ scope: InsightsScope) -> InsightsSleep {
        let calendar = scope.calendar
        let nightsByDay = InsightsSharedB.longestNights(scope)
        let nights = scope.days.compactMap { nightsByDay[$0] }
        let previousNights = scope.previousDays.compactMap { nightsByDay[$0] }
        // Bedtimes move by 12 hours, so 23:00 and 01:00 sort next to
        // each other instead of 22 hours apart.
        let bedtimes = nights.map { (InsightsSharedB.minuteOfDay($0.start, calendar) + 720) % 1440 }
        let medianBedtime = InsightsSharedB.median(bedtimes)
        let regularNights = medianBedtime.map { median in
            bedtimes.filter { abs($0 - median) <= 45 }.count
        } ?? 0
        let wakeTimes = nights.map { InsightsSharedB.minuteOfDay($0.end, calendar) }
        return InsightsSleep(
            isHealthConnected: scope.input.health.isConnected,
            nights: nights,
            averageDuration: InsightsSharedB.averageDuration(nights),
            previousAverageDuration: InsightsSharedB.averageDuration(previousNights),
            nightsOverSevenHours: InsightsRate(
                done: nights.filter { $0.duration >= 7 * 3600 }.count,
                total: nights.count
            ),
            bedtimeConsistency: InsightsRate(done: regularNights, total: nights.count),
            medianBedtimeMinutes: medianBedtime.map { ($0 + 720) % 1440 },
            medianWakeMinutes: InsightsSharedB.median(wakeTimes),
            habits: InsightsSharedB.activeHabits(in: .sleep, scope)
        )
    }
}

private extension InsightsSharedB {
    /// The longest sleep session of at least 2 hours per wake day (the
    /// civil day it ends on). On equal lengths the earlier start wins.
    static func longestNights(_ scope: InsightsScope) -> [Date: InsightsNight] {
        var nights: [Date: InsightsNight] = [:]
        for interval in scope.input.health.sleep where interval.duration >= 2 * 3600 {
            let night = InsightsNight(day: scope.civilDay(interval.end), start: interval.start, end: interval.end)
            if let kept = nights[night.day] {
                let isLonger = night.duration > kept.duration
                let isEarlierTie = night.duration == kept.duration && night.start < kept.start
                guard isLonger || isEarlierTie else { continue }
            }
            nights[night.day] = night
        }
        return nights
    }

    static func averageDuration(_ nights: [InsightsNight]) -> TimeInterval? {
        guard !nights.isEmpty else { return nil }
        return nights.reduce(0) { $0 + $1.duration } / Double(nights.count)
    }

    /// Wall-clock minutes after midnight, 0..<1440.
    static func minuteOfDay(_ instant: Date, _ calendar: Calendar) -> Int {
        let time = calendar.dateComponents([.hour, .minute], from: instant)
        return (time.hour ?? 0) * 60 + (time.minute ?? 0)
    }

    /// The middle value. With an even count: the mean of the two middle
    /// values, rounded down. `nil` without values.
    static func median(_ values: [Int]) -> Int? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let middle = sorted.count / 2
        if sorted.count % 2 == 1 { return sorted[middle] }
        // Values are never negative here, so integer division rounds down.
        return (sorted[middle - 1] + sorted[middle]) / 2
    }
}
