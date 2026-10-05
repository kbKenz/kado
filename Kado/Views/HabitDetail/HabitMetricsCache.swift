import Foundation
import KadoCore

/// The detail screen's score and streaks, computed again only when an
/// input changes. The score walks every day since the habit started,
/// and `HabitDetailView.body` also runs for changes that cannot move
/// it (a quick-log haptic event, a second refresh after the same save).
///
/// The key compares each input by value. `Habit` and `Completion`
/// compare by `id` only, so they can't be the key themselves: a
/// stepped counter or a moved date would read as "unchanged" and
/// freeze the numbers, which is issue #80 again.
final class HabitMetricsCache {
    struct Metrics: Equatable {
        let score: Double
        let currentStreak: Int
        let bestStreak: Int
    }

    nonisolated struct Key: Equatable {
        struct CompletionFields: Equatable {
            let id: UUID
            let habitID: UUID
            let date: Date
            let value: Double
            let note: String?
        }

        let habitID: UUID
        let frequency: Frequency
        let type: HabitType
        let createdAt: Date
        let archivedAt: Date?
        let completions: [CompletionFields]
        let today: Date
        /// The calculators come from the environment and can't be
        /// compared. The app builds them from this calendar, so a
        /// change to them (the week-start setting) changes it too.
        let calendar: Calendar
        let calculatorTypes: [ObjectIdentifier]

        init(
            habit: Habit,
            completions: [Completion],
            today: Date,
            calendar: Calendar,
            scoreCalculator: any HabitScoreCalculating,
            streakCalculator: any StreakCalculating
        ) {
            habitID = habit.id
            frequency = habit.frequency
            type = habit.type
            createdAt = habit.createdAt
            archivedAt = habit.archivedAt
            self.completions = completions.map {
                CompletionFields(id: $0.id, habitID: $0.habitID, date: $0.date, value: $0.value, note: $0.note)
            }
            self.today = today
            self.calendar = calendar
            calculatorTypes = [
                ObjectIdentifier(Swift.type(of: scoreCalculator)),
                ObjectIdentifier(Swift.type(of: streakCalculator)),
            ]
        }
    }

    private var last: (key: Key, metrics: Metrics)?

    func metrics(for key: Key, compute: () -> Metrics) -> Metrics {
        if let last, last.key == key { return last.metrics }
        let metrics = compute()
        last = (key, metrics)
        return metrics
    }
}
