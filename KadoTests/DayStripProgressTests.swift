import Foundation
import Testing
import KadoCore

@Suite("DayStripProgress")
struct DayStripProgressTests {
    private let cal = TestCalendar.utc
    private let evaluator = DefaultFrequencyEvaluator()

    private func habit(_ name: String, type: HabitType = .binary, createdDaysAgo: Int = 10) -> Habit {
        Habit(name: name, frequency: .daily, type: type, createdAt: TestCalendar.day(-createdDaysAgo))
    }

    @Test("Listed from the earlier of creation and first completion")
    func listing() {
        let h = habit("Read", createdDaysAgo: 3)
        #expect(!h.isListed(on: TestCalendar.day(-4), completions: [], calendar: cal))
        #expect(h.isListed(on: TestCalendar.day(-3), completions: [], calendar: cal))
        let backfilled = [Completion(habitID: h.id, date: TestCalendar.day(-6))]
        #expect(h.isListed(on: TestCalendar.day(-6), completions: backfilled, calendar: cal))
    }

    @Test("Counts due and done habits on a past day")
    func pastDay() {
        let a = habit("A"), b = habit("B")
        let day = TestCalendar.day(-1)
        let comps = [a.id: [Completion(habitID: a.id, date: day)]]
        let p = DayStripProgress.progress(on: day, isFuture: false, habits: [a, b],
                                          completions: comps, evaluator: evaluator, calendar: cal)
        #expect(p == DayProgress(completed: 1, total: 2))
    }

    @Test("Future days count due habits but none done")
    func futureDay() {
        let negative = habit("No sugar", type: .negative)
        let p = DayStripProgress.progress(on: TestCalendar.day(2), isFuture: true, habits: [habit("A"), negative],
                                          completions: [:], evaluator: evaluator, calendar: cal)
        #expect(p == DayProgress(completed: 0, total: 2))
    }

    @Test("A day before every habit's first day is empty")
    func beforeStart() {
        let p = DayStripProgress.progress(on: TestCalendar.day(-20), isFuture: false, habits: [habit("A")],
                                          completions: [:], evaluator: evaluator, calendar: cal)
        #expect(p == .empty)
    }
}
