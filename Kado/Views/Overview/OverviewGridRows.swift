import Foundation
import KadoCore

/// The Grid's rows and chip metrics, kept between renders so that only
/// a habit whose values changed is computed again.
///
/// The score reads a habit's whole history, so scoring every habit on
/// each render made one popover step cost as much as opening the Grid.
/// A habit is reused only when every field of its snapshot and of each
/// of its completions is unchanged (`Habit` and `Completion` compare by
/// id alone, so `==` can't be used here), and the whole cache is
/// dropped when the day, the calendar or a calculator changes. What
/// comes out is what `OverviewMatrix.compute` plus the two calculators
/// give on the same inputs: `OverviewGridRowsTests` holds it to that.
///
/// A reference type held in `@State` and not observed: filling it
/// during a render triggers no other render.
final class OverviewGridRows {
    struct Metrics: Equatable {
        var streak: Int
        var scorePercent: Int
    }

    struct Output {
        var rows: [MatrixRow]
        var metrics: [UUID: Metrics]
    }

    /// Everything a row reads besides its habit and completions.
    private struct Context: Equatable {
        var days: [Date]
        var today: Date
        var now: Date
        var calendar: Calendar
        var services: [ObjectIdentifier]
    }

    private struct Entry {
        var habit: Habit
        var completions: [Completion]
        /// Nil for an archived habit, which the matrix leaves out.
        var row: MatrixRow?
        var metrics: Metrics
    }

    private var context: Context?
    private var entries: [UUID: Entry] = [:]

    func compute(
        _ snapshots: [(habit: Habit, completions: [Completion])],
        days: [Date],
        today: Date,
        now: Date,
        calendar: Calendar,
        frequencyEvaluator: any FrequencyEvaluating,
        streakCalculator: any StreakCalculating,
        scoreCalculator: any HabitScoreCalculating
    ) -> Output {
        let context = Context(
            days: days,
            today: today,
            now: now,
            calendar: calendar,
            services: [
                ObjectIdentifier(type(of: frequencyEvaluator)),
                ObjectIdentifier(type(of: streakCalculator)),
                ObjectIdentifier(type(of: scoreCalculator)),
            ]
        )
        if context != self.context {
            self.context = context
            entries = [:]
        }

        var next: [UUID: Entry] = [:]
        for (habit, completions) in snapshots {
            if let entry = entries[habit.id],
               Self.sameValues(entry.habit, habit),
               Self.sameValues(entry.completions, completions) {
                next[habit.id] = entry
                continue
            }
            // One habit at a time gives the same row: the matrix only
            // ever reads a habit's own completions.
            let row = OverviewMatrix.compute(
                habits: [habit],
                completions: completions,
                days: days,
                today: today,
                calendar: calendar,
                frequencyEvaluator: frequencyEvaluator
            ).first
            let streak = streakCalculator.current(for: habit, completions: completions, asOf: now)
            let score = scoreCalculator.currentScore(for: habit, completions: completions, asOf: now)
            next[habit.id] = Entry(
                habit: habit,
                completions: completions,
                row: row,
                metrics: Metrics(streak: streak, scorePercent: Int((score * 100).rounded()))
            )
        }
        // Also drops the habits that are gone.
        entries = next

        // The matrix's own order: active habits by `sortOrder`.
        let rows = snapshots.map(\.habit)
            .filter { $0.archivedAt == nil }
            .sorted { $0.sortOrder < $1.sortOrder }
            .compactMap { next[$0.id]?.row }
        return Output(rows: rows, metrics: next.mapValues(\.metrics))
    }

    /// Every stored field, by hand: a field added to `Habit` must be
    /// added here too (`OverviewGridRowsTests.comparedFieldsAreComplete`
    /// fails until it is).
    private static func sameValues(_ lhs: Habit, _ rhs: Habit) -> Bool {
        lhs.id == rhs.id
            && lhs.name == rhs.name
            && lhs.frequency == rhs.frequency
            && lhs.type == rhs.type
            && lhs.createdAt == rhs.createdAt
            && lhs.archivedAt == rhs.archivedAt
            && lhs.color == rhs.color
            && lhs.icon == rhs.icon
            && lhs.remindersEnabled == rhs.remindersEnabled
            && lhs.reminderHour == rhs.reminderHour
            && lhs.reminderMinute == rhs.reminderMinute
            && lhs.sortOrder == rhs.sortOrder
            && lhs.goalID == rhs.goalID
            && lhs.category == rhs.category
    }

    private static func sameValues(_ lhs: [Completion], _ rhs: [Completion]) -> Bool {
        guard lhs.count == rhs.count else { return false }
        return zip(lhs, rhs).allSatisfy { a, b in
            a.id == b.id
                && a.habitID == b.habitID
                && a.date == b.date
                && a.value == b.value
                && a.note == b.note
        }
    }
}
