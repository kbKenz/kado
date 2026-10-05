import Foundation

/// Helpers for the Focus, Sleep, Movement, Rhythm, All time and
/// Highlights sections.
///
/// They live in a namespace of their own, so their names cannot clash
/// with the helpers of the other sections: Swift refuses a `private`
/// member that has the same name as an `internal` one on the same type,
/// even in another file. Each section file adds its own `private`
/// helpers to this namespace too.
enum InsightsSharedB {
    /// A session that ran for some time.
    struct TrackedSession {
        let source: InsightsSession
        /// The logical day the session started on.
        let day: Date
        /// Worked time at `context.now`. Always more than zero.
        let seconds: TimeInterval
    }

    /// Every session with time at `context.now`, on any day. A session
    /// without time counts nowhere.
    static func trackedSessions(_ scope: InsightsScope) -> [TrackedSession] {
        scope.input.sessions.compactMap { session in
            let seconds = session.session.elapsed(at: scope.context.now)
            guard seconds > 0 else { return nil }
            return TrackedSession(source: session, day: scope.sessionDay(session), seconds: seconds)
        }
    }

    /// The tracked sessions that started on one of `days`.
    static func trackedSessions(_ scope: InsightsScope, on days: [Date]) -> [TrackedSession] {
        let keys = Set(days)
        return trackedSessions(scope).filter { keys.contains($0.day) }
    }
}
