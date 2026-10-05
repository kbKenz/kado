import Foundation
import Testing
@testable import KadoCore

@Suite("Insights habits")
struct InsightsHabitsTests {
    typealias T = InsightsTestSupport

    private func rows(_ input: InsightsInput, _ context: InsightsContext = T.context()) -> [InsightsHabitRow] {
        InsightsCalculator.habits(T.scope(input, context))
    }

    /// A habit whose records carry their own values: (day offset, value).
    private func habit(_ name: String, type: HabitType, records: [(Int, Double)]) -> InsightsHabit {
        var habit = T.habit(name, type: type)
        habit.completions = records.map { offset, value in
            Completion(habitID: habit.id, date: T.time(offset, 9), value: value)
        }
        return habit
    }

    /// The row of the habit named `name`.
    private func row(_ rows: [InsightsHabitRow], _ name: String) throws -> InsightsHabitRow {
        try #require(rows.first { $0.name == name })
    }

    @Test("No habits, no rows")
    func empty() {
        #expect(rows(.empty).isEmpty)
    }

    @Test("A binary habit: consistency, times done, no amount")
    func binary() throws {
        let read = T.habit("Read", category: .study, doneOffsets: [-20, -6, -5, -3, -1, 0], color: .red, icon: "book.fill")
        let row = try #require(rows(InsightsInput(habits: [read])).first)
        #expect(row.habitID == read.id)
        #expect(row.name == "Read")
        #expect(row.icon == "book.fill")
        #expect(row.color == .red)
        #expect(row.category == .study)
        #expect(row.type == .binary)
        // -6...0: done on -6, -5, -3, -1 and today; missed on -4 and -2.
        #expect(row.rate == InsightsRate(done: 5, total: 7))
        #expect(row.timesDone == 5)
        #expect(row.amount == 0.0)
        #expect(row.allTimeTimesDone == 6)
        #expect(row.allTimeAmount == 0.0)
    }

    @Test("A counter adds up its units, a timer its seconds")
    func amounts() throws {
        let water = habit("Water", type: .counter(target: 8), records: [
            (-10, 8), (-7, 2), (-3, 0), (-2, 8), (-1, 3), (-1, 5),
        ])
        let plank = habit("Plank", type: .timer(targetSeconds: 600), records: [(-5, 300), (-4, 600), (0, 900)])
        let result = rows(InsightsInput(habits: [water, plank]))

        let waterRow = try row(result, "Water")
        // Full target on -2 and -1 (3 + 5); the zero record on -3 is a note.
        #expect(waterRow.rate == InsightsRate(done: 2, total: 6))
        #expect(waterRow.timesDone == 2)
        #expect(waterRow.amount == 16.0)
        // Day -7 is outside the week but counts all time.
        #expect(waterRow.allTimeTimesDone == 4)
        #expect(waterRow.allTimeAmount == 26.0)

        let plankRow = try row(result, "Plank")
        // Half the target on -5, full on -4 and today.
        #expect(plankRow.rate == InsightsRate(done: 2, total: 6))
        #expect(plankRow.timesDone == 3)
        #expect(plankRow.amount == 1800.0)
        #expect(plankRow.allTimeTimesDone == 3)
        #expect(plankRow.allTimeAmount == 1800.0)
    }

    @Test("A negative habit counts slips as times done, with no amount")
    func negative() throws {
        let smoke = habit("Smoke", type: .negative, records: [(-9, 1), (-4, 1), (-2, 1)])
        let row = try #require(rows(InsightsInput(habits: [smoke])).first)
        // -6...-1 are due; slips on -4 and -2. Today never counts.
        #expect(row.rate == InsightsRate(done: 4, total: 6))
        #expect(row.timesDone == 2)
        #expect(row.amount == 0.0)
        #expect(row.allTimeTimesDone == 3)
        #expect(row.allTimeAmount == 0.0)
    }

    @Test("Today joins the rate only once it is done")
    func todayGrace() throws {
        let notYet = T.habit("Not yet", doneOffsets: [-1])
        let row = try #require(rows(InsightsInput(habits: [notYet])).first)
        #expect(row.rate == InsightsRate(done: 1, total: 1))
        #expect(row.timesDone == 1)
    }

    @Test("Streaks and score come from the shared calculators, as of today")
    func streaksAndScore() throws {
        let habit = T.habit(doneOffsets: [-9, -8, -7, -5, -4, -3, -2, -1])
        let row = try #require(rows(InsightsInput(habits: [habit])).first)
        let streaks = DefaultStreakCalculator(calendar: T.calendar)
        let scores = DefaultHabitScoreCalculator(calendar: T.calendar)
        #expect(row.currentStreak == streaks.current(for: habit.habit, completions: habit.completions, asOf: T.day(0)))
        #expect(row.bestStreak == streaks.best(for: habit.habit, completions: habit.completions, asOf: T.day(0)))
        #expect(row.score == scores.currentScore(for: habit.habit, completions: habit.completions, asOf: T.day(0)))
        // Five days in a row up to yesterday (today is a grace day).
        #expect(row.currentStreak == 5)
        #expect(row.bestStreak == 5)
    }

    @Test("Rows sort by consistency, then times done, then the user's order, then name")
    func sorting() {
        func habit(_ name: String, sortOrder: Int = 0, doneOffsets: [Int] = [-6, -4, -2], createdDaysAgo: Int = 60) -> InsightsHabit {
            var habit = T.habit(name, createdDaysAgo: createdDaysAgo, doneOffsets: doneOffsets)
            habit.habit.sortOrder = sortOrder
            return habit
        }
        let input = InsightsInput(habits: [
            // Created today, nothing due yet: no rate, so last.
            habit("Fresh", doneOffsets: [], createdDaysAgo: 0),
            habit("Bravo", sortOrder: 3),
            // 1 of 2: the same share as the 3 of 6 below, fewer times done.
            habit("Half one", doneOffsets: [-2]),
            habit("Second", sortOrder: 2),
            habit("Alpha", sortOrder: 3),
            habit("Best", doneOffsets: [-6, -5, -4, -3, -2, -1]),
            habit("First", sortOrder: 1),
            habit("Half three"),
        ])
        #expect(rows(input).map(\.name) == ["Best", "Half three", "First", "Second", "Alpha", "Bravo", "Half one", "Fresh"])
    }

    @Test("Archived habits get no row")
    func archived() {
        let archived = T.habit("Old", archivedOffset: -3, doneOffsets: [-5])
        let active = T.habit("New", doneOffsets: [-5])
        #expect(rows(InsightsInput(habits: [archived, active])).map(\.name) == ["New"])
    }

    @Test("A month across a midnight DST change counts every day once")
    func havanaMonth() throws {
        let calendar = TestCalendar.havana
        // Today is 2026-03-12; the month runs 02-11...03-12 and holds 03-08.
        let context = T.context(period: .month, today: T.day(-32, calendar: calendar), calendar: calendar)
        let water = T.habit(
            "Water",
            type: .counter(target: 2),
            createdDaysAgo: 61,
            doneOffsets: Array(-61 ... -32),
            value: 2,
            calendar: calendar
        )
        let row = try #require(rows(InsightsInput(habits: [water]), context).first)
        #expect(row.rate == InsightsRate(done: 30, total: 30))
        #expect(row.timesDone == 30)
        #expect(row.amount == 60.0)
        #expect(row.allTimeTimesDone == 30)
        #expect(row.allTimeAmount == 60.0)
    }
}
