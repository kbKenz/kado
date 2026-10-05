import Foundation
import Testing
@testable import Kado

/// `TaskDaySections.mayInclude` lets Today skip building items for
/// tasks that cannot show. It must never drop one that would: the
/// sections built from the filtered list equal the ones built from all
/// tasks, for every kind of day, including tasks done early that a
/// future day still lists.
@Suite("TaskDaySections prefilter")
struct TaskDaySectionsPrefilterTests {
    private let cal = TestCalendar.utc

    @Test("Sections from the prefiltered tasks equal sections from all tasks")
    func prefilterKeepsEverySection() {
        var rng = SeededGenerator(seed: 0x7A5C)
        let today = cal.startOfDay(for: TestCalendar.referenceDate)
        let day = { (offset: Int) in self.cal.date(byAdding: .day, value: offset, to: today)! }
        let at = { (offset: Int, minutes: Int) in self.cal.date(byAdding: .minute, value: minutes, to: day(offset))! }

        for _ in 0..<30 {
            let items = (0..<60).map { n -> TaskListItem in
                let maybe = { (rng: inout SeededGenerator) in Int.random(in: 0..<3, using: &rng) > 0 }
                let dueDate = maybe(&rng) ? at(Int.random(in: -8...8, using: &rng), Int.random(in: 0..<1440, using: &rng)) : nil
                let completedAt = maybe(&rng) ? at(Int.random(in: -8...8, using: &rng), Int.random(in: 0..<1440, using: &rng)) : nil
                let schedules = (0..<Int.random(in: 0...2, using: &rng)).map { _ -> TaskScheduleItem in
                    let planned = day(Int.random(in: -8...8, using: &rng))
                    // Some blocks span midnight, so they belong to two days.
                    let start = Bool.random(using: &rng) ? at(Int.random(in: -8...8, using: &rng), Int.random(in: 0..<1440, using: &rng)) : nil
                    let end = start.flatMap { s in Bool.random(using: &rng) ? s.addingTimeInterval(Double(Int.random(in: 30...2000, using: &rng)) * 60) : nil }
                    return TaskScheduleItem(plannedDay: planned, startAt: start, endAt: end)
                }
                return TaskListItem(title: "T\(n)", dueDate: dueDate, completedAt: completedAt, schedules: schedules)
            }

            for offset in -6...6 {
                let shown = day(offset)
                let kind = TodayDayKind(day: shown, today: today, calendar: cal)
                let all = TaskDaySections.make(for: shown, kind: kind, items: items, calendar: cal)
                let kept = items.filter { item in
                    TaskDaySections.mayInclude(
                        completedAt: item.completedAt, dueDate: item.dueDate,
                        hasSchedules: { !item.schedules.isEmpty },
                        on: shown, kind: kind, calendar: cal
                    )
                }
                let filtered = TaskDaySections.make(for: shown, kind: kind, items: kept, calendar: cal)
                #expect(ids(filtered.due) == ids(all.due), "due, day \(offset)")
                #expect(ids(filtered.inbox) == ids(all.inbox), "inbox, day \(offset)")
                #expect(ids(filtered.completed) == ids(all.completed), "completed, day \(offset)")
            }
        }
    }

    @Test("A task done early stays on its future day, and leaves the others")
    func doneEarly() {
        let today = cal.startOfDay(for: TestCalendar.referenceDate)
        let tomorrow = TestCalendar.day(1)
        let check = { (day: Date, kind: TodayDayKind, due: Date?, scheduled: Bool) in
            TaskDaySections.mayInclude(
                completedAt: TestCalendar.referenceDate, dueDate: due, hasSchedules: { scheduled },
                on: day, kind: kind, calendar: self.cal
            )
        }
        #expect(check(tomorrow, .future, tomorrow, false))
        #expect(check(tomorrow, .future, nil, true))
        #expect(!check(tomorrow, .future, nil, false))
        #expect(check(today, .today, nil, false))
        #expect(!check(TestCalendar.day(-1), .past, TestCalendar.day(-1), true))
    }

    private func ids(_ items: [TaskListItem]) -> [String] { items.map(\.title) }
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
