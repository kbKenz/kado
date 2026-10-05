import Foundation
import Testing
@testable import KadoCore

@Suite("Insights movement")
struct InsightsMovementTests {
    typealias T = InsightsTestSupport

    private func calculate(_ input: InsightsInput, _ context: InsightsContext = T.context()) -> InsightsMovement {
        InsightsCalculator.movement(T.scope(input, context))
    }

    /// A workout that starts at `hour:00` on the day `offset` days from
    /// the reference day and lasts `minutes`.
    private func workout(_ name: String, offset: Int, hour: Int = 7, minutes: Double) -> InsightsWorkout {
        InsightsWorkout(name: name, interval: DateInterval(start: T.time(offset, hour), duration: minutes * 60))
    }

    private func connected(_ workouts: [InsightsWorkout]) -> InsightsInput {
        InsightsInput(health: InsightsHealth(isConnected: true, workouts: workouts))
    }

    @Test("Empty input: Health not connected, nothing done, no averages")
    func empty() {
        #expect(calculate(.empty) == .empty)
    }

    @Test("Workouts that started in the period: count, total, average and most frequent type")
    func workouts() {
        let movement = calculate(connected([
            workout("Running", offset: -6, minutes: 30),
            workout("Running", offset: -4, minutes: 40),
            workout("Yoga", offset: -3, minutes: 60),
            workout("Running", offset: -1, minutes: 50),
            workout("Yoga", offset: 0, minutes: 60),
            workout("Cycling", offset: -7, minutes: 90),   // previous period
            workout("Cycling", offset: -14, minutes: 90),  // before both periods
        ]))
        #expect(movement.isHealthConnected)
        #expect(movement.workoutCount == 5)
        #expect(movement.workoutTotal == 240.0 * 60)
        #expect(movement.averageWorkout == 48.0 * 60)
        #expect(movement.topWorkout == InsightsNamedCount(name: "Running", count: 3))
        #expect(movement.previousWorkoutCount == 1)
    }

    @Test("Most frequent workout: ties go to more time, then to the name")
    func topWorkoutTies() {
        let byTime = calculate(connected([
            workout("Running", offset: -2, minutes: 20),
            workout("Cycling", offset: -2, hour: 9, minutes: 30),
            workout("Running", offset: -1, minutes: 20),
            workout("Cycling", offset: -1, hour: 9, minutes: 30),
        ]))
        #expect(byTime.topWorkout == InsightsNamedCount(name: "Cycling", count: 2))
        let byName = calculate(connected([
            workout("Swimming", offset: -2, minutes: 30),
            workout("Rowing", offset: -1, minutes: 30),
        ]))
        #expect(byName.topWorkout == InsightsNamedCount(name: "Rowing", count: 1))
    }

    @Test("A workout belongs to the civil day it started on, whatever the day-start hour")
    func workoutStartDay() {
        let lateWalk = InsightsWorkout(name: "Walk", interval: DateInterval(start: T.time(-7, 23, 30), end: T.time(-6, 0, 30)))
        let earlySwim = workout("Swim", offset: -6, hour: 2, minutes: 30)
        let movement = calculate(connected([lateWalk, earlySwim]), T.context(startHour: 4))
        #expect(movement.workoutCount == 1)
        #expect(movement.topWorkout == InsightsNamedCount(name: "Swim", count: 1))
        #expect(movement.previousWorkoutCount == 1)
    }

