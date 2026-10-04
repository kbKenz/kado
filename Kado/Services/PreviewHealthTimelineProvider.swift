import Foundation
import KadoCore

/// Environment default and preview fixture. Never touches HealthKit,
/// so previews and unit tests that forget to inject stay offline.
struct PreviewHealthTimelineProvider: HealthTimelineProviding {
    var isAvailable = true
    var sleep: [HealthTimelineEntry] = []
    var workouts: [HealthTimelineEntry] = []

    func requestAuthorization() async throws {}
    func sleepEntries(in interval: DateInterval) async throws -> [HealthTimelineEntry] { sleep }
    func workoutEntries(in interval: DateInterval) async throws -> [HealthTimelineEntry] { workouts }
}
