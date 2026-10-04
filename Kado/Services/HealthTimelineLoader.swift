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

    private static let logger = Logger(subsystem: "dev.scastiel.kado", category: "health-calendar")

    func entries(on day: Date, isEnabled: Bool) async -> [HealthTimelineEntry] {
        guard isEnabled, provider.isAvailable,
              let window = HealthTimelineClipper.queryInterval(around: day, calendar: calendar)
        else { return [] }
        let sleep = await attempt("sleep") { try await provider.sleepEntries(in: window) }
        let workouts = await attempt("workouts") { try await provider.workoutEntries(in: window) }
        return HealthTimelineClipper.entries(sleep + workouts, on: day, calendar: calendar)
    }

    /// Logs the error's type only: a description could carry Health data.
    private func attempt(_ kind: String, _ load: () async throws -> [HealthTimelineEntry]) async -> [HealthTimelineEntry] {
        do {
            return try await load()
        } catch {
            Self.logger.error("Health \(kind, privacy: .public) query failed: \(String(describing: type(of: error)), privacy: .public)")
            return []
        }
    }
}
