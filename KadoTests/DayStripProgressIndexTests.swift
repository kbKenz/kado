import Foundation
import Testing
import KadoCore

/// The indexed strip progress must give exactly the answer of the plain
/// one, which reads every completion per day: same listing rule, same
/// `isDueOrLogged`, same first-match `HabitRowState`. Walked over random
/// histories in three zones, every frequency and type, duplicate and
/// zero-value records, and past, present and future days.
@Suite("DayStripProgress.Index")
struct DayStripProgressIndexTests {
    @Test("Indexed progress equals the plain progress", arguments: [
        TestCalendar.utc, TestCalendar.paris, TestCalendar.havana,
    ])
    func matchesPlainProgress(calendar: Calendar) {
        var rng = SeededGenerator(seed: 0x5EED)
        let evaluator = DefaultFrequencyEvaluator(calendar: calendar)
        let reference = calendar.startOfDay(for: TestCalendar.referenceDate)
        let day = { (offset: Int) in calendar.date(byAdding: .day, value: offset, to: reference)! }

        for _ in 0..<40 {
            let habits = (0..<6).map { _ in Self.randomHabit(createdAt: day(-Int.random(in: 0...40, using: &rng)), using: &rng) }
            var completions: [UUID: [Completion]] = [:]
            for habit in habits {
                completions[habit.id] = (0..<Int.random(in: 0...30, using: &rng)).map { _ in
                    // A stray record with another habit's id must be
                    // ignored the same way by both paths.
                    let habitID = Int.random(in: 0..<20, using: &rng) == 0 ? UUID() : habit.id
                    let date = calendar.date(
                        byAdding: .minute,
                        value: Int.random(in: 0..<(24 * 60), using: &rng),
                        to: day(-Int.random(in: -3...45, using: &rng))
                    )!
                    let value: Double = [0, 0.5, 1, 1, 2, 5, 600][Int.random(in: 0..<7, using: &rng)]
                    return Completion(habitID: habitID, date: date, value: value)
                }
            }
            let index = DayStripProgress.Index(habits: habits, completions: completions, calendar: calendar)

            for offset in -50...10 {
                let date = day(offset)
                let isFuture = offset > 0
                let plain = DayStripProgress.progress(
                    on: date, isFuture: isFuture, habits: habits, completions: completions,
                    evaluator: evaluator, calendar: calendar
                )
                let indexed = DayStripProgress.progress(
                    on: date, isFuture: isFuture, index: index, evaluator: evaluator, calendar: calendar
                )
                #expect(indexed == plain, "day \(offset) in \(calendar.timeZone.identifier)")
            }
        }
    }

    @Test("The first positive record of the day decides, as in the list")
    func firstMatchWins() {
        let calendar = TestCalendar.utc
        let habit = Habit(name: "Water", frequency: .daily, type: .counter(target: 3), createdAt: TestCalendar.day(-5))
        let day = TestCalendar.day(-1)
        // Two records on one day: the first one (2, short of 3) is the
        // one the Today row reads, so the ring must not count the day.
        let completions = [habit.id: [
            Completion(habitID: habit.id, date: day, value: 2),
            Completion(habitID: habit.id, date: day.addingTimeInterval(60), value: 3),
        ]]
        let index = DayStripProgress.Index(habits: [habit], completions: completions, calendar: calendar)
        let progress = DayStripProgress.progress(
            on: day, isFuture: false, index: index,
            evaluator: DefaultFrequencyEvaluator(calendar: calendar), calendar: calendar
        )
        #expect(progress == DayProgress(completed: 0, total: 1))
    }

    private static func randomHabit(createdAt: Date, using rng: inout SeededGenerator) -> Habit {
        let frequencies: [Frequency] = [
            .daily, .daysPerWeek(3), .daysPerWeek(0), .specificDays([.monday, .thursday]),
            .everyNDays(2), .everyNDays(3), .everyNDays(0),
        ]
        let types: [HabitType] = [.binary, .counter(target: 2), .timer(targetSeconds: 600), .negative]
        return Habit(
            name: "H",
            frequency: frequencies[Int.random(in: 0..<frequencies.count, using: &rng)],
            type: types[Int.random(in: 0..<types.count, using: &rng)],
            createdAt: createdAt
        )
    }
}

/// SplitMix64: a deterministic generator, so a failing fixture can be
/// replayed.
nonisolated private struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
