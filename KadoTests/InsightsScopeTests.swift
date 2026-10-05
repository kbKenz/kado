import Foundation
import Testing
@testable import KadoCore

@Suite("Insights scope")
struct InsightsScopeTests {
    typealias T = InsightsTestSupport

    @Test("A week is the 7 days ending today, the previous week the 7 before")
    func weekDays() {
        let scope = T.scope(.empty, T.context(period: .week))
        #expect(scope.days == (-6...0).map { T.day($0) })
        #expect(scope.previousDays == (-13 ... -7).map { T.day($0) })
    }

    @Test("Every day key is the calendar's own start of day, across a midnight DST change")
    func havanaDaysAreDayStarts() {
        let calendar = TestCalendar.havana
        let today = TestCalendar.instant(calendar, 2026, 3, 12)
        let scope = T.scope(.empty, T.context(period: .month, today: today, calendar: calendar))
        #expect(scope.days.count == 30)
        #expect(scope.previousDays.count == 30)
        for day in scope.days + scope.previousDays {
            #expect(calendar.startOfDay(for: day) == day)
        }
        #expect(Set(scope.days).count == 30)
    }

    @Test("A daily binary habit: done, missed, and today as a grace day")
    func binaryOutcomes() {
        // The first completion (day -3) is the habit's effective start.
        let habit = T.habit(doneOffsets: [-3, -1])
        let scope = T.scope(InsightsInput(habits: [habit]))
        #expect(scope.outcome(of: habit, on: T.day(-1)) == .due(done: true))
        #expect(scope.outcome(of: habit, on: T.day(-2)) == .due(done: false))
        #expect(scope.outcome(of: habit, on: T.day(0)) == .notCounted)
        #expect(scope.outcome(of: habit, on: T.day(1)) == .notCounted)
    }

    @Test("Today counts once it is done")
    func todayDone() {
        let habit = T.habit(doneOffsets: [0])
        let scope = T.scope(InsightsInput(habits: [habit]))
        #expect(scope.outcome(of: habit, on: T.day(0)) == .due(done: true))
    }

    @Test("A counter needs its full target to be done")
    func counterTarget() {
        let half = T.habit(type: .counter(target: 8), doneOffsets: [-1], value: 4)
        let full = T.habit(type: .counter(target: 8), doneOffsets: [-1], value: 8)
        let scope = T.scope(InsightsInput(habits: [half, full]))
        #expect(scope.outcome(of: half, on: T.day(-1)) == .due(done: false))
        #expect(scope.outcome(of: full, on: T.day(-1)) == .due(done: true))
    }

    @Test("A negative habit is done without a slip, and today never counts")
    func negativeHabit() {
        let habit = T.habit(type: .negative, doneOffsets: [-2])
        let scope = T.scope(InsightsInput(habits: [habit]))
        #expect(scope.outcome(of: habit, on: T.day(-1)) == .due(done: true))
        #expect(scope.outcome(of: habit, on: T.day(-2)) == .due(done: false))
        #expect(scope.outcome(of: habit, on: T.day(0)) == .notCounted)
    }

    @Test("A logged day the schedule did not ask for is off schedule")
    func offSchedule() {
        // Reference day is a Monday; the habit is due on Wednesdays only.
        // Day -12 is a Wednesday done, which also sets the effective start.
        let habit = T.habit(frequency: .specificDays([.wednesday]), doneOffsets: [-12, -1])
        let scope = T.scope(InsightsInput(habits: [habit]))
        #expect(scope.outcome(of: habit, on: T.day(-1)) == .offSchedule)
        #expect(scope.outcome(of: habit, on: T.day(-2)) == .notCounted)
        #expect(scope.outcome(of: habit, on: T.day(-5)) == .due(done: false))
    }

    @Test("Days before the first completion do not count once there is one")
    func effectiveStart() {
        let habit = T.habit(createdDaysAgo: 30, doneOffsets: [-1])
        let scope = T.scope(InsightsInput(habits: [habit]))
        #expect(scope.outcome(of: habit, on: T.day(-2)) == .notCounted)
        let never = T.habit(createdDaysAgo: 30)
        let scope2 = T.scope(InsightsInput(habits: [never]))
        #expect(scope2.outcome(of: never, on: T.day(-2)) == .due(done: false))
    }

    @Test("Nothing counts before the habit starts or after it is archived")
    func lifecycleBounds() {
        let habit = T.habit(createdDaysAgo: 3, archivedOffset: -1, doneOffsets: [-3, -2])
        let scope = T.scope(InsightsInput(habits: [habit]))
        #expect(scope.outcome(of: habit, on: T.day(-4)) == .notCounted)
        #expect(scope.outcome(of: habit, on: T.day(-2)) == .due(done: true))
        #expect(scope.outcome(of: habit, on: T.day(0)) == .notCounted)
    }

    @Test("Sessions belong to the logical day they started on")
    func sessionDay() {
        let session = T.session(offset: 0, hour: 2, minutes: 30)
        let scope = T.scope(.empty, T.context(startHour: 4))
        #expect(scope.sessionDay(session) == T.day(-1))
    }
}
