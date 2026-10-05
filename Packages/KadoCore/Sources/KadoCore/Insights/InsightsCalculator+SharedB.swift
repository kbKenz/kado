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

    /// Due days done / due days of `habit` on `days`.
    static func rate(of habit: InsightsHabit, on days: [Date], _ scope: InsightsScope) -> InsightsRate {
        var rate = InsightsRate.empty
        for day in days {
            guard case .due(let done) = scope.outcome(of: habit, on: day) else { continue }
            rate.total += 1
            if done { rate.done += 1 }
        }
        return rate
    }

    /// The active (not archived) habits of `category`, in input order,
    /// each with its consistency over the period.
    static func activeHabits(in category: ItemCategory, _ scope: InsightsScope) -> [InsightsHabitConsistency] {
        scope.input.habits
            .filter { $0.category == category && $0.habit.archivedAt == nil }
            .map { habit in
                InsightsHabitConsistency(
                    habitID: habit.id,
                    name: habit.habit.name,
                    icon: habit.habit.icon,
                    color: habit.habit.color,
                    rate: rate(of: habit, on: scope.days, scope)
                )
            }
    }

    /// A negative habit: its records are slips, never times done.
    static func isNegative(_ type: HabitType) -> Bool {
        if case .negative = type { return true }
        return false
    }

    static func isTimer(_ type: HabitType) -> Bool {
        if case .timer = type { return true }
        return false
    }
}
