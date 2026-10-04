import Foundation
import KadoCore

/// Reads the Health intervals the Calendar overlays. Read-only: Kadō
/// never writes to Health. Sleep and workouts are separate calls so
/// one failing never hides the other.
protocol HealthTimelineProviding {
    /// False on devices without Health (some iPads). The Settings row
    /// is hidden and nothing is queried.
    var isAvailable: Bool { get }
    func requestAuthorization() async throws
    func sleepEntries(in interval: DateInterval) async throws -> [HealthTimelineEntry]
    func workoutEntries(in interval: DateInterval) async throws -> [HealthTimelineEntry]
}