    @Test("Fitness times done: days with a record on fitness habits, plus fitness tasks done")
    func timesDone() {
        let run = T.habit("Run", category: .fitness, doneOffsets: [-9, -3, -1, 0])
        let pushUps = T.habit("Push-ups", type: .counter(target: 20), category: .fitness, doneOffsets: [-2, -2], value: 5)
        let oldGym = T.habit("Gym", category: .fitness, archivedOffset: -2, doneOffsets: [-4])
        let noElevator = T.habit("No elevator", type: .negative, category: .fitness, doneOffsets: [-2])
        let read = T.habit("Read", category: .study, doneOffsets: [-1])
        let tasks = [
            T.task("Buy shoes", category: .fitness, completedOffset: -1),
            T.task("Book a class", category: .fitness, completedOffset: -8),
            T.task("Race", category: .fitness, completedOffset: -2, isCancelled: true),
            T.task("Team meeting", category: .work, completedOffset: -1),
            T.task("Plan a hike", category: .fitness, plannedOffsets: [-1]),
        ]
        let movement = calculate(InsightsInput(habits: [run, pushUps, oldGym, noElevator, read], tasks: tasks))
        // Run 3 (today included), push-ups 1 (two records, one day), gym 1 (archived later), shoes 1.
        // A slip on a negative habit is never a time done.
        #expect(movement.fitnessTimesDone == 6)
        // Run on day -9 and the class on day -8.
        #expect(movement.previousFitnessTimesDone == 2)
    }

    @Test("Fitness time: timer values plus sessions that are not on a timer habit")
    func trackedTime() {
        let stretch = T.habit(
            "Stretch", type: .timer(targetSeconds: 1800), category: .fitness,
            archivedOffset: -2, doneOffsets: [-3], value: 1200
        )
        let plank = T.habit("Plank", type: .timer(targetSeconds: 1800), category: .fitness, doneOffsets: [-8, -1], value: 1800)
        let meditate = T.habit("Meditate", type: .timer(targetSeconds: 600), category: .mind, doneOffsets: [-1], value: 600)
        let run = T.habit("Run", category: .fitness, doneOffsets: [-2])
        let sessions = [
            T.session(offset: -1, minutes: 30, category: .fitness, habitID: plank.id),  // already in Plank's value
            T.session(offset: -2, minutes: 45, category: .fitness, taskID: UUID()),
            T.session(offset: -2, hour: 18, minutes: 15, category: .fitness, habitID: run.id),
            T.session(offset: -2, hour: 12, minutes: 60, category: .work),
            T.session(offset: -8, minutes: 20, category: .fitness),                       // previous period
        ]
        let movement = calculate(InsightsInput(habits: [stretch, plank, meditate, run], sessions: sessions))
        // 1200 + 1800 timer seconds, plus 45 and 15 minutes of sessions: 6600 s over 4 occurrences.
        #expect(movement.fitnessTrackedTime == 6600.0)
        #expect(movement.averageFitnessTime == 1650.0)
    }

    @Test("Fitness habits: active ones only, with their consistency; today is a grace day")
    func habits() {
        let run = T.habit("Run", category: .fitness, doneOffsets: [-6, -4, -2], icon: "figure.run")
        let oldGym = T.habit("Gym", category: .fitness, archivedOffset: -3, doneOffsets: [-6])
        let read = T.habit("Read", category: .study, doneOffsets: [-1])
        let movement = calculate(InsightsInput(habits: [run, oldGym, read]))
        #expect(movement.habits == [
            InsightsHabitConsistency(
                habitID: run.id, name: "Run", icon: "figure.run", color: .blue,
                rate: InsightsRate(done: 3, total: 6)
            ),
        ])
    }

    @Test("Havana: fitness days around the midnight DST change count once each")
    func havana() {
        let calendar = TestCalendar.havana
        // Day -36 is 2026-03-08, when Havana's clock skips from 00:00 to
        // 01:00; day -32 is 2026-03-12.
        let run = T.habit("Run", category: .fitness, doneOffsets: [-37, -36, -35], calendar: calendar)
        let context = T.context(period: .week, today: T.day(-32, calendar: calendar), calendar: calendar)
        let workout = InsightsWorkout(
            name: "Run",
            interval: DateInterval(start: TestCalendar.instant(calendar, 2026, 3, 8, 7), duration: 1800)
        )
        let input = InsightsInput(habits: [run], health: InsightsHealth(isConnected: true, workouts: [workout]))
        let movement = InsightsCalculator.movement(T.scope(input, context))
        #expect(movement.fitnessTimesDone == 3)
        #expect(movement.workoutCount == 1)
        #expect(movement.previousWorkoutCount == 0)
    }
}
