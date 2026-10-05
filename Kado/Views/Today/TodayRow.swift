import Foundation
import KadoCore

/// Value-type snapshot of one row in the Today list.
///
/// `ForEach` retains the collection it was handed and re-reads
/// `Identifiable.id` during the list diff — and that diff can run
/// *after* a dev-mode `ModelContainer` swap has invalidated every
/// `HabitRecord` the previous store vended. Reading any persisted
/// property on an invalidated managed object traps inside SwiftData,
/// so the list must never hold one (issue #63).
///
/// Handing `ForEach` plain structs leaves nothing to invalidate.
/// Mutations resolve the record by `id` against the live `@Query`,
/// which always reflects whichever store is currently mounted.
struct TodayRow: Identifiable {
    let habit: Habit
    let completions: [Completion]
    /// The earliest of the habit's creation and every record's date, the
    /// day strip's lower bound. Kept apart from `completions` because a
    /// record whose habit link is still unset mid-import has no snapshot
    /// but still counts here.
    let earliestDate: Date

    var id: UUID { habit.id }

    init(habit: Habit, completions: [Completion]) {
        self.habit = habit
        self.completions = completions
        self.earliestDate = completions.lazy.map(\.date).reduce(habit.createdAt, min)
    }

    init(_ record: HabitRecord) {
        var completions: [Completion] = []
        var earliest = record.createdAt
        // One walk over the records, reading each one once.
        for completion in record.completions ?? [] {
            if let snapshot = completion.snapshot {
                completions.append(snapshot)
                earliest = min(earliest, snapshot.date)
            } else {
                earliest = min(earliest, completion.date)
            }
        }
        self.habit = record.snapshot
        self.completions = completions
        self.earliestDate = earliest
    }
}

extension TodayRow {
    /// Snapshots every record, then splits the rows into the two
    /// sections Today renders: the ones the schedule asks for today
    /// (or that already have progress logged today), and the rest.
    ///
    /// The snapshot happens once, up front, so the two sections and
    /// every derived metric read the same frozen data — and so nothing
    /// downstream keeps a reference to a managed object.
    static func sections(
        from records: [HabitRecord],
        on now: Date,
        evaluator: any FrequencyEvaluating,
        calendar: Calendar
    ) -> (due: [TodayRow], other: [TodayRow]) {
        // Spelled out rather than `map(TodayRow.init)`: passing a
        // MainActor-isolated initializer as a function value to a
        // nonisolated generic loses the isolation and warns.
        sections(from: records.map({ TodayRow($0) }), on: now, evaluator: evaluator, calendar: calendar)
    }

    /// Same split, over rows already snapshotted, so a view that needs
    /// the rows for something else too snapshots only once.
    static func sections(
        from rows: [TodayRow],
        on now: Date,
        evaluator: any FrequencyEvaluating,
        calendar: Calendar
    ) -> (due: [TodayRow], other: [TodayRow]) {
        var due: [TodayRow] = []
        var other: [TodayRow] = []
        for row in rows {
            // Days before a habit's first day aren't its days at all;
            // listing it there would let a tap backdate its start (#104).
            // Note: raising "Day starts at" after creating a habit between
            // midnight and the new rollover can hide it until the rollover
            // (createdAt falls on the next logical day).
            guard row.habit.isListed(on: now, completions: row.completions, calendar: calendar) else {
                continue
            }
            let isDue = evaluator.isDueOrLogged(
                habit: row.habit,
                on: now,
                completions: row.completions,
                calendar: calendar
            )
            if isDue {
                due.append(row)
            } else {
                other.append(row)
            }
        }
        return (due, other)
    }
}

/// Navigation value for a pushed habit-detail screen.
///
/// Carries the habit's id rather than the `HabitRecord` itself: a
/// `NavigationPath` outlives a dev-mode container swap, and a managed
/// object it retained from the previous store traps the moment SwiftUI
/// re-reads it. `HabitDetailLoader` turns the id back into a live
/// record against the store that is mounted now.
struct HabitRoute: Hashable {
    let id: UUID
}
