import Foundation
import KadoCore

/// What `GoalProgressCalculator` reads for a set of measured goals,
/// gathered in one pass over each table. The Goals list used to
/// snapshot every entry, task, habit and completion once per row.
///
/// Each goal gets only the records the calculator would have kept
/// from the full tables — its own entries and tasks, the measured
/// habit, that habit's completions — in their original order. The
/// calculator filters by the same ids, so the result is the same.
/// Links are read from each record's own side (`goal`, `habit`), as
/// the full-table snapshots did, not from the goal's inverse lists.
struct GoalProgressInputs {
    private var entriesByGoal: [UUID: [GoalProgressEntry]] = [:]
    private var tasksByGoal: [UUID: [TaskBackup]] = [:]
    private var habitsByID: [UUID: [Habit]] = [:]
    private var completionsByHabit: [UUID: [Completion]] = [:]

    /// Only the tables a measured goal's mode reads are walked: a list
    /// of manual goals never touches completions.
    init(
        measurements: [GoalMeasurement],
        entries: [GoalProgressEntryRecord],
        tasks: [TaskRecord],
        habits: [HabitRecord],
        completions: [CompletionRecord]
    ) {
        let measured = measurements.filter(\.enabled)
        if measured.contains(where: { $0.mode == .manual }) {
            for record in entries {
                guard let entry = record.snapshot else { continue }
                entriesByGoal[entry.goalID, default: []].append(entry)
            }
        }
        if measured.contains(where: { $0.mode == .tasks }) {
            for task in tasks {
                guard let goalID = task.goal?.id else { continue }
                tasksByGoal[goalID, default: []].append(TaskBackup(
                    id: task.id, title: task.title, createdAt: task.createdAt,
                    updatedAt: task.updatedAt, completedAt: task.completedAt, goalID: goalID
                ))
            }
        }
        let habitIDs = Set(measured.filter { $0.mode == .habit }.compactMap(\.habitID))
        if !habitIDs.isEmpty {
            for habit in habits where habitIDs.contains(habit.id) {
                habitsByID[habit.id, default: []].append(habit.snapshot)
            }
            for record in completions {
                guard let habitID = record.habit?.id, habitIDs.contains(habitID),
                      let completion = record.snapshot else { continue }
                completionsByHabit[habitID, default: []].append(completion)
            }
        }
    }

    func progress(
        goalID: UUID, measurement: GoalMeasurement, startDate: Date?,
        today: Date, calendar: Calendar
    ) -> GoalProgressResult {
        let habitID = measurement.habitID
        return GoalProgressCalculator.calculate(
            goalID: goalID, measurement: measurement, startDate: startDate, today: today, calendar: calendar,
            entries: entriesByGoal[goalID] ?? [],
            tasks: tasksByGoal[goalID] ?? [],
            habits: habitID.flatMap { habitsByID[$0] } ?? [],
            completions: habitID.flatMap { completionsByHabit[$0] } ?? []
        )
    }
}
