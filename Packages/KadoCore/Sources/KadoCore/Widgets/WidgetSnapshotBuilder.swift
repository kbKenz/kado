import Foundation
import SwiftData
import WidgetKit

/// Builds a `WidgetSnapshot` from SwiftData state. Called on the
/// app side (main process) after every mutation so the widget
/// always reads fresh data.
@MainActor
public enum WidgetSnapshotBuilder {
    /// How many days `rebuildAndWrite` computes ahead. A week: someone
    /// who leaves the app closed that long still sees the right due set
    /// each morning.
    nonisolated public static let horizonDays = 7

    /// Gather everything the widgets need from `context` and
    /// serialize to a single `WidgetSnapshot` value.
    ///
    /// The three services default to implementations built on the
    /// `calendar` passed in. They are resolved in the body rather
    /// than as default arguments because a default argument cannot
    /// reference another parameter — spelling them
    /// `= DefaultFrequencyEvaluator()` silently pinned them to
    /// `Calendar.current` while the rest of the build honoured the
    /// caller's calendar, which makes any non-UTC machine disagree
    /// with a UTC-pinned test.
    public static func build(
        from context: ModelContext,
        asOf reference: Date = .now,
        calendar: Calendar = .current,
        matrixWindowDays: Int = 7,
        scoreCalculator: (any HabitScoreCalculating)? = nil,
        streakCalculator: (any StreakCalculating)? = nil,
        frequencyEvaluator: (any FrequencyEvaluating)? = nil
    ) -> WidgetSnapshot {
        let services = Services(
            calendar: calendar,
            score: scoreCalculator,
            streak: streakCalculator,
            frequency: frequencyEvaluator
        )
        let source = Source(context: context)
        let scores = source.habits.reduce(into: [UUID: Double]()) { scores, habit in
            scores[habit.id] = services.score.currentScore(
                for: habit,
                completions: source.completions(for: habit),
                asOf: reference
            )
        }
        return build(
            source,
            asOf: reference,
            scores: scores,
            services: services,
            matrixWindowDays: matrixWindowDays
        )
    }

    /// The day `reference` falls in plus the `horizonDays - 1` after it,
    /// each computed as of that morning with nothing further logged.
    ///
    /// Nothing here knows it is looking ahead: every calculator answers
    /// for the reference day it is given, and a future day simply has
    /// no completions yet. That is exactly what the app itself would
    /// render that morning — and anything logged in the meantime
    /// rewrites the whole series, so a later day is never stale
    /// relative to what the app knows.
    ///
    /// Costs about one `build`, not seven. The store is read once, and
    /// the score — an EMA walked day by day from the habit's first
    /// completion, by far the expensive part — is walked once per habit
    /// to the last day, each day reading its own value off that walk;
    /// `currentScore(asOf:)` is the prefix of the same fold, so the
    /// numbers are identical. Everything else is re-derived per day,
    /// the best streak included: it looks like a maximum nothing
    /// unlogged could raise, but for a negative habit an unlogged day
    /// is a clean one, and two of them in a row *do* raise it.
    /// `seriesDaysMatchStandaloneBuilds` holds every day of a series to
    /// a standalone build of that day, across DST shapes.
    public static func buildSeries(
        from context: ModelContext,
        asOf reference: Date = .now,
        calendar: Calendar = .current,
        horizonDays: Int = Self.horizonDays,
        matrixWindowDays: Int = 7,
        scoreCalculator: (any HabitScoreCalculating)? = nil,
        streakCalculator: (any StreakCalculating)? = nil,
        frequencyEvaluator: (any FrequencyEvaluating)? = nil
    ) -> WidgetSnapshotSeries {
        buildSeries(
            source: Source(context: context),
            asOf: reference,
            calendar: calendar,
            horizonDays: horizonDays,
            matrixWindowDays: matrixWindowDays,
            scoreCalculator: scoreCalculator,
            streakCalculator: streakCalculator,
            frequencyEvaluator: frequencyEvaluator
        )
    }

