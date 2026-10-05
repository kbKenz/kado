import Foundation
import KadoCore

/// Text for the numbers in the Insights cards. Formatting only: every
/// number comes from the report, and nothing here decides one.
enum InsightsFormat {

    /// "12h 40m". Hours and minutes, narrow units, in the locale's words.
    static func duration(_ seconds: TimeInterval, locale: Locale = .autoupdatingCurrent) -> String {
        Duration.seconds(max(0, seconds))
            .formatted(.units(allowed: [.hours, .minutes], width: .narrow).locale(locale))
    }

    /// "82%".
    static func percent(_ fraction: Double, locale: Locale = .autoupdatingCurrent) -> String {
        fraction.formatted(.percent.precision(.fractionLength(0)).locale(locale))
    }

    /// The rate as a percent, or `nil` when it had no chance at all.
    static func percent(_ rate: InsightsRate, locale: Locale = .autoupdatingCurrent) -> String? {
        rate.fraction.map { percent($0, locale: locale) }
    }

    /// A count with the locale's grouping: "1,240".
    static func count(_ value: Int, locale: Locale = .autoupdatingCurrent) -> String {
        value.formatted(.number.locale(locale))
    }

    /// A counter's total, with at most one decimal: "214", "12.5".
    static func amount(_ value: Double, locale: Locale = .autoupdatingCurrent) -> String {
        value.formatted(.number.precision(.fractionLength(0...1)).locale(locale))
    }

    /// "2.4": an average number of days, with one decimal.
    static func days(_ value: Double, locale: Locale = .autoupdatingCurrent) -> String {
        value.formatted(.number.precision(.fractionLength(1)).locale(locale))
    }

    /// A wall-clock time from minutes after midnight: "11:10 PM", or
    /// "23:10" where the locale counts to 24.
    ///
    /// Read on 1 January 2001, a day with no clock change in any zone,
    /// so every minute of the day exists.
    static func time(
        minutesAfterMidnight minutes: Int,
        calendar: Calendar,
        locale: Locale = .autoupdatingCurrent
    ) -> String {
        let clamped = min(max(minutes, 0), 24 * 60 - 1)
        var components = DateComponents()
        components.year = 2001
        components.month = 1
        components.day = 1
        components.hour = clamped / 60
        components.minute = clamped % 60
        guard let date = calendar.date(from: components) else { return "" }
        let style = Date.FormatStyle(
            date: .omitted,
            time: .shortened,
            locale: locale,
            calendar: calendar,
            timeZone: calendar.timeZone
        )
        return date.formatted(style)
    }

    // MARK: - Changes

    /// How a rate moved against the previous period, in whole points.
    enum PointChange: Hashable {
        /// The rate had no chance at all in this period.
        case noData
        /// The previous period had no chance at all, so there is
        /// nothing to compare with.
        case noEarlierData
        case same
        case up(Int)
        case down(Int)
    }

    /// The change between two rates, from their rounded percents, so
    /// it always matches the two numbers on screen.
    static func pointChange(_ current: InsightsRate, from previous: InsightsRate) -> PointChange {
        guard let now = current.fraction else { return .noData }
        guard let before = previous.fraction else { return .noEarlierData }
        let points = wholePercent(now) - wholePercent(before)
        if points > 0 { return .up(points) }
        if points < 0 { return .down(-points) }
        return .same
    }

    /// How a duration moved against the previous period.
    enum DurationChange: Hashable {
        case same
        case more(TimeInterval)
        case less(TimeInterval)
    }

    /// The change between two durations. Under a minute either way is
    /// the same, because the totals are shown to the minute.
    static func durationChange(_ current: TimeInterval, from previous: TimeInterval) -> DurationChange {
        let delta = current - previous
        if abs(delta) < 60 { return .same }
        return delta > 0 ? .more(delta) : .less(-delta)
    }

    /// Tracked against planned time, as the Focus card words it.
    enum PlanDrift: Hashable {
        /// Within 5% of the plan.
        case onPlan
        /// Longer than planned by this share (0.18 = 18%).
        case longer(Double)
        /// Shorter than planned by this share.
        case shorter(Double)
    }

    /// The drift a plan ratio describes. Within 5% reads as on plan:
    /// a session rarely ends to the minute.
    static func planDrift(_ ratio: Double) -> PlanDrift {
        let drift = ratio - 1
        if abs(drift) < 0.05 { return .onPlan }
        return drift > 0 ? .longer(drift) : .shorter(-drift)
    }

    private static func wholePercent(_ fraction: Double) -> Int {
        Int((fraction * 100).rounded())
    }
}
