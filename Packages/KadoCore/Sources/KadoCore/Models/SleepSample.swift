import Foundation

/// A raw sleep-analysis sample, mapped out of HealthKit so the session
/// rules can be tested without it.
nonisolated public struct SleepSample: Hashable, Sendable {
    public enum Stage: Hashable, Sendable {
        case inBed
        /// Any asleep stage: core, deep, REM, or unspecified.
        case asleep
        case awake
    }

    public let id: UUID
    public let stage: Stage
    public let interval: DateInterval

    public init(id: UUID, stage: Stage, interval: DateInterval) {
        self.id = id
        self.stage = stage
        self.interval = interval
    }
}
