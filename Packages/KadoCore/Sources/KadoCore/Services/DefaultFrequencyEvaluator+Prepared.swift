import Foundation

extension DefaultFrequencyEvaluator {
    /// `habit`'s schedule, ready to be asked about many days.
    ///
    /// `isDue` / `isOutstanding` re-derive the effective start, the
    /// `.everyNDays` anchor and the `.daysPerWeek` window from every
    /// completion on each call, so a walk over a habit's life (the
    /// score, Insights' day outcomes) cost days x completions. The
    /// prepared schedule works those out once and then answers each day
    /// in O(1) or O(log completions).
    ///
    /// Pass the same `completions` the per-call methods would get;
    /// other habits' records are ignored, as there.
    /// `loggedDayCalendar` is the `calendar` that `isCounted` would be
    /// handed, which need not be this evaluator's.
    public func prepared(
        for habit: Habit,
        completions: [Completion],
        loggedDayCalendar: Calendar? = nil
    ) -> Prepared {
        Prepared(
            habit: habit,
            completions: completions,
            calendar: calendar,
            loggedDayCalendar: loggedDayCalendar ?? calendar
        )
    }

    /// One habit's schedule with everything `evaluate` reads from its
    /// completions worked out up front.
    ///
    /// Each method gives exactly the answer of its per-call twin, so a
    /// rule changed in `evaluate` must change here too: two copies of a
    /// schedule rule drifting apart is what issue #57 was.
    /// `ScheduleEquivalenceTests` checks the two against each other.
    public struct Prepared: Sendable {
        public let habit: Habit
        private let calendar: Calendar
        private let loggedDayCalendar: Calendar
        private let effectiveStartDay: Date
        private let archivedDay: Date?
        /// `.everyNDays`: the cycle's anchor before the first completion.
        private let createdDay: Date
        /// `.everyNDays`: `EveryNDaysCycle.anchorCandidates`, ascending.
        private let anchorDays: [Date]
        /// `.everyNDays`, non-negative habits: the days with a positive
        /// record, in `loggedDayCalendar`, for `isCounted`'s logged arm.
        private let loggedDays: Set<Date>
        /// `.daysPerWeek`: the day of each positive record, ascending.
        /// One entry per record, not per day: the quota counts records.
        private let positiveRecordDays: [Date]

        init(habit: Habit, completions: [Completion], calendar: Calendar, loggedDayCalendar: Calendar) {
            self.habit = habit
            self.calendar = calendar
            self.loggedDayCalendar = loggedDayCalendar
            effectiveStartDay = calendar.startOfDay(
                for: habit.effectiveStart(completions: completions, calendar: calendar)
            )
            archivedDay = habit.archivedAt.map { calendar.startOfDay(for: $0) }
            createdDay = calendar.startOfDay(for: habit.createdAt)

            let positive = completions.filter { $0.habitID == habit.id && $0.value > 0 }
            var anchorDays: [Date] = []
            var loggedDays = Set<Date>()
            var positiveRecordDays: [Date] = []
            switch habit.frequency {
            case .daily, .specificDays:
                break
            case .everyNDays(let n):
                if n > 0 {
                    anchorDays = EveryNDaysCycle.anchorCandidates(
                        for: habit, completions: completions, calendar: calendar
                    )
                }
                if EveryNDaysCycle.canReanchor(habit) {
                    loggedDays = Set(positive.map { loggedDayCalendar.startOfDay(for: $0.date) })
                }
            case .daysPerWeek(let target):
                if target > 0 {
                    positiveRecordDays = positive.map { calendar.startOfDay(for: $0.date) }.sorted()
                }
            }
            self.anchorDays = anchorDays
            self.loggedDays = loggedDays
            self.positiveRecordDays = positiveRecordDays
        }

        /// Same answer as `DefaultFrequencyEvaluator.isDue`.
        public func isDue(on date: Date) -> Bool {
            evaluate(on: date, countingOwnDay: false)
        }

        /// Same answer as `DefaultFrequencyEvaluator.isOutstanding`.
        public func isOutstanding(on date: Date) -> Bool {
            evaluate(on: date, countingOwnDay: true)
        }

        /// Same answer as `FrequencyEvaluating.isCounted`, with
        /// `loggedDayCalendar` as its `calendar`.
        public func isCounted(on date: Date) -> Bool {
            guard case .everyNDays = habit.frequency else { return isDue(on: date) }
            if isDue(on: date) { return true }
            if case .negative = habit.type { return false }
            // `isDate(_:inSameDayAs:)` against each record, as a lookup:
            // two instants share a day exactly when their day starts do.
            return loggedDays.contains(loggedDayCalendar.startOfDay(for: date))
        }

        /// Mirrors `DefaultFrequencyEvaluator.evaluate` step by step.
        private func evaluate(on date: Date, countingOwnDay: Bool) -> Bool {
            let day = calendar.startOfDay(for: date)
            guard day >= effectiveStartDay else { return false }
            if let archivedDay {
                guard day <= archivedDay else { return false }
            }

            switch habit.frequency {
            case .daily:
                return true

            case .specificDays(let weekdays):
                let weekdayInt = calendar.component(.weekday, from: day)
                guard let weekday = Weekday(rawValue: weekdayInt) else { return false }
                return weekdays.contains(weekday)

            case .everyNDays(let n):
                guard n > 0 else { return false }
                return EveryNDaysCycle.isDue(
                    interval: n,
                    on: day,
                    anchoredAt: EveryNDaysCycle.anchorDay(before: day, in: anchorDays, fallback: createdDay),
                    calendar: calendar
                )

            case .daysPerWeek(let target):
                guard target > 0 else { return false }
                // The bounds exactly as `evaluate` computes them, not
                // re-anchored to midnights: in a zone whose day can
                // start at 01:00 that changes which records fall inside.
                let windowStart = calendar.date(byAdding: .day, value: -6, to: day)!
                let windowEnd = countingOwnDay
                    ? day
                    : calendar.date(byAdding: .day, value: -1, to: day)!
                return recordCount(from: windowStart, through: windowEnd) < target
            }
        }

        /// The positive records whose day lies in `[start, end]`.
        private func recordCount(from start: Date, through end: Date) -> Int {
            let lower = Self.firstIndex(in: positiveRecordDays) { $0 >= start }
            let upper = Self.firstIndex(in: positiveRecordDays) { $0 > end }
            return max(0, upper - lower)
        }

        /// The first index of ascending `days` whose element satisfies
        /// `isAtOrPast`, or `days.count`. `isAtOrPast` must be false and
        /// then true along the array.
        private static func firstIndex(in days: [Date], where isAtOrPast: (Date) -> Bool) -> Int {
            var low = 0
            var high = days.count
            while low < high {
                let mid = low + (high - low) / 2
                if isAtOrPast(days[mid]) {
                    high = mid
                } else {
                    low = mid + 1
                }
            }
            return low
        }
    }
}
