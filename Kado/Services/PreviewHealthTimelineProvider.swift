import Foundation
import KadoCore

/// Environment default and preview fixture. Never touches HealthKit,
/// so previews and unit tests that forget to inject stay offline.
struct PreviewHealthTimelineProvider: HealthTimelineProviding {
    var isAvailable = true
    var sleep: [HealthTimelineEntry] = []
    var sleepSamples: [SleepSample] = []
    var workouts: [HealthTimelineEntry] = []

    func requestAuthorization() async throws {}
    func sleepEntries(in interval: DateInterval) async throws -> [HealthTimelineEntry] { sleep }
    func sleepSamples(in interval: DateInterval) async throws -> [SleepSample] { sleepSamples }
    func workoutEntries(in interval: DateInterval) async throws -> [HealthTimelineEntry] { workouts }
}
