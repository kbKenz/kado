import Foundation
import Testing
@testable import Kado
import KadoCore

/// `OverviewGridRows` reuses a habit's row and chip metrics while that
/// habit and its completions are unchanged. Whatever it reuses must be
/// what a fresh computation would give, which is what the Grid did on
/// every render before the cache.
@Suite("OverviewGridRows")
@MainActor
struct OverviewGridRowsTests {
    private let calendar = TestCalendar.utc
    private var now: Date { TestCalendar.referenceDate }
    private var today: Date { calendar.startOfDay(for: now) }

    private var days: [Date] {
        (0..<30).reversed().map { calendar.date(byAdding: .day, value: -$0, to: today)! }
    }

    private typealias Snapshot = (habit: Habit, completions: [Completion])

    /// The Grid's computation before the cache, kept here as the reference.
    private func fresh(
        _ snapshots: [Snapshot],
        now: Date? = nil,
        calendar: Calendar? = nil,
        scoreCalculator: any HabitScoreCalculating = DefaultHabitScoreCalculator(calendar: TestCalendar.utc)
    ) -> OverviewGridRows.Output {
        let calendar = calendar ?? self.calendar
        let now = now ?? self.now
        let today = calendar.startOfDay(for: now)
        let rows = OverviewMatrix.compute(
            habits: snapshots.map(\.habit),
            completions: snapshots.flatMap(\.completions),
            days: days(endingAt: today, calendar: calendar),
            today: today,
            calendar: calendar,
            frequencyEvaluator: DefaultFrequencyEvaluator(calendar: calendar)
        )
        let streaks = DefaultStreakCalculator(calendar: calendar)
        let metrics = Dictionary(uniqueKeysWithValues: snapshots.map { habit, completions in
            let streak = streaks.current(for: habit, completions: completions, asOf: now)
            let score = scoreCalculator.currentScore(for: habit, completions: completions, asOf: now)
            return (habit.id, OverviewGridRows.Metrics(streak: streak, scorePercent: Int((score * 100).rounded())))
        })
        return OverviewGridRows.Output(rows: rows, metrics: metrics)
    }

    private func cached(
        _ cache: OverviewGridRows,
        _ snapshots: [Snapshot],
        now: Date? = nil,
        calendar: Calendar? = nil,
        scoreCalculator: any HabitScoreCalculating = DefaultHabitScoreCalculator(calendar: TestCalendar.utc)
    ) -> OverviewGridRows.Output {
        let calendar = calendar ?? self.calendar
        let now = now ?? self.now
        let today = calendar.startOfDay(for: now)
        return cache.compute(
            snapshots,
            days: days(endingAt: today, calendar: calendar),
            today: today,
            now: now,
            calendar: calendar,
            frequencyEvaluator: DefaultFrequencyEvaluator(calendar: calendar),
            streakCalculator: DefaultStreakCalculator(calendar: calendar),
            scoreCalculator: scoreCalculator
        )
    }

    private func days(endingAt today: Date, calendar: Calendar) -> [Date] {
        (0..<30).reversed().map { calendar.date(byAdding: .day, value: -$0, to: today)! }
    }

    /// `MatrixRow` and `Habit` compare by id only, so the rows are also
    /// compared field by field on what the Grid draws.
    private func expectSame(_ lhs: OverviewGridRows.Output, _ rhs: OverviewGridRows.Output, _ comment: Comment) {
        #expect(lhs.rows == rhs.rows, comment)
        #expect(lhs.rows.map(\.habit.name) == rhs.rows.map(\.habit.name), comment)
        #expect(lhs.rows.map(\.habit.color) == rhs.rows.map(\.habit.color), comment)
        #expect(lhs.rows.map(\.habit.icon) == rhs.rows.map(\.habit.icon), comment)
        #expect(lhs.rows.map(\.habit.type) == rhs.rows.map(\.habit.type), comment)
        #expect(lhs.metrics == rhs.metrics, comment)
    }

    private func day(_ offset: Int, hour: Int = 9) -> Date {
        calendar.date(byAdding: .hour, value: hour, to: calendar.date(byAdding: .day, value: offset, to: today)!)!
    }

    private func fixture() -> [Snapshot] {
        let start = calendar.date(byAdding: .day, value: -60, to: today)!
        let daily = Habit(name: "Read", frequency: .daily, type: .binary, createdAt: start, sortOrder: 0)
        let weekly = Habit(name: "Gym", frequency: .daysPerWeek(3), type: .binary, createdAt: start, color: .green, sortOrder: 1)
        let everyOther = Habit(name: "Water plants", frequency: .everyNDays(2), type: .binary, createdAt: start, sortOrder: 2)
        let counter = Habit(name: "Glasses", frequency: .daily, type: .counter(target: 8), createdAt: start, sortOrder: 3)
        let negative = Habit(name: "Smoke", frequency: .daily, type: .negative, createdAt: start, sortOrder: 4)
        let fresh = Habit(name: "New", frequency: .daily, type: .binary, createdAt: today, sortOrder: 5)

        func log(_ habit: Habit, _ offsets: [Int], value: Double = 1) -> [Completion] {
            offsets.map { Completion(habitID: habit.id, date: day($0), value: value) }
        }
        return [
            (daily, log(daily, Array(stride(from: -40, through: 0, by: 1)).filter { $0 % 5 != 0 })),
            (weekly, log(weekly, [-20, -18, -15, -13, -11, -8, -6, -4, -1])),
            (everyOther, log(everyOther, [-30, -28, -26, -22, -20, -2])),
            (counter, log(counter, [-10, -9, -8, -3, -1], value: 5)),
            (negative, log(negative, [-12, -4], value: 1)),
            (fresh, []),
        ]
    }

