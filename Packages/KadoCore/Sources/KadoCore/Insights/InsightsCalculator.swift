import Foundation

/// The clock, calendar and services a report is computed with.
nonisolated public struct InsightsContext: Sendable {
    public var period: InsightsPeriod
    /// The current instant. Open sessions count up to it.
    public var now: Date
    /// Calendar midnight of the logical today (`\.today`).
    public var today: Date
    /// The week-start aware calendar (`\.calendar`).
    public var calendar: Calendar
    public var dayBoundary: DayBoundary
    public var frequencyEvaluator: any FrequencyEvaluating
    public var streakCalculator: any StreakCalculating
    public var scoreCalculator: any HabitScoreCalculating

    public init(
        period: InsightsPeriod,
        now: Date,
        today: Date,
        calendar: Calendar,
        dayBoundary: DayBoundary,
        frequencyEvaluator: any FrequencyEvaluating,
        streakCalculator: any StreakCalculating,
        scoreCalculator: any HabitScoreCalculating
    ) {
        self.period = period
        self.now = now
        self.today = calendar.startOfDay(for: today)
        self.calendar = calendar
        self.dayBoundary = dayBoundary
        self.frequencyEvaluator = frequencyEvaluator
        self.streakCalculator = streakCalculator
        self.scoreCalculator = scoreCalculator
    }
}

/// What one habit did on one logical day, for consistency figures.
nonisolated public enum HabitDayOutcome: Hashable, Sendable {
    /// Nothing to judge: after today, before the habit's effective
    /// start, after it was archived, not counted by its schedule and
    /// not logged, or today while still not done (today is a grace
    /// day, as for streaks).
    case notCounted
    /// The schedule counted the day (`FrequencyEvaluating.isCounted`).
    /// `done` is `DailyValue.compute(...) >= 1`: any positive record
    /// for binary, the full target for counter and timer, no slip for
    /// negative.
    case due(done: Bool)
    /// Not counted by the schedule but logged with a positive value
    /// (non-negative habits only). Counts as a time done, never as a
    /// miss.
    case offSchedule
}

/// The shared state every section calculator reads.
///
/// Day rules: habit days come from `calendar.startOfDay(for:
/// completion.date)` (completions are already stamped on their logical
/// day). Sessions belong to `dayBoundary.startOfDay(for: startedAt)`.
/// Tasks and Health intervals use civil days, `calendar.startOfDay`.
/// All of them are compared with the same `days` keys, which are
/// calendar midnights.
nonisolated public struct InsightsScope: Sendable {
    public let input: InsightsInput
    public let context: InsightsContext
    /// The period's logical days, oldest first, ending with today.
    public let days: [Date]
    /// The same number of days right before `days`, oldest first.
    public let previousDays: [Date]
    /// Per habit id: its completions grouped by calendar day.
    public let completionsByDay: [UUID: [Date: [Completion]]]

    public init(input: InsightsInput, context: InsightsContext) {
        self.input = input
        self.context = context
        let calendar = context.calendar
        let count = context.period.dayCount
        let days = InsightsScope.days(endingAt: context.today, count: count, calendar: calendar)
        self.days = days
        self.previousDays = InsightsScope.days(
            endingAt: InsightsScope.step(days.first ?? context.today, by: -1, calendar: calendar),
            count: count,
            calendar: calendar
        )
        var grouped: [UUID: [Date: [Completion]]] = [:]
        for habit in input.habits {
            grouped[habit.id] = Dictionary(grouping: habit.completions) { calendar.startOfDay(for: $0.date) }
        }
        self.completionsByDay = grouped
    }

    public var calendar: Calendar { context.calendar }
    public var today: Date { context.today }

    /// The logical day a session started on.
    public func sessionDay(_ session: InsightsSession) -> Date {
        context.dayBoundary.startOfDay(for: session.session.startedAt)
    }

    /// The civil day of an instant (tasks, Health).
    public func civilDay(_ instant: Date) -> Date {
        calendar.startOfDay(for: instant)
    }

    /// Positive (value > 0) records of a habit on a day.
    public func positiveRecords(of habit: InsightsHabit, on day: Date) -> [Completion] {
        (completionsByDay[habit.id]?[day] ?? []).filter { $0.value > 0 }
    }

    /// What `habit` did on `day`. See `HabitDayOutcome`.
    public func outcome(of habit: InsightsHabit, on day: Date) -> HabitDayOutcome {
        guard day <= today else { return .notCounted }
        let model = habit.habit
        let onDay = completionsByDay[habit.id]?[day] ?? []
        let counted = context.frequencyEvaluator.isCounted(
            habit: model,
            on: day,
            completions: habit.completions,
            calendar: calendar
        )
        guard counted else {
            if case .negative = model.type { return .notCounted }
            return onDay.contains { $0.value > 0 } ? .offSchedule : .notCounted
        }
        let done = DailyValue.compute(for: model, completionsOnDay: onDay) >= 1 - 1e-9
        if day == today {
            // A negative habit's day is not won until it ends.
            if case .negative = model.type { return .notCounted }
            if !done { return .notCounted }
        }
        return .due(done: done)
    }

    /// `count` calendar midnights ending at `last` (included), oldest
    /// first. Re-anchors on every step, so a zone whose day starts at
    /// 01:00 on a DST change still yields true midnights.
    public static func days(endingAt last: Date, count: Int, calendar: Calendar) -> [Date] {
        guard count > 0 else { return [] }
        var result: [Date] = [calendar.startOfDay(for: last)]
        while result.count < count {
            result.append(step(result[result.count - 1], by: -1, calendar: calendar))
        }
        return result.reversed()
    }

    /// The calendar midnight `offset` days from `day`.
    public static func step(_ day: Date, by offset: Int, calendar: Calendar) -> Date {
        let moved = calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: day)) ?? day
        return calendar.startOfDay(for: moved)
    }
}

/// Builds an `InsightsReport` from values. Pure: no SwiftData, no UI,
/// no clock other than `context.now`.
///
/// Each section is its own `static func` in an
/// `InsightsCalculator+<Section>.swift` file, so sections can change
/// and be tested one at a time. Highlights come last because they read
/// the other sections.
nonisolated public struct InsightsCalculator: Sendable {
    public init() {}

    public func report(input: InsightsInput, context: InsightsContext) -> InsightsReport {
        let scope = InsightsScope(input: input, context: context)
        var report = InsightsReport(period: context.period, days: scope.days)
        report.isEmpty = input.habits.isEmpty && input.tasks.isEmpty && input.sessions.isEmpty
        report.pulse = Self.pulse(scope)
        report.activity = Self.activity(scope)
        report.focus = Self.focus(scope)
        report.categories = Self.categories(scope)
        report.sleep = Self.sleep(scope)
        report.movement = Self.movement(scope)
        report.habits = Self.habits(scope)
        report.tasks = Self.tasks(scope)
        report.goals = Self.goals(scope)
        report.rhythm = Self.rhythm(scope)
        report.allTime = Self.allTime(scope)
        report.highlights = Self.highlights(report, scope)
        return report
    }
}