    /// `buildSeries(from:)` on a store already read into values. Pure,
    /// so it can run off the main actor: the store read is the only
    /// part that needs the context.
    nonisolated public static func buildSeries(
        source: Source,
        asOf reference: Date = .now,
        calendar: Calendar = .current,
        horizonDays: Int = Self.horizonDays,
        matrixWindowDays: Int = 7,
        scoreCalculator: (any HabitScoreCalculating)? = nil,
        streakCalculator: (any StreakCalculating)? = nil,
        frequencyEvaluator: (any FrequencyEvaluating)? = nil
    ) -> WidgetSnapshotSeries {
        let services = Services(
            calendar: calendar,
            score: scoreCalculator,
            streak: streakCalculator,
            frequency: frequencyEvaluator
        )
        let first = calendar.startOfDay(for: reference)
        let days = (0..<max(horizonDays, 1)).compactMap { offset in
            calendar.date(byAdding: .day, value: offset, to: first)
        }
        guard let last = days.last else { return .empty }

        var scoresByDay: [Date: [UUID: Double]] = [:]
        for habit in source.habits {
            let completions = source.completions(for: habit)
            let history = services.score.scoreHistory(
                for: habit,
                completions: completions,
                from: habit.effectiveStart(completions: completions, calendar: calendar),
                to: last
            )
            // Keyed through `startOfDay` on both sides so the match does
            // not ride on the walk and the series agreeing about which
            // instant a day begins at.
            let byDay = Dictionary(
                history.map { (calendar.startOfDay(for: $0.date), $0.score) },
                uniquingKeysWith: { $1 }
            )
            for day in days {
                // A day before the habit existed has no entry, and
                // `currentScore` answers zero for it too.
                scoresByDay[day, default: [:]][habit.id] = byDay[calendar.startOfDay(for: day)] ?? 0
            }
        }

        return WidgetSnapshotSeries(
            generatedAt: .now,
            days: days.map { day in
                build(
                    source,
                    asOf: day,
                    scores: scoresByDay[day] ?? [:],
                    services: services,
                    matrixWindowDays: matrixWindowDays
                )
            }
        )
    }

    /// Convenience: build from the production container, write to the
    /// App Group JSON, and tell WidgetKit — in one shot. Safe to call
    /// from any mutation site.
    ///
    /// The reload lives here, not with the callers, for the same reason
    /// the day-complete celebration does: this is the one call every
    /// path already makes — the views through `WidgetReloader`, the
    /// intents directly, the app at launch, at the day edge and on
    /// foregrounding into a new day. A file written without a reload
    /// leaves the Home Screen on the old one for up to an hour, and
    /// with the reload paired by hand at each site that is exactly what
    /// the launch path did. Reporting the day's progress here likewise
    /// means no surface can complete the day without the confetti
    /// hearing about it.
    public static func rebuildAndWrite(using context: ModelContext) {
        let pass = Pass(context: context)
        let series = pass.buildSeries()
        pass.write(series)
        WidgetCenter.shared.reloadAllTimelines()
        // Today's progress only: the days after it are computed with
        // nothing logged, and a day that hasn't started can't be done.
        if let today = series.days.first {
            DayCompletionCelebration.shared.observe(today.dayProgress, on: pass.day)
        }
    }

    /// `rebuildAndWrite` with only the store read on the main actor.
    /// The series, its JSON and the file write — the part that grows
    /// with history — run detached, so a tap never waits on them.
    ///
    /// Today's progress comes from the read straight away rather than
    /// from the finished series, so the confetti is not held up by the
    /// build either. `afterRead` gets the same values, for a caller
    /// that would otherwise read the store again (reminders).
    ///
    /// Two passes can overlap here, or overlap a synchronous
    /// `rebuildAndWrite`; the ticket taken at read time keeps a slower,
    /// older pass from landing over a newer file.
    public static func rebuildAndWriteInBackground(
        using context: ModelContext,
        afterRead: (Source) -> Void = { _ in }
    ) async {
        let rebuild = beginBackgroundRebuild(using: context)
        afterRead(rebuild.source)
        await rebuild.finish()
    }

    /// The main-actor half of `rebuildAndWriteInBackground`: reads the
    /// store and reports today's progress now, and returns the rest of
    /// the pass. That rest holds only values, so a caller that awaits
    /// it need not keep `context` alive meanwhile — a context outliving
    /// its container traps when its save timer fires.
    public static func beginBackgroundRebuild(using context: ModelContext) -> BackgroundRebuild {
        let rebuild = BackgroundRebuild(context: context)
        DayCompletionCelebration.shared.observe(rebuild.pass.todayProgress(), on: rebuild.pass.day)
        return rebuild
    }

