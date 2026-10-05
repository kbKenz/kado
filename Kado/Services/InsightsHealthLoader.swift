import Foundation
import KadoCore
import OSLog

/// Reads Apple Health for the Insights Sleep and Movement cards.
///
/// Behind the same opt-in as the Calendar overlay
/// (`HealthCalendarDefaults.key`), so a user who never turned it on
/// never triggers a HealthKit query. Read live, shown, and dropped:
/// nothing here is stored, synced or exported.
struct InsightsHealthLoader {
    let provider: any HealthTimelineProviding
    let calendar: Calendar

    /// Sleep sessions and workouts that overlap `interval`.
    ///
    /// Off, or no Health on this device: `.disconnected`, and nothing
    /// is queried. Otherwise sleep and workouts are read at the same
    /// time, and each one fails on its own: the failure is logged
    /// (error type only), that part comes back empty, and the result
    /// stays connected, so the cards show what was read.
    func health(in interval: DateInterval, isEnabled: Bool) async -> InsightsHealth {
        guard isEnabled, provider.isAvailable else { return .disconnected }
        async let samples = read("sleep") { try await provider.sleepSamples(in: interval) }
        async let entries = read("workouts") { try await provider.workoutEntries(in: interval) }
        let sleep = Self.sleepSessions(from: await samples, calendar: calendar)
        let workouts = await entries.compactMap(Self.workout)
        return InsightsHealth(isConnected: true, sleep: sleep, workouts: workouts)
    }

    /// Merged sleep sessions, oldest first, with the asleep or in-bed
    /// choice made one night at a time.
    ///
    /// `SleepSessionBuilder` keeps only asleep stages when its samples
    /// have any. Given a whole month at once, the nights with a Watch
    /// would hide every night the iPhone recorded alone. So samples are
    /// grouped by the noon-to-noon window their start falls in
    /// ([D-1 12:00, D 12:00) in `calendar`), and each night is built on
    /// its own.
    static func sleepSessions(from samples: [SleepSample], calendar: Calendar) -> [DateInterval] {
        Dictionary(grouping: samples) { night(of: $0.interval.start, calendar: calendar) }
            .values
            .flatMap { SleepSessionBuilder.sessions(from: $0) }
            .map(\.interval)
            .sorted { ($0.start, $0.end) < ($1.start, $1.end) }
    }

    /// Midnight of the day the noon-to-noon window around `instant`
    /// ends on: the same day before noon, the next day from noon on.
    static func night(of instant: Date, calendar: Calendar) -> Date {
        let day = calendar.startOfDay(for: instant)
        guard let noon = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: day),
              instant >= noon
        else { return day }
        return InsightsScope.step(day, by: 1, calendar: calendar)
    }

    /// What a report on `period` needs: from noon before the previous
    /// period's first day, so that first night is read whole, to `now`.
    static func queryInterval(for period: InsightsPeriod, today: Date, now: Date, calendar: Calendar) -> DateInterval {
        let first = InsightsScope.step(today, by: -(2 * period.dayCount - 1), calendar: calendar)
        let dayBefore = InsightsScope.step(first, by: -1, calendar: calendar)
        let start = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: dayBefore) ?? dayBefore
        return DateInterval(start: start, end: max(start, now))
    }

    private static func workout(_ entry: HealthTimelineEntry) -> InsightsWorkout? {
        guard case .workout(let name) = entry.kind else { return nil }
        return InsightsWorkout(name: name, interval: entry.interval)
    }

    /// Logs the error's type only: a description could carry Health
    /// data. Cancellation is expected when the screen goes away and is
    /// not logged.
    private func read<Value>(_ kind: String, _ load: () async throws -> [Value]) async -> [Value] {
        do {
            return try await load()
        } catch is CancellationError {
            return []
        } catch {
            Logger.healthCalendar.error("Insights Health \(kind, privacy: .public) query failed: \(String(describing: type(of: error)), privacy: .public)")
            return []
        }
    }
}
