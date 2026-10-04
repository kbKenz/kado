import Foundation
import HealthKit
import KadoCore

/// Live HealthKit reads for the Calendar overlay. Read-only; nothing
/// it returns is stored, synced, or exported.
final class HealthKitTimelineProvider: HealthTimelineProviding {
    private let store = HKHealthStore()
    private let sleepType = HKCategoryType(.sleepAnalysis)

    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    func requestAuthorization() async throws {
        try await store.requestAuthorization(toShare: [], read: [sleepType, HKObjectType.workoutType()])
    }

    func sleepEntries(in interval: DateInterval) async throws -> [HealthTimelineEntry] {
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.categorySample(type: sleepType, predicate: Self.overlapping(interval))],
            sortDescriptors: [SortDescriptor(\.startDate)]
        )
        let samples = try await descriptor.result(for: store)
        return SleepSessionBuilder.sessions(from: samples.compactMap(Self.sleepSample))
    }

    func workoutEntries(in interval: DateInterval) async throws -> [HealthTimelineEntry] {
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.workout(Self.overlapping(interval))],
            sortDescriptors: [SortDescriptor(\.startDate)]
        )
        let workouts = try await descriptor.result(for: store)
        return workouts.map { workout in
            HealthTimelineEntry(
                id: workout.uuid,
                kind: .workout(name: workout.workoutActivityType.displayName),
                interval: DateInterval(start: workout.startDate, end: max(workout.startDate, workout.endDate))
            )
        }
    }

    /// Samples that overlap the window at all, not only ones inside it.
    private static func overlapping(_ interval: DateInterval) -> NSPredicate {
        HKQuery.predicateForSamples(withStart: interval.start, end: interval.end, options: [])
    }

    private static func sleepSample(_ sample: HKCategorySample) -> SleepSample? {
        guard let value = HKCategoryValueSleepAnalysis(rawValue: sample.value) else { return nil }
        let stage: SleepSample.Stage
        switch value {
        case .inBed: stage = .inBed
        case .awake: stage = .awake
        case .asleepUnspecified, .asleepCore, .asleepDeep, .asleepREM: stage = .asleep
        @unknown default: return nil
        }
        return SleepSample(id: sample.uuid, stage: stage,
                           interval: DateInterval(start: sample.startDate, end: max(sample.startDate, sample.endDate)))
    }
}
