import Foundation
import Testing
import KadoCore
@testable import Kado

/// `MonthlyCalendarDayIndex` replaced per-cell scans of every
/// completion. These tests hold it to the exact answers those scans
/// gave, over random histories and across zones whose days start at
/// odd times.
@Suite("MonthlyCalendarDayIndex")
struct MonthlyCalendarDayIndexTests {
    /// Deterministic, so a failure reproduces.
    private struct SplitMix: RandomNumberGenerator {
        var state: UInt64
        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
    }

    private static let zones: [Calendar] = [
        TestCalendar.utc,
        TestCalendar.paris,
        TestCalendar.havana,
        zone("Australia/Lord_Howe"),
        zone("Pacific/Chatham"),
    ]

    private static func zone(_ identifier: String) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: identifier)!
        return calendar
    }

    /// Built the way the view builds its grid: offsets from the
    /// month's start, so on Havana's 2026-03-08 the day is 01:00.
    private func daysInMonth(containing date: Date, calendar: Calendar) -> [Date] {
        let monthStart = calendar.dateInterval(of: .month, for: date)!.start
        let range = calendar.range(of: .day, in: .month, for: monthStart)!
        return range.compactMap { calendar.date(byAdding: .day, value: $0 - 1, to: monthStart) }
    }

    private func randomCompletions(
        habitID: UUID,
        around anchor: Date,
        calendar: Calendar,
        using rng: inout SplitMix
    ) -> [Completion] {
        let otherHabit = UUID()
        return (0..<Int.random(in: 0...60, using: &rng)).map { _ in
            let dayOffset = Int.random(in: -45...45, using: &rng)
            let minutes = Int.random(in: 0..<(24 * 60), using: &rng)
            let day = calendar.date(byAdding: .day, value: dayOffset, to: calendar.startOfDay(for: anchor))!
            let date = calendar.date(byAdding: .minute, value: minutes, to: day)!
            let notes: [String?] = [nil, "", "felt good"]
            return Completion(
                habitID: Int.random(in: 0..<8, using: &rng) == 0 ? otherHabit : habitID,
                date: date,
                value: [0, 0.5, 1, 3].randomElement(using: &rng)!,
                note: notes.randomElement(using: &rng)!
            )
        }
    }

    @Test("Matches the per-cell scans it replaced, across zones and random histories")
    func matchesPerCellScans() {
        var rng = SplitMix(state: 42)
        let types: [HabitType] = [.binary, .negative, .counter(target: 3)]
        for calendar in Self.zones {
            let months = [
                TestCalendar.instant(calendar, 2026, 3, 15, 12),
                TestCalendar.instant(calendar, 2026, 4, 15, 12),
                TestCalendar.instant(calendar, 2026, 10, 15, 12),
            ]
            for month in months {
                for _ in 0..<12 {
                    let createdAt = calendar.date(
                        byAdding: .minute,
                        value: Int.random(in: -60 * 24 * 40...60 * 24 * 40, using: &rng),
                        to: month
                    )!
                    let habit = Habit(
                        name: "H",
                        frequency: .daily,
                        type: types.randomElement(using: &rng)!,
                        createdAt: createdAt
                    )
                    let completions = randomCompletions(
                        habitID: habit.id, around: month, calendar: calendar, using: &rng
                    )
                    let index = MonthlyCalendarDayIndex(habit: habit, completions: completions, calendar: calendar)
                    for day in daysInMonth(containing: month, calendar: calendar) {
                        let beforeStart = habit.isBeforeStart(day, completions: completions, calendar: calendar)
                        let completed = completions.contains { c in
                            c.habitID == habit.id && c.value > 0 && calendar.isDate(c.date, inSameDayAs: day)
                        }
                        let noted = completions.contains { c in
                            c.habitID == habit.id
                                && calendar.isDate(c.date, inSameDayAs: day)
                                && c.note.map { !$0.isEmpty } ?? false
                        }
                        #expect(index.isBeforeStart(day) == beforeStart, "\(calendar.timeZone.identifier) \(day)")
                        #expect(index.hasValue(on: day) == completed, "\(calendar.timeZone.identifier) \(day)")
                        #expect(index.hasNote(on: day) == noted, "\(calendar.timeZone.identifier) \(day)")
                    }
                }
            }
        }
    }

    @Test("A zero-value record with a note shows the dot but does not count as done")
    func zeroValueNote() {
        let calendar = TestCalendar.havana
        let day = TestCalendar.instant(calendar, 2026, 3, 8, 1)
        let habit = Habit(name: "H", frequency: .daily, type: .binary, createdAt: day)
        let completions = [Completion(habitID: habit.id, date: day, value: 0, note: "rest")]
        let index = MonthlyCalendarDayIndex(habit: habit, completions: completions, calendar: calendar)
        #expect(index.hasNote(on: day))
        #expect(!index.hasValue(on: day))
    }
}
