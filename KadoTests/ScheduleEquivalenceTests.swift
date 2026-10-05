import Foundation
import Testing
@testable import KadoCore

/// The prepared schedule (`DefaultFrequencyEvaluator.Prepared`) must
/// answer exactly what the per-call evaluator answers, and the score
/// and Insights fast paths built on it must produce the same numbers,
/// bit for bit. A second copy of a schedule rule drifting from the
/// first is what issue #57 was, so this checks the two against each
/// other over random histories rather than a few hand-picked days.
///
/// Every frequency (including `.everyNDays(0)` and `.daysPerWeek(0)`)
/// meets every habit type, in zones whose day does not always start at
/// 00:00: Havana moves its clock at midnight, Paris and Auckland at
/// 02:00/03:00. The histories cross those transitions, carry several
/// records on one day, zero-value note records, records of another
/// habit, out-of-order dates and archived habits.
@Suite("Prepared schedule equivalence")
struct ScheduleEquivalenceTests {

    static let zones = ["UTC", "America/Havana", "Europe/Paris", "Pacific/Auckland"]

    static let frequencies: [Frequency] = [
        .daily,
        .specificDays([]),
        .specificDays([.monday, .thursday]),
        .specificDays(Set(Weekday.allCases)),
        .everyNDays(0),
        .everyNDays(1),
        .everyNDays(2),
        .everyNDays(5),
        .daysPerWeek(0),
        .daysPerWeek(1),
        .daysPerWeek(3),
        .daysPerWeek(7),
    ]

    static let types: [HabitType] = [
        .binary, .counter(target: 3), .timer(targetSeconds: 600), .negative,
    ]

