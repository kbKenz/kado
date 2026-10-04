import Foundation

/// Tracked time on one task or habit, as a value. `WorkSessionRecord`
/// stores it; this type does the arithmetic so views and tests never
/// repeat it.
nonisolated public struct WorkSession: Hashable, Sendable {
    public var startedAt: Date
    public var endedAt: Date?
    public var pausedAt: Date?
    /// Total of finished pauses. An open pause is counted from `pausedAt`.
    public var pausedSeconds: TimeInterval

    public init(startedAt: Date, endedAt: Date? = nil, pausedAt: Date? = nil, pausedSeconds: TimeInterval = 0) {
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.pausedAt = pausedAt
        self.pausedSeconds = pausedSeconds
    }

    public var isOpen: Bool { endedAt == nil }
    public var isPaused: Bool { isOpen && pausedAt != nil }

    /// Worked time at `now`: (end or now) − start − pauses.
    public func elapsed(at now: Date) -> TimeInterval {
        let end = endedAt ?? now
        let openPause = isPaused ? max(0, end.timeIntervalSince(pausedAt!)) : 0
        return max(0, end.timeIntervalSince(startedAt) - pausedSeconds - openPause)
    }
}
