import Foundation
import HealthKit
import KadoCore

/// Live HealthKit reads for the Calendar overlay. Read-only; nothing
/// it returns is stored, synced, or exported.
final class HealthKitTimelineProvider: HealthTimelineProviding {
    private let store = HKHealthStore()
    private let sleepType = HKCategoryType(.sleepAnalysis)
    private let readTypes: Set<HKObjectType> = [HKCategoryType(.sleepAnalysis), HKObjectType.workoutType()]

    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    func requestAuthorization() async throws {
        guard isAvailable else { return }
        try await store.requestAuthorization(toShare: [], read: readTypes)
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

    /// Internal for tests. Asleep stages use Apple's set, so a stage added
    /// in a later iOS still counts as asleep.
    static func sleepSample(_ sample: HKCategorySample) -> SleepSample? {
        // HealthKit rejects unknown values at construction; kept as a guard.
        guard let value = HKCategoryValueSleepAnalysis(rawValue: sample.value) else { return nil }
        let stage: SleepSample.Stage
        if HKCategoryValueSleepAnalysis.allAsleepValues.contains(value) { stage = .asleep }
        else if value == .inBed { stage = .inBed }
        else if value == .awake { stage = .awake }
        else { return nil }
        return SleepSample(id: sample.uuid, stage: stage,
                           interval: DateInterval(start: sample.startDate, end: max(sample.startDate, sample.endDate)))
    }
}
