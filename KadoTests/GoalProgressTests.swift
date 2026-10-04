import Foundation
import Testing
import KadoCore

@Suite("Goal progress calculation")
struct GoalProgressTests {
    let goalID = UUID()
    let today = Date(timeIntervalSince1970: 1_700_000_000)
    var calendar: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(secondsFromGMT: 0)!; return c }

    @Test func numericDraftRejectsPartialAndEmptyText() {
        #expect(GoalProgressNumber.parse("", locale: Locale(identifier: "en_US")) == nil)
        #expect(GoalProgressNumber.parse("abc", locale: Locale(identifier: "en_US")) == nil)
        #expect(GoalProgressNumber.parse("3junk", locale: Locale(identifier: "en_US")) == nil)
        #expect(GoalProgressNumber.parse("1,5", locale: Locale(identifier: "fr_FR")) == 1.5)
        #expect(GoalProgressNumber.parse("2.5", locale: Locale(identifier: "en_US")) == 2.5)
    }
    @Test func manualDeduplicationAndPeriod() {
        let id = UUID()
        let entry = GoalProgressEntry(id: id, goalID: goalID, date: today, amount: 5)
        let entries = [entry, entry, GoalProgressEntry(goalID: goalID, date: today.addingTimeInterval(86400), amount: 99)]
        let result = GoalProgressCalculator.calculate(goalID: goalID, measurement: GoalMeasurement(enabled: true, baseline: 10, target: 20, unit: "pages"), today: today, calendar: calendar, entries: entries)
        #expect(result.current == 15)
        #expect(result.fraction == 0.5)
        #expect(result.contributions.count == 1)
    }
    @Test func missingSourceIsUnavailable() {
        let result = GoalProgressCalculator.calculate(goalID: goalID, measurement: GoalMeasurement(enabled: true, mode: .habit, target: 10, unit: "pages", habitID: UUID()), today: today, calendar: calendar)
        #expect(!result.isAvailable)
    }
    @Test func timerConvertsSecondsAndIgnoresOtherHabits() {
        let habit = Habit(name: "Read", frequency: .daily, type: .timer(targetSeconds: 60), createdAt: today, goalID: goalID)
        let result = GoalProgressCalculator.calculate(goalID: goalID, measurement: GoalMeasurement(enabled: true, mode: .habit, target: 10, unit: "minutes", habitID: habit.id), today: today, calendar: calendar, habits: [habit], completions: [Completion(habitID: habit.id, date: today, value: 120), Completion(habitID: UUID(), date: today, value: 1000)])
        #expect(result.current == 2)
        #expect(result.unit == "minutes")
    }
    @Test func tasksCountOnceAndReopeningRemovesContribution() {
        var task = TaskBackup(id: UUID(), title: "One", createdAt: today, updatedAt: today, completedAt: today, goalID: goalID)
        let measurement = GoalMeasurement(enabled: true, mode: .tasks, target: 1, unit: "tasks")
        let result = GoalProgressCalculator.calculate(goalID: goalID, measurement: measurement, today: today, calendar: calendar, tasks: [task, task])
        #expect(result.current == 1)
        task.completedAt = nil
        #expect(GoalProgressCalculator.calculate(goalID: goalID, measurement: measurement, today: today, calendar: calendar, tasks: [task]).current == 0)
    }
    @Test func overflowIsUnavailableAndFixedModeKeepsCustomUnit() {
        let overflow = GoalProgressCalculator.calculate(goalID: goalID, measurement: GoalMeasurement(enabled: true, baseline: Double.greatestFiniteMagnitude / 2, target: Double.greatestFiniteMagnitude, unit: "pages"), today: today, calendar: calendar, entries: [GoalProgressEntry(goalID: goalID, date: today, amount: Double.greatestFiniteMagnitude)])
        #expect(!overflow.isAvailable)
        var measurement = GoalMeasurement(enabled: true, target: 10, unit: "pages")
        measurement.mode = .tasks
        let tasksResult = GoalProgressCalculator.calculate(goalID: goalID, measurement: measurement, today: today, calendar: calendar)
        #expect(tasksResult.unit == "tasks")
        measurement.mode = .manual
        #expect(measurement.unit == "pages")
    }
    @Test func validationAndOverTarget() {
        #expect(!GoalMeasurement(enabled: true, baseline: 3, target: 2, unit: "pages").isValid)
        #expect(!GoalMeasurement(enabled: true, target: .infinity, unit: "pages").isValid)
        let result = GoalProgressCalculator.calculate(goalID: goalID, measurement: GoalMeasurement(enabled: true, target: 2, unit: "pages"), today: today, calendar: calendar, entries: [GoalProgressEntry(goalID: goalID, date: today, amount: 5)])
        #expect(result.current == 5)
        #expect(result.fraction == 1)
    }
    @Test func startDateAndReassignment() {
        let habit = Habit(name: "Pages", frequency: .daily, type: .counter(target: 10), createdAt: today, goalID: UUID())
        let measurement = GoalMeasurement(enabled: true, mode: .habit, target: 10, unit: "pages", habitID: habit.id)
        #expect(!GoalProgressCalculator.calculate(goalID: goalID, measurement: measurement, today: today, calendar: calendar, habits: [habit]).isAvailable)
        let entries = [GoalProgressEntry(goalID: goalID, date: today.addingTimeInterval(-86400), amount: 3), GoalProgressEntry(goalID: goalID, date: today, amount: 2)]
        #expect(GoalProgressCalculator.calculate(goalID: goalID, measurement: GoalMeasurement(enabled: true, target: 10, unit: "pages"), startDate: today, today: today, calendar: calendar, entries: entries).current == 2)
    }
}
