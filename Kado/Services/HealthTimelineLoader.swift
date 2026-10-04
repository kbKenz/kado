import Foundation
import KadoCore
import OSLog

/// Loads one Calendar day's Health entries. Gated on the opt-in, so
/// a user who never enabled the feature never triggers a HealthKit
/// query. Each kind fails on its own and a failure never reaches the
/// Calendar: the day still renders its tasks.
struct HealthTimelineLoader {
    let provider: any HealthTimelineProviding
    let calendar: Calendar

    func entries(on day: Date, isEnabled: Bool) async -> [HealthTimelineEntry] {
        guard isEnabled, provider.isAvailable,
              let window = HealthTimelineClipper.queryInterval(around: day, calendar: calendar)
        else { return [] }
        let sleep = await attempt("sleep") { try await provider.sleepEntries(in: window) }
        guard !Task.isCancelled else { return [] }
        let workouts = await attempt("workouts") { try await provider.workoutEntries(in: window) }
        return HealthTimelineClipper.entries(sleep + workouts, on: day, calendar: calendar)
    }

    /// Logs the error's type only: a description could carry Health data.
    /// Cancellation is expected when the user changes day and is not logged.
    private func attempt(_ kind: String, _ load: () async throws -> [HealthTimelineEntry]) async -> [HealthTimelineEntry] {
        do {
            return try await load()
        } catch is CancellationError {
            return []
        } catch {
            Logger.healthCalendar.error("Health \(kind, privacy: .public) query failed: \(String(describing: type(of: error)), privacy: .public)")
            return []
        }
    }
}
