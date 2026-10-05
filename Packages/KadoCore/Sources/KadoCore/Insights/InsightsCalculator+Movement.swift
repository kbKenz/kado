import Foundation

extension InsightsCalculator {
    /// Apple Health workouts and Fitness-category habits and tasks.
    /// Rules: see `InsightsMovement` in InsightsReport.swift.
    static func movement(_ scope: InsightsScope) -> InsightsMovement {
        let workouts = InsightsSharedB.workouts(on: scope.days, scope)
        let workoutTotal = workouts.reduce(0) { $0 + $1.interval.duration }
        let tracked = InsightsSharedB.fitnessTrackedTime(scope)
        return InsightsMovement(
            isHealthConnected: scope.input.health.isConnected,
            workoutCount: workouts.count,
            previousWorkoutCount: InsightsSharedB.workouts(on: scope.previousDays, scope).count,
            workoutTotal: workoutTotal,
            averageWorkout: workouts.isEmpty ? nil : workoutTotal / Double(workouts.count),
            topWorkout: InsightsSharedB.topWorkout(workouts),
            fitnessTimesDone: InsightsSharedB.fitnessTimesDone(on: scope.days, scope),
            previousFitnessTimesDone: InsightsSharedB.fitnessTimesDone(on: scope.previousDays, scope),
            fitnessTrackedTime: tracked.seconds,
            averageFitnessTime: tracked.occurrences > 0 ? tracked.seconds / Double(tracked.occurrences) : nil,
            habits: InsightsSharedB.activeHabits(in: .fitness, scope)
        )
    }
}

private extension InsightsSharedB {
    struct WorkoutTally {
        var count = 0
        var seconds: TimeInterval = 0
    }

    /// Workouts that started (civil day) on one of `days`.
    static func workouts(on days: [Date], _ scope: InsightsScope) -> [InsightsWorkout] {
        let keys = Set(days)
        return scope.input.health.workouts.filter { keys.contains(scope.civilDay($0.interval.start)) }
    }

    /// The most frequent workout name. Ties go to the larger total time,
    /// then to the name that sorts first.
    static func topWorkout(_ workouts: [InsightsWorkout]) -> InsightsNamedCount? {
        var tallies: [String: WorkoutTally] = [:]
        for workout in workouts {
            tallies[workout.name, default: WorkoutTally()].count += 1
            tallies[workout.name, default: WorkoutTally()].seconds += workout.interval.duration
        }
        let top = tallies.max { lhs, rhs in
            if lhs.value.count != rhs.value.count { return lhs.value.count < rhs.value.count }
            if lhs.value.seconds != rhs.value.seconds { return lhs.value.seconds < rhs.value.seconds }
            return lhs.key > rhs.key
        }
        return top.map { InsightsNamedCount(name: $0.key, count: $0.value.count) }
    }

    /// Days with a positive record on each Fitness habit that is not
    /// negative (archived ones included), plus the Fitness tasks
    /// completed on `days`.
    static func fitnessTimesDone(on days: [Date], _ scope: InsightsScope) -> Int {
        let habitDays = scope.input.habits
            .filter { $0.category == .fitness && !isNegative($0.habit.type) }
            .reduce(0) { sum, habit in
                sum + days.filter { !scope.positiveRecords(of: habit, on: $0).isEmpty }.count
            }
        let keys = Set(days)
        let tasksDone = scope.input.tasks.filter { task in
            guard task.category == .fitness, !task.isCancelled, let completedAt = task.completedAt else {
                return false
            }
            return keys.contains(scope.civilDay(completedAt))
        }.count
        return habitDays + tasksDone
    }

    /// Timer seconds of Fitness habits on period days, plus the Fitness
    /// sessions of the period that did not run on a timer habit. Also
    /// counts how many of these carried time.
    static func fitnessTrackedTime(_ scope: InsightsScope) -> (seconds: TimeInterval, occurrences: Int) {
        var seconds: TimeInterval = 0
        var occurrences = 0
        for habit in scope.input.habits where habit.category == .fitness && isTimer(habit.habit.type) {
            for day in scope.days {
                let records = scope.positiveRecords(of: habit, on: day)
                guard !records.isEmpty else { continue }
                seconds += records.reduce(0) { $0 + $1.value }
                occurrences += 1
            }
        }
        // A timer habit's session time is already in its completion value.
        let timerHabits = Set(scope.input.habits.filter { isTimer($0.habit.type) }.map(\.id))
        for session in trackedSessions(scope, on: scope.days) where session.source.category == .fitness {
            if let habitID = session.source.habitID, timerHabits.contains(habitID) { continue }
            seconds += session.seconds
            occurrences += 1
        }
        return (seconds, occurrences)
    }
}
