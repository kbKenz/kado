import Foundation

public struct DefaultHabitScoreCalculator: HabitScoreCalculating {
    public let alpha: Double
    public let calendar: Calendar
    public let frequencyEvaluator: any FrequencyEvaluating

    public init(
        alpha: Double = 0.05,
        calendar: Calendar = .current,
        frequencyEvaluator: (any FrequencyEvaluating)? = nil
    ) {
        self.alpha = alpha
        self.calendar = calendar
        self.frequencyEvaluator = frequencyEvaluator
            ?? DefaultFrequencyEvaluator(calendar: calendar)
    }

    public func currentScore(
        for habit: Habit,
        completions: [Completion],
        asOf date: Date
    ) -> Double {
        let start = habit.effectiveStart(completions: completions, calendar: calendar)
        // The last value of `scoreHistory`, without building the array.
        var score = 0.0
        walk(habit: habit, completions: completions, from: start, to: date) { _, value in
            score = value
        }
        return score
    }

    public func scoreHistory(
        for habit: Habit,
        completions: [Completion],
        from startDate: Date,
        to endDate: Date
    ) -> [DailyScore] {
        var result: [DailyScore] = []
        walk(habit: habit, completions: completions, from: startDate, to: endDate) { day, score in
            result.append(DailyScore(date: day, score: score))
        }
        return result
    }

    /// The score fold, reporting each day's running score to `body`.
    private func walk(
        habit: Habit,
        completions: [Completion],
        from startDate: Date,
        to endDate: Date,
        body: (Date, Double) -> Void
    ) {
        let effectiveStartDay = calendar.startOfDay(
            for: habit.effectiveStart(completions: completions, calendar: calendar)
        )
        let firstDay = max(calendar.startOfDay(for: startDate), effectiveStartDay)
        let lastDay = calendar.startOfDay(for: endDate)
        guard firstDay <= lastDay else { return }

        // Filtered once, then handed to the evaluator on every day of
        // the walk. Every frequency it evaluates already discards other
        // habits' records, so this changes no answer — but
        // `WidgetSnapshotBuilder` rebuilds every habit's score on
        // MainActor after every mutation, and handing the evaluator the
        // whole store's completions made that quadratic in the store,
        // not in the habit.
        let habitCompletions = completions.filter { $0.habitID == habit.id }
        let completionsByDay = completionsForHabitGrouped(by: habit, completions: habitCompletions)

        // `isCounted`, not `isDue`: an `.everyNDays` cycle re-anchors on
        // completion, so working ahead removes due days and a
        // due-days-only measure would score perfect daily adherence at
        // nearly zero.
        //
        // The default evaluator is asked through a prepared schedule:
        // per call it rescans every completion (effective start,
        // `.everyNDays` anchor, `.daysPerWeek` window), which made this
        // walk days x completions — seconds for a long history, on
        // MainActor. Same answers, see `ScheduleEquivalenceTests`. An
        // injected evaluator keeps the per-call path.
        let isCounted: (Date) -> Bool
        if let evaluator = frequencyEvaluator as? DefaultFrequencyEvaluator {
            let schedule = evaluator.prepared(
                for: habit,
                completions: habitCompletions,
                loggedDayCalendar: calendar
            )
            isCounted = { schedule.isCounted(on: $0) }
        } else {
            isCounted = { day in
                frequencyEvaluator.isCounted(
                    habit: habit,
                    on: day,
                    completions: habitCompletions,
                    calendar: calendar
                )
            }
        }

        var score = 0.0
        var day = firstDay
        while day <= lastDay {
            if isCounted(day) {
                let value = DailyValue.compute(
                    for: habit,
                    completionsOnDay: completionsByDay[day] ?? []
                )
                score = (1 - alpha) * score + alpha * value
            }
            body(day, score)
            // Re-anchored, because adding a day to a midnight does not
            // always land on one: in a zone whose DST transition happens
            // *at* 00:00 (America/Havana) the day's first instant is
            // 01:00, and every step after keeps that hour — while the
            // completions being scored are bucketed at true midnights.
            day = calendar.startOfDay(for: calendar.date(byAdding: .day, value: 1, to: day)!)
        }
    }

    private func completionsForHabitGrouped(
        by habit: Habit,
        completions: [Completion]
    ) -> [Date: [Completion]] {
        Dictionary(grouping: completions.filter { $0.habitID == habit.id }) {
            calendar.startOfDay(for: $0.date)
        }
    }
}
