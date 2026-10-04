import Foundation
import KadoCore
@testable import Kado

/// Driven sequentially by one test at a time, so plain stored state
/// is enough.
@MainActor
final class StubHealthTimelineProvider: HealthTimelineProviding {
    struct Failure: Error {}

    var isAvailable = true
    var sleep: [HealthTimelineEntry] = []
    var workouts: [HealthTimelineEntry] = []
    var sleepFails = false
    var workoutsFails = false
    private(set) var queryCount = 0

    func requestAuthorization() async throws {}

    func sleepEntries(in interval: DateInterval) async throws -> [HealthTimelineEntry] {
        queryCount += 1
        if sleepFails { throw Failure() }
        return sleep
    }

    func workoutEntries(in interval: DateInterval) async throws -> [HealthTimelineEntry] {
        queryCount += 1
        if workoutsFails { throw Failure() }
        return workouts
    }
}