    /// A background rebuild whose store read is done.
    nonisolated public struct BackgroundRebuild: Sendable {
        fileprivate let pass: Pass

        @MainActor
        fileprivate init(context: ModelContext) {
            pass = Pass(context: context)
        }

        /// The store as the pass read it.
        public var source: Source { pass.source }

        /// Builds and writes the series off the main actor, then asks
        /// WidgetKit to reload.
        @MainActor
        public func finish() async {
            let pass = pass
            await Task.detached(priority: .utility) {
                pass.write(pass.buildSeries())
            }.value
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    /// Today's tally as `build` counts it — the due-or-logged habits
    /// and how many of them are done — without building the rest of
    /// the day.
    nonisolated public static func dayProgress(
        source: Source,
        asOf reference: Date,
        calendar: Calendar = .current,
        frequencyEvaluator: (any FrequencyEvaluating)? = nil
    ) -> DayProgress {
        let services = Services(calendar: calendar, score: nil, streak: nil, frequency: frequencyEvaluator)
        let due = dueRows(source, asOf: reference, services: services)
        return DayProgress(
            completed: due.filter { $0.state.isDone(for: $0.habit) }.count,
            total: due.count
        )
    }

    /// One rebuild's inputs, all taken in the same main-actor turn: the
    /// logical day and week start the widget can't resolve itself, the
    /// store as values, and the ticket that orders its write against
    /// every other pass.
    nonisolated fileprivate struct Pass: Sendable {
        let day: Date
        let calendar: Calendar
        let source: Source
        let ticket: Int

        @MainActor
        init(context: ModelContext) {
            // Widgets render a pre-computed snapshot and never ask what
            // day it is — nor which day a week opens on — so both
            // preferences have to be resolved here, once. The week
            // start reaches the streak calculator, whose `.daysPerWeek`
            // count is bucketed into whole calendar weeks.
            day = DayStartDefaults.boundary().startOfDay(for: .now)
            calendar = WeekStartDefaults.calendar()
            source = Source(context: context)
            ticket = WidgetSnapshotWriteOrder.shared.ticket()
        }

        func buildSeries() -> WidgetSnapshotSeries {
            WidgetSnapshotBuilder.buildSeries(source: source, asOf: day, calendar: calendar)
        }

        func todayProgress() -> DayProgress {
            WidgetSnapshotBuilder.dayProgress(source: source, asOf: day, calendar: calendar)
        }

        func write(_ series: WidgetSnapshotSeries) {
            WidgetSnapshotWriteOrder.shared.write(series, ticket: ticket)
        }
    }

    // MARK: - One day

    /// One day's snapshot from an already-read `Source`, with the
    /// per-habit scores handed in so a series can share one walk.
    nonisolated private static func build(
        _ source: Source,
        asOf reference: Date,
        scores: [UUID: Double],
        services: Services,
        matrixWindowDays: Int
    ) -> WidgetSnapshot {
        let calendar = services.calendar

        // Compute per-habit stats once. Reused across the three
        // WidgetHabit construction sites (top-level, today rows,
        // matrix rows) so consumers see consistent values.
        struct HabitStats { let current: Int; let best: Int; let score: Double }
        var statsByID: [UUID: HabitStats] = [:]
        for habit in source.habits {
            let completions = source.completions(for: habit)
            statsByID[habit.id] = HabitStats(
                current: services.streak.current(for: habit, completions: completions, asOf: reference),
                best: services.streak.best(for: habit, completions: completions, asOf: reference),
                score: scores[habit.id] ?? 0
            )
        }

        func makeWidgetHabit(from habit: Habit) -> WidgetHabit {
            let stats = statsByID[habit.id]
            return WidgetHabit(
                id: habit.id,
                name: habit.name,
                color: habit.color,
                icon: habit.icon,
                typeKind: mapTypeKind(habit.type),
                target: mapTarget(habit.type),
                currentStreak: stats?.current ?? 0,
                bestStreak: stats?.best ?? 0,
                currentScore: stats?.score ?? 0
            )
        }

        let widgetHabits = source.habits.map(makeWidgetHabit(from:))

        var todayRows: [WidgetTodayRow] = []
        var completed = 0
        for (habit, state) in dueRows(source, asOf: reference, services: services) {
            let widgetHabit = makeWidgetHabit(from: habit)
            todayRows.append(
                WidgetTodayRow(
                    habit: widgetHabit,
                    status: mapStatus(state.status),
                    progress: state.progress,
                    valueToday: state.valueToday,
                    // Both off `widgetHabit`, which already carries
                    // them from the same `statsByID` lookup. Reading
                    // the dictionary again here would leave two paths
                    // to one number, and a later change to how either
                    // is derived would have to find both.
                    streak: widgetHabit.currentStreak,
                    scorePercent: widgetHabit.scorePercent
                )
            )
            // Not `status == .complete`: for a negative habit that is a
            // slip, and the day's tally must not count giving in as
            // getting it done.
            if state.isDone(for: habit) { completed += 1 }
        }

        // Matrix window (last N days ending today).
        let today = calendar.startOfDay(for: reference)
        let matrixDays: [Date] = (0..<matrixWindowDays).reversed().compactMap { offset in
            calendar.date(byAdding: .day, value: -offset, to: today)
        }
        let matrix = OverviewMatrix.compute(
            habits: source.habits,
            completions: source.allCompletions,
            days: matrixDays,
            today: reference,
            calendar: calendar,
            frequencyEvaluator: services.frequency
        )
        let widgetMatrix = matrix.map { row in
            WidgetMatrixRow(
                habit: makeWidgetHabit(from: row.habit),
                cells: row.days.map(mapDayCell)
            )
        }

        return WidgetSnapshot(
            // The true build time, not `reference` — under a non-zero
            // day-start hour `reference` is the logical day's midnight,
            // which would make this field quietly untrue.
            generatedAt: .now,
            habits: widgetHabits,
            today: todayRows,
            totalDueToday: todayRows.count,
            completedToday: completed,
            matrix: widgetMatrix,
            matrixDays: matrixDays,
            logicalDay: today
        )
    }

    /// The habits a day's Today list shows, each with its state. Shared
    /// by the snapshot's rows and `dayProgress`, so the tally the
    /// confetti hears is the one the widget shows.
    nonisolated private static func dueRows(
        _ source: Source,
        asOf reference: Date,
        services: Services
    ) -> [(habit: Habit, state: HabitRowState)] {
        source.habits.compactMap { habit in
            let completions = source.completions(for: habit)
            // Without the "or logged today" arm a habit vanishes from
            // the widget the moment it is completed past a weekly
            // quota, taking its own tick out of `completedToday`.
            // Shared with the Today tab so the two can't drift.
            guard services.frequency.isDueOrLogged(
                habit: habit,
                on: reference,
                completions: completions,
                calendar: services.calendar
            ) else {
                return nil
            }
            let state = HabitRowState.resolve(
                habit: habit,
                completions: completions,
                calendar: services.calendar,
                asOf: reference
            )
            return (habit, state)
        }
    }

    // MARK: - Inputs

    /// The calculators a build runs on, resolved once per call rather
    /// than per day.
    nonisolated private struct Services: Sendable {
        let calendar: Calendar
        let score: any HabitScoreCalculating
        let streak: any StreakCalculating
        let frequency: any FrequencyEvaluating

        init(
            calendar: Calendar,
            score: (any HabitScoreCalculating)?,
            streak: (any StreakCalculating)?,
            frequency: (any FrequencyEvaluating)?
        ) {
            let frequency = frequency ?? DefaultFrequencyEvaluator(calendar: calendar)
            self.calendar = calendar
            self.frequency = frequency
            self.score = score
                ?? DefaultHabitScoreCalculator(calendar: calendar, frequencyEvaluator: frequency)
            self.streak = streak ?? DefaultStreakCalculator(calendar: calendar)
        }
    }

    /// Everything the builder reads from the store, pulled once — and
    /// once only for a whole series. Faulting every habit's completions
    /// is the one SwiftData cost here, and it does not depend on the
    /// day being built. Plain values, so the build can take them off
    /// the main actor.
    nonisolated public struct Source: Sendable {
        /// Active habits, in the user's order.
        public let habits: [Habit]
        private let completionsByHabit: [UUID: [Completion]]
        /// The active habits' completions, in habit order.
        public let allCompletions: [Completion]

        @MainActor
        public init(context: ModelContext) {
            let descriptor = FetchDescriptor<HabitRecord>(
                sortBy: [SortDescriptor(\.sortOrder)]
            )
            let records = ((try? context.fetch(descriptor)) ?? []).filter { $0.archivedAt == nil }
            var byHabit: [UUID: [Completion]] = [:]
            for record in records {
                byHabit[record.id] = (record.completions ?? []).compactMap(\.snapshot)
            }
            habits = records.map(\.snapshot)
            completionsByHabit = byHabit
            allCompletions = habits.flatMap { byHabit[$0.id] ?? [] }
        }

        public func completions(for habit: Habit) -> [Completion] {
            completionsByHabit[habit.id] ?? []
        }
    }

    // MARK: - Mapping helpers

    nonisolated private static func mapTypeKind(_ type: HabitType) -> WidgetHabitTypeKind {
        switch type {
        case .binary: .binary
        case .negative: .negative
        case .counter: .counter
        case .timer: .timer
        }
    }

    nonisolated private static func mapTarget(_ type: HabitType) -> Double? {
        switch type {
        case .binary, .negative: nil
        case .counter(let target): target
        case .timer(let targetSeconds): targetSeconds
        }
    }

    nonisolated private static func mapStatus(_ status: HabitRowState.Status) -> WidgetStatus {
        switch status {
        case .none: .none
        case .partial: .partial
        case .complete: .complete
        }
    }

    nonisolated private static func mapDayCell(_ cell: DayCell) -> WidgetDayCell {
        switch cell {
        case .future: .future
        // The widget doesn't edit, so it has no use for the distinction.
        case .notDue, .beforeStart: .notDue
        case .scored(let v): .scored(v)
        case .offSchedule(let v): .offSchedule(v)
        }
    }
}
