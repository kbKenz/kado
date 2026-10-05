import Foundation

/// Tasks done and left undone over a set of days.
///
/// Shared by the Pulse, Categories and Tasks sections, so the three
/// cards always agree on what "done" and "left undone" mean.
nonisolated struct InsightsTaskTally: Hashable, Sendable {
    var done = 0
    var undone = 0

    /// Done + left undone.
    var total: Int { done + undone }

    /// Follow-through: done out of done + left undone.
    var followThrough: InsightsRate { InsightsRate(done: done, total: total) }
}

/// Shared reads for the Pulse, Activity, Habits, Categories, Tasks and
/// Goals sections.
extension InsightsScope {
    // MARK: - Tasks

    /// The tasks the sections read. A cancelled import is skipped
    /// everywhere.
    var uncancelledTasks: [InsightsTask] {
        input.tasks.filter { !$0.isCancelled }
    }

    /// The task was completed on a civil day in `days`.
    func isTaskDone(_ task: InsightsTask, in days: Set<Date>) -> Bool {
        guard let completedAt = task.completedAt else { return false }
        return days.contains(civilDay(completedAt))
    }

    /// The task has no completion, and its target day is in `days` and
    /// before today.
    func isTaskLeftUndone(_ task: InsightsTask, in days: Set<Date>) -> Bool {
        guard task.completedAt == nil, let target = task.targetDay else { return false }
        let targetDay = civilDay(target)
        return targetDay < today && days.contains(targetDay)
    }

    /// Done and left-undone counts of `tasks` over `days`. Cancelled
    /// tasks are skipped.
    func taskTally(of tasks: [InsightsTask], over days: Set<Date>) -> InsightsTaskTally {
        var tally = InsightsTaskTally()
        for task in tasks where !task.isCancelled {
            if isTaskDone(task, in: days) {
                tally.done += 1
            } else if isTaskLeftUndone(task, in: days) {
                tally.undone += 1
            }
        }
        return tally
    }

    // MARK: - Habits

    /// Due habit-days done / due habit-days, for `habits` over `days`.
    /// Off-schedule and not-counted days add nothing.
    func habitConsistency(of habits: [InsightsHabit], over days: [Date]) -> InsightsRate {
        var rate = InsightsRate.empty
        for habit in habits {
            for day in days {
                guard case .due(let done) = outcome(of: habit, on: day) else { continue }
                rate.total += 1
                if done { rate.done += 1 }
            }
        }
        return rate
    }

    /// The days in `days` on which `habit` has a positive record. For a
    /// negative habit these are slips.
    func daysWithPositiveRecord(of habit: InsightsHabit, in days: [Date]) -> Int {
        days.filter { !positiveRecords(of: habit, on: $0).isEmpty }.count
    }

    // MARK: - Sessions

    /// Sessions with tracked time, with their seconds at `now`. A
    /// session with no tracked time is skipped everywhere.
    var sessionsWithTime: [(session: InsightsSession, seconds: TimeInterval)] {
        input.sessions.compactMap { session in
            let seconds = session.session.elapsed(at: context.now)
            return seconds > 0 ? (session: session, seconds: seconds) : nil
        }
    }

    // MARK: - Days

    /// Whole civil days from the day of `start` to the day of `end`.
    /// Negative when `end` is on an earlier day.
    ///
    /// Counts from noon to noon: in a zone whose day starts at 01:00 on
    /// a DST change (America/Havana), the day's start and the next
    /// midnight are only 23 hours apart, and a count between the two
    /// day starts would come out one day short.
    func civilDayDistance(from start: Date, to end: Date) -> Int {
        let startNoon = noon(of: start)
        let endNoon = noon(of: end)
        return calendar.dateComponents([.day], from: startNoon, to: endNoon).day ?? 0
    }

    private func noon(of instant: Date) -> Date {
        let day = civilDay(instant)
        return calendar.date(bySettingHour: 12, minute: 0, second: 0, of: day) ?? day
    }
}
