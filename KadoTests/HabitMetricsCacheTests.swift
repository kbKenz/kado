import Foundation
import Testing
import KadoCore
@testable import Kado

/// The detail screen's score and streaks are cached; a key that missed
/// an input would freeze them after an edit (issue #80). Every input
/// that can move them has to bust the cache, and nothing else.
@Suite("HabitMetricsCache") @MainActor
struct HabitMetricsCacheTests {
    private let calendar = TestCalendar.utc
    private let score = DefaultHabitScoreCalculator(calendar: TestCalendar.utc)
    private let streak = DefaultStreakCalculator(calendar: TestCalendar.utc)

    private func key(_ habit: Habit, _ completions: [Completion], today: Date = TestCalendar.day(0), calendar: Calendar? = nil) -> HabitMetricsCache.Key {
        HabitMetricsCache.Key(
            habit: habit,
            completions: completions,
            today: today,
            calendar: calendar ?? self.calendar,
            scoreCalculator: score,
            streakCalculator: streak
        )
    }

    /// Runs the cache the way the view does and counts the recomputes.
    private final class Counter { var computes = 0 }

    private func lookup(_ cache: HabitMetricsCache, _ key: HabitMetricsCache.Key, _ counter: Counter) {
        _ = cache.metrics(for: key) {
            counter.computes += 1
            return HabitMetricsCache.Metrics(score: 0, currentStreak: 0, bestStreak: 0)
        }
    }

    private var habit: Habit {
        Habit(name: "Run", frequency: .daily, type: .counter(target: 3), createdAt: TestCalendar.day(-30))
    }

    @Test("Same inputs reuse the cached metrics")
    func reusesForSameInputs() {
        let habit = self.habit
        let completions = (0..<10).map { Completion(habitID: habit.id, date: TestCalendar.day(-$0), value: 2) }
        let cache = HabitMetricsCache()
        let counter = Counter()
        lookup(cache, key(habit, completions), counter)
        lookup(cache, key(habit, completions), counter)
        #expect(counter.computes == 1)
    }

    @Test("Every input that can move the score or a streak recomputes")
    func recomputesOnEachInput() {
        let habit = self.habit
        let completion = Completion(habitID: habit.id, date: TestCalendar.day(-1), value: 1)
        let base = key(habit, [completion])

        var stepped = completion; stepped.value = 2
        var moved = completion; moved.date = TestCalendar.day(-2)
        var noted = completion; noted.note = "felt good"
        var otherFrequency = habit; otherFrequency.frequency = .daysPerWeek(3)
        var otherType = habit; otherType.type = .counter(target: 5)
        var otherCreated = habit; otherCreated.createdAt = TestCalendar.day(-60)
        var archived = habit; archived.archivedAt = TestCalendar.day(0)
        var paris = calendar; paris.timeZone = TimeZone(identifier: "Europe/Paris")!

        let changed: [HabitMetricsCache.Key] = [
            key(habit, [stepped]),
            key(habit, [moved]),
            key(habit, [noted]),
            key(habit, []),
            key(habit, [completion, Completion(habitID: habit.id, date: TestCalendar.day(-3))]),
            key(otherFrequency, [completion]),
            key(otherType, [completion]),
            key(otherCreated, [completion]),
            key(archived, [completion]),
            key(habit, [completion], today: TestCalendar.day(1)),
            key(habit, [completion], calendar: paris),
        ]
        for next in changed {
            // `Completion` and `Habit` compare by id alone; the key must not.
            #expect(next != base)
            let cache = HabitMetricsCache()
            let counter = Counter()
            lookup(cache, base, counter)
            lookup(cache, next, counter)
            #expect(counter.computes == 2)
        }
    }

    @Test("Cached metrics equal a fresh computation after each edit")
    func cachedEqualsFresh() {
        let habit = self.habit
        var completions = (0..<20).map { Completion(habitID: habit.id, date: TestCalendar.day(-$0 * 2), value: 3) }
        let cache = HabitMetricsCache()
        func viaCache() -> HabitMetricsCache.Metrics {
            cache.metrics(for: key(habit, completions)) { fresh() }
        }
        func fresh() -> HabitMetricsCache.Metrics {
            HabitMetricsCache.Metrics(
                score: score.currentScore(for: habit, completions: completions, asOf: TestCalendar.day(0)),
                currentStreak: streak.current(for: habit, completions: completions, asOf: TestCalendar.day(0)),
                bestStreak: streak.best(for: habit, completions: completions, asOf: TestCalendar.day(0))
            )
        }
        #expect(viaCache() == fresh())
        completions[0].value = 1
        #expect(viaCache() == fresh())
        completions.append(Completion(habitID: habit.id, date: TestCalendar.day(-1), value: 3))
        #expect(viaCache() == fresh())
        completions.removeFirst()
        #expect(viaCache() == fresh())
    }
}