    @Test("isDue, isOutstanding and isCounted match the per-call evaluator", arguments: zones)
    func preparedMatchesEvaluator(zone: String) {
        let calendar = Self.calendar(zone)
        // The `calendar` `isCounted` is handed may differ from the
        // evaluator's; the prepared path has to honour both.
        let otherCalendar = Self.calendar(zone == "UTC" ? "America/Havana" : "UTC")
        let evaluator = DefaultFrequencyEvaluator(calendar: calendar)
        var rng = SeededGenerator(seed: Self.seed(zone))

        for frequency in Self.frequencies {
            for type in Self.types {
                let sample = Self.sample(frequency: frequency, type: type, calendar: calendar, rng: &rng)
                let habit = sample.habit
                let completions = sample.completions
                let prepared = evaluator.prepared(for: habit, completions: completions)
                let crossPrepared = evaluator.prepared(
                    for: habit, completions: completions, loggedDayCalendar: otherCalendar
                )
                for day in Self.days(of: sample, calendar: calendar) {
                    let label = "\(zone) \(frequency) \(type) \(day)"
                    #expect(
                        prepared.isDue(on: day)
                            == evaluator.isDue(habit: habit, on: day, completions: completions),
                        "isDue \(label)"
                    )
                    #expect(
                        prepared.isOutstanding(on: day)
                            == evaluator.isOutstanding(habit: habit, on: day, completions: completions),
                        "isOutstanding \(label)"
                    )
                    #expect(
                        prepared.isCounted(on: day)
                            == evaluator.isCounted(habit: habit, on: day, completions: completions, calendar: calendar),
                        "isCounted \(label)"
                    )
                    #expect(
                        crossPrepared.isCounted(on: day)
                            == evaluator.isCounted(
                                habit: habit, on: day, completions: completions, calendar: otherCalendar
                            ),
                        "isCounted, other calendar, \(label)"
                    )
                    // Callers also pass instants inside the day.
                    let instant = day.addingTimeInterval(Double.random(in: 0..<86_400, using: &rng))
                    #expect(
                        prepared.isCounted(on: instant)
                            == evaluator.isCounted(
                                habit: habit, on: instant, completions: completions, calendar: calendar
                            ),
                        "isCounted \(zone) \(frequency) \(type) \(instant)"
                    )
                }
            }
        }
    }

    @Test("Score history and current score are bit-for-bit identical", arguments: zones)
    func scoreMatchesGenericPath(zone: String) {
        let calendar = Self.calendar(zone)
        let otherCalendar = Self.calendar(zone == "UTC" ? "America/Havana" : "UTC")
        var rng = SeededGenerator(seed: Self.seed(zone) &+ 1)

        // Same calendar for both (the production setup), then an
        // evaluator on another calendar than the score's.
        let pairs: [(score: Calendar, evaluator: Calendar)] = [
            (calendar, calendar), (calendar, otherCalendar),
        ]
        for frequency in Self.frequencies {
            for type in Self.types {
                for pair in pairs {
                    let sample = Self.sample(frequency: frequency, type: type, calendar: calendar, rng: &rng)
                    let fast = DefaultHabitScoreCalculator(
                        calendar: pair.score,
                        frequencyEvaluator: DefaultFrequencyEvaluator(calendar: pair.evaluator)
                    )
                    let generic = DefaultHabitScoreCalculator(
                        calendar: pair.score,
                        frequencyEvaluator: PassThroughEvaluator(
                            base: DefaultFrequencyEvaluator(calendar: pair.evaluator)
                        )
                    )
                    let label = "\(zone) \(frequency) \(type) evaluator \(pair.evaluator.timeZone.identifier)"
                    let start = sample.spanStart.addingTimeInterval(-3 * 86_400)
                    #expect(
                        fast.scoreHistory(
                            for: sample.habit, completions: sample.completions, from: start, to: sample.spanEnd
                        ) == generic.scoreHistory(
                            for: sample.habit, completions: sample.completions, from: start, to: sample.spanEnd
                        ),
                        "scoreHistory \(label)"
                    )
                    #expect(
                        fast.currentScore(for: sample.habit, completions: sample.completions, asOf: sample.middle)
                            == generic.currentScore(
                                for: sample.habit, completions: sample.completions, asOf: sample.middle
                            ),
                        "currentScore \(label)"
                    )
                }
            }
        }
    }

    @Test("Insights day outcomes match the generic path", arguments: zones)
    func insightsOutcomesMatchGenericPath(zone: String) {
        let calendar = Self.calendar(zone)
        var rng = SeededGenerator(seed: Self.seed(zone) &+ 2)
        var habits: [InsightsHabit] = []
        for frequency in Self.frequencies {
            for type in Self.types {
                let sample = Self.sample(frequency: frequency, type: type, calendar: calendar, rng: &rng)
                // The scope is handed one habit's records, as the input
                // builder does.
                let own = sample.completions.filter { $0.habitID == sample.habit.id }
                habits.append(InsightsHabit(habit: sample.habit, category: .other, completions: own))
            }
        }
        let input = InsightsInput(habits: habits)
        let today = Self.span(calendar).middle
        func scope(_ evaluator: any FrequencyEvaluating) -> InsightsScope {
            InsightsScope(
                input: input,
                context: InsightsContext(
                    period: .month,
                    now: today,
                    today: today,
                    calendar: calendar,
                    dayBoundary: DayBoundary(calendar: calendar, startHour: 0),
                    frequencyEvaluator: evaluator,
                    streakCalculator: DefaultStreakCalculator(calendar: calendar),
                    scoreCalculator: DefaultHabitScoreCalculator(calendar: calendar)
                )
            )
        }
        let fast = scope(DefaultFrequencyEvaluator(calendar: calendar))
        let generic = scope(PassThroughEvaluator(base: DefaultFrequencyEvaluator(calendar: calendar)))

        // The precomputed window, plus days on both sides of it that
        // `outcome` answers on demand.
        let days = InsightsScope.days(endingAt: InsightsScope.step(today, by: 10, calendar: calendar), count: 120, calendar: calendar)
        for habit in habits {
            for day in days {
                #expect(
                    fast.outcome(of: habit, on: day) == generic.outcome(of: habit, on: day),
                    "\(zone) \(habit.habit.frequency) \(habit.habit.type) \(day)"
                )
            }
        }
    }

    // MARK: - Random histories

    struct Sample {
        let habit: Habit
        let completions: [Completion]
        let spanStart: Date
        let spanEnd: Date
        let middle: Date
    }

    /// 2026-02-20 to 2026-11-10: crosses Havana's midnight transitions
    /// (03-08, 11-01), Paris's (03-29, 10-25) and Auckland's (04-05,
    /// 09-27).
    static func span(_ calendar: Calendar) -> (start: Date, end: Date, middle: Date) {
        let start = TestCalendar.instant(calendar, 2026, 2, 20)
        let end = TestCalendar.instant(calendar, 2026, 11, 10, 12)
        let middle = TestCalendar.instant(calendar, 2026, 6, 15, 9)
        return (start, end, middle)
    }

    static func sample(
        frequency: Frequency,
        type: HabitType,
        calendar: Calendar,
        rng: inout SeededGenerator
    ) -> Sample {
        let span = span(calendar)
        let length = span.end.timeIntervalSince(span.start)
        func instant() -> Date {
            span.start.addingTimeInterval(Double.random(in: 0..<length, using: &rng))
        }
        let createdAt = span.start.addingTimeInterval(Double.random(in: 0..<(length / 3), using: &rng))
        let archivedAt: Date? = Bool.random(using: &rng) ? instant() : nil
        let habit = Habit(
            name: "Sample",
            frequency: frequency,
            type: type,
            createdAt: createdAt,
            archivedAt: archivedAt
        )
        let otherHabit = UUID()
        var completions: [Completion] = []
        let count = Int.random(in: 0...40, using: &rng)
        for _ in 0..<count {
            let date = instant()
            let value: Double = [0, 0, 1, 1, 1, 2, 3, 0.5, 600, 250].randomElement(using: &rng)!
            let note: String? = value == 0 ? "note" : nil
            completions.append(Completion(habitID: habit.id, date: date, value: value, note: note))
            // A second record on the same day now and then.
            if Int.random(in: 0..<5, using: &rng) == 0 {
                completions.append(Completion(habitID: habit.id, date: date.addingTimeInterval(60), value: 1))
            }
        }
        // A burst of daily records, so the rolling week and the
        // re-anchoring cycle see dense stretches as well as gaps.
        let burstStart = instant()
        for offset in 0..<Int.random(in: 0...20, using: &rng) {
            let date = calendar.date(byAdding: .day, value: offset, to: burstStart)!
            completions.append(Completion(habitID: habit.id, date: date, value: 1))
        }
        // Another habit's records must change nothing.
        for _ in 0..<5 {
            completions.append(Completion(habitID: otherHabit, date: instant(), value: 1))
        }
        completions.shuffle(using: &rng)
        return Sample(
            habit: habit,
            completions: completions,
            spanStart: span.start,
            spanEnd: span.end,
            middle: span.middle
        )
    }

    /// Every calendar day from a few days before the span to its end,
    /// re-anchored to the day's first instant at each step.
    static func days(of sample: Sample, calendar: Calendar) -> [Date] {
        var result: [Date] = []
        var day = calendar.startOfDay(for: calendar.date(byAdding: .day, value: -3, to: sample.spanStart)!)
        let last = calendar.startOfDay(for: sample.spanEnd)
        while day <= last {
            result.append(day)
            day = calendar.startOfDay(for: calendar.date(byAdding: .day, value: 1, to: day)!)
        }
        return result
    }

    static func calendar(_ zone: String) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: zone)!
        calendar.firstWeekday = 2
        return calendar
    }

    static func seed(_ zone: String) -> UInt64 {
        zone.utf8.reduce(UInt64(1469598103934665603)) { ($0 ^ UInt64($1)) &* 1099511628211 }
    }
}

/// Forwards to `DefaultFrequencyEvaluator` without being one, so the
/// score calculator and the Insights scope take their generic,
/// per-call path. That path is the reference.
private struct PassThroughEvaluator: FrequencyEvaluating {
    let base: DefaultFrequencyEvaluator

    func isDue(habit: Habit, on date: Date, completions: [Completion]) -> Bool {
        base.isDue(habit: habit, on: date, completions: completions)
    }

    func isOutstanding(habit: Habit, on date: Date, completions: [Completion]) -> Bool {
        base.isOutstanding(habit: habit, on: date, completions: completions)
    }
}

/// SplitMix64: a fixed seed per zone keeps a failure reproducible.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
