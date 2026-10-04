import Foundation

/// Tracked time on one task or habit, as a value. `WorkSessionRecord`
/// stores it; this type does the arithmetic so views and tests never
/// repeat it.
nonisolated public struct WorkSession: Hashable, Sendable {
    public var startedAt: Date
    public var endedAt: Date?
    /// Set while paused. A pause still set when the session ends counts until `endedAt`.
    public var pausedAt: Date?
    /// Total of finished pauses. An open pause is counted from `pausedAt`.
    public var pausedSeconds: TimeInterval

    public init(startedAt: Date, endedAt: Date? = nil, pausedAt: Date? = nil, pausedSeconds: TimeInterval = 0) {
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.pausedAt = pausedAt
        self.pausedSeconds = pausedSeconds
    }

    /// True until the session has an end.
    public var isOpen: Bool { endedAt == nil }
    /// UI state: the session is running but paused right now.
    public var isPaused: Bool { isOpen && pausedAt != nil }

    /// Worked time at `now`: (end or now) − start − pauses.
    public func elapsed(at now: Date) -> TimeInterval {
        let end = endedAt ?? now
        let openPause = pausedAt.map { max(0, end.timeIntervalSince(max($0, startedAt))) } ?? 0
        return max(0, end.timeIntervalSince(startedAt) - pausedSeconds - openPause)
    }
}
