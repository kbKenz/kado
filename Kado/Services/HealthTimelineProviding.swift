import Foundation
import KadoCore

/// Reads the Health intervals the Calendar overlays and the Insights
/// cards summarize. Read-only: Kadō never writes to Health. Sleep and
/// workouts are separate calls so one failing never hides the other.
protocol HealthTimelineProviding {
    /// False on devices without Health (some iPads). The Settings row
    /// is hidden and nothing is queried.
    var isAvailable: Bool { get }
    func requestAuthorization() async throws
    func sleepEntries(in interval: DateInterval) async throws -> [HealthTimelineEntry]
    /// The raw sleep samples that overlap `interval`, not merged.
    /// Insights merges them one night at a time (`InsightsHealthLoader`).
    func sleepSamples(in interval: DateInterval) async throws -> [SleepSample]
    func workoutEntries(in interval: DateInterval) async throws -> [HealthTimelineEntry]
}