    @Test("Matches a fresh computation through a run of edits")
    func matchesFreshThroughEdits() {
        let cache = OverviewGridRows()
        var snapshots = fixture()
        expectSame(cached(cache, snapshots), fresh(snapshots), "first render")
        expectSame(cached(cache, snapshots), fresh(snapshots), "unchanged render")

        // Step a counter, as the popover does.
        snapshots[3].completions[4].value = 8
        expectSame(cached(cache, snapshots), fresh(snapshots), "counter stepped")

        // Log today on the weekly habit.
        snapshots[1].completions.append(Completion(habitID: snapshots[1].habit.id, date: day(0), value: 1))
        expectSame(cached(cache, snapshots), fresh(snapshots), "weekly logged")

        // Clear the earliest day of the every-other-day habit: its start moves.
        snapshots[2].completions.removeFirst()
        expectSame(cached(cache, snapshots), fresh(snapshots), "earliest cleared")

        // A note only: nothing drawn changes, the cache may reuse.
        snapshots[0].completions[0].note = "Good book"
        expectSame(cached(cache, snapshots), fresh(snapshots), "note added")

        // Rename, recolour and change the schedule.
        snapshots[0].habit.name = "Read more"
        snapshots[0].habit.color = .purple
        expectSame(cached(cache, snapshots), fresh(snapshots), "renamed")
        snapshots[1].habit.frequency = .daily
        expectSame(cached(cache, snapshots), fresh(snapshots), "schedule changed")
        snapshots[3].habit.type = .counter(target: 4)
        expectSame(cached(cache, snapshots), fresh(snapshots), "target changed")

        // Reorder, delete, add.
        snapshots[4].habit.sortOrder = -1
        expectSame(cached(cache, snapshots), fresh(snapshots), "reordered")
        snapshots.remove(at: 2)
        expectSame(cached(cache, snapshots), fresh(snapshots), "deleted")
        let added = Habit(name: "Walk", frequency: .specificDays([.monday, .friday]), type: .binary, createdAt: day(-14), sortOrder: 9)
        snapshots.append((added, [Completion(habitID: added.id, date: day(-7), value: 1)]))
        expectSame(cached(cache, snapshots), fresh(snapshots), "added")
    }

    @Test("A new day or a new calendar is computed afresh")
    func contextChanges() {
        let cache = OverviewGridRows()
        let snapshots = fixture()
        _ = cached(cache, snapshots)

        let tomorrow = calendar.date(byAdding: .day, value: 1, to: now)!
        expectSame(cached(cache, snapshots, now: tomorrow), fresh(snapshots, now: tomorrow), "next day")

        let mondayFirst = TestCalendar.utc(firstWeekday: 2)
        expectSame(
            cached(cache, snapshots, now: tomorrow, calendar: mondayFirst),
            fresh(snapshots, now: tomorrow, calendar: mondayFirst),
            "week starts on Monday"
        )
    }

    /// The cache reuses a row only when `sameValues` finds every field
    /// unchanged. A field added to `Habit` or `Completion` but not
    /// compared there would let an edit to it serve a stale row: this
    /// fails first, so whoever adds one also adds it to the comparison.
    @Test("The comparison covers every stored field of Habit and Completion")
    func comparedFieldsAreComplete() {
        let habit = Habit(name: "Read", frequency: .daily, type: .binary, createdAt: now)
        let completion = Completion(habitID: habit.id, date: now)
        #expect(Mirror(reflecting: habit).children.compactMap(\.label) == [
            "id", "name", "frequency", "type", "createdAt", "archivedAt", "color", "icon",
            "remindersEnabled", "reminderHour", "reminderMinute", "sortOrder", "goalID", "category",
        ])
        #expect(Mirror(reflecting: completion).children.compactMap(\.label) == [
            "id", "habitID", "date", "value", "note",
        ])
    }

    @Test("Only a habit whose values changed is scored again")
    func scoresOnlyWhatChanged() {
        let cache = OverviewGridRows()
        let counting = CountingScoreCalculator(calendar: calendar)
        var snapshots = fixture()

        _ = cached(cache, snapshots, scoreCalculator: counting)
        #expect(counting.calls == snapshots.count)

        _ = cached(cache, snapshots, scoreCalculator: counting)
        #expect(counting.calls == snapshots.count, "an unchanged render scores nothing")

        snapshots[0].completions[0].value = 0.5
        let output = cached(cache, snapshots, scoreCalculator: counting)
        #expect(counting.calls == snapshots.count + 1, "one edit scores one habit")
        expectSame(output, fresh(snapshots), "after the edit")

        let tomorrow = calendar.date(byAdding: .day, value: 1, to: now)!
        _ = cached(cache, snapshots, now: tomorrow, scoreCalculator: counting)
        #expect(counting.calls == 2 * snapshots.count + 1, "a new day scores every habit")
    }
}

/// Counts `currentScore` calls. Driven sequentially by one test, so
/// the counter needs no lock.
private final class CountingScoreCalculator: HabitScoreCalculating, @unchecked Sendable {
    private let base: DefaultHabitScoreCalculator
    private(set) var calls = 0

    init(calendar: Calendar) {
        base = DefaultHabitScoreCalculator(calendar: calendar)
    }

    func currentScore(for habit: Habit, completions: [Completion], asOf date: Date) -> Double {
        calls += 1
        return base.currentScore(for: habit, completions: completions, asOf: date)
    }

    func scoreHistory(for habit: Habit, completions: [Completion], from startDate: Date, to endDate: Date) -> [DailyScore] {
        base.scoreHistory(for: habit, completions: completions, from: startDate, to: endDate)
    }
}
