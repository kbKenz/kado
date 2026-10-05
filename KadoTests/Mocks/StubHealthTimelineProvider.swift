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
    var sleepSamples: [SleepSample] = []
    var workouts: [HealthTimelineEntry] = []
    /// Fails both sleep reads: one HealthKit query backs them.
    var sleepFails = false
    var workoutsFails = false
    private(set) var queryCount = 0
    /// Every interval asked for, in call order.
    private(set) var queriedIntervals: [DateInterval] = []

    func requestAuthorization() async throws {}

    func sleepEntries(in interval: DateInterval) async throws -> [HealthTimelineEntry] {
        try record(interval, fails: sleepFails)
        return sleep
    }

    func sleepSamples(in interval: DateInterval) async throws -> [SleepSample] {
        try record(interval, fails: sleepFails)
        return sleepSamples
    }

    func workoutEntries(in interval: DateInterval) async throws -> [HealthTimelineEntry] {
        try record(interval, fails: workoutsFails)
        return workouts
    }

    private func record(_ interval: DateInterval, fails: Bool) throws {
        queryCount += 1
        queriedIntervals.append(interval)
        if fails { throw Failure() }
    }
}
