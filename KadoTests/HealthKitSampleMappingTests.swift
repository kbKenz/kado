import Foundation
import HealthKit
import Testing
import KadoCore
@testable import Kado

@MainActor
@Suite("HealthKit sample mapping")
struct HealthKitSampleMappingTests {
    let start = Date(timeIntervalSince1970: 1_700_000_000)

    func sample(_ raw: Int, end: Date? = nil) -> HKCategorySample {
        HKCategorySample(
            type: HKCategoryType(.sleepAnalysis), value: raw,
            start: start, end: end ?? start.addingTimeInterval(3600)
        )
    }

    @Test("Each sleep value maps to the expected stage",
          arguments: [
            (HKCategoryValueSleepAnalysis.inBed, SleepSample.Stage.inBed),
            (.awake, .awake),
            (.asleepUnspecified, .asleep),
            (.asleepCore, .asleep),
            (.asleepDeep, .asleep),
            (.asleepREM, .asleep),
          ])
    func stageMapping(value: HKCategoryValueSleepAnalysis, expected: SleepSample.Stage) {
        #expect(HealthKitTimelineProvider.sleepSample(sample(value.rawValue))?.stage == expected)
    }

    @Test("A zero-length sample keeps a zero-duration interval")
    func zeroLength() throws {
        let raw = HKCategoryValueSleepAnalysis.asleepCore.rawValue
        let mapped = try #require(HealthKitTimelineProvider.sleepSample(sample(raw, end: start)))
        #expect(mapped.stage == .asleep)
        #expect(mapped.interval.duration == 0)
    }

    @Test("Both strength types share one name")
    func strengthNames() {
        #expect(HKWorkoutActivityType.functionalStrengthTraining.displayName
                == HKWorkoutActivityType.traditionalStrengthTraining.displayName)
    }

    @Test("An unmapped workout type reads like other")
    func unmappedName() {
        #expect(HKWorkoutActivityType.archery.displayName == HKWorkoutActivityType.other.displayName)
    }
}
