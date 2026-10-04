import Foundation

/// Counts reported by an import run, used both as a dry-run preview in
/// the confirmation sheet and as the outcome after a successful merge.
public struct ImportSummary: Hashable, Sendable {
    public var totalHabits: Int
    public var newHabits: Int
    public var updatedHabits: Int
    public var totalCompletions: Int
    public var newCompletions: Int
    public var updatedCompletions: Int
    public var totalTasks: Int
    public var newTasks: Int
    public var updatedTasks: Int
    public var totalScheduleBlocks: Int
    public var newScheduleBlocks: Int
    public var updatedScheduleBlocks: Int
    public var totalGoalProgressEntries: Int
    public var newGoalProgressEntries: Int
    public var updatedGoalProgressEntries: Int
    public var totalGoals: Int
    public var newGoals: Int
    public var updatedGoals: Int
    public var totalWorkSessions: Int
    public var newWorkSessions: Int
    public var updatedWorkSessions: Int

    public init(
        totalHabits: Int = 0,
        newHabits: Int = 0,
        updatedHabits: Int = 0,
        totalCompletions: Int = 0,
        newCompletions: Int = 0,
        updatedCompletions: Int = 0,
        totalTasks: Int = 0,
        newTasks: Int = 0,
        updatedTasks: Int = 0,
        totalScheduleBlocks: Int = 0,
        newScheduleBlocks: Int = 0,
        updatedScheduleBlocks: Int = 0,
        totalGoals: Int = 0,
        newGoals: Int = 0,
        updatedGoals: Int = 0,
        totalGoalProgressEntries: Int = 0, newGoalProgressEntries: Int = 0, updatedGoalProgressEntries: Int = 0,
        totalWorkSessions: Int = 0, newWorkSessions: Int = 0, updatedWorkSessions: Int = 0
    ) {
        self.totalHabits = totalHabits
        self.newHabits = newHabits
        self.updatedHabits = updatedHabits
        self.totalCompletions = totalCompletions
        self.newCompletions = newCompletions
        self.updatedCompletions = updatedCompletions
        self.totalTasks = totalTasks
        self.newTasks = newTasks
        self.updatedTasks = updatedTasks
        self.totalScheduleBlocks = totalScheduleBlocks
        self.newScheduleBlocks = newScheduleBlocks
        self.updatedScheduleBlocks = updatedScheduleBlocks
        self.totalGoalProgressEntries = totalGoalProgressEntries
        self.newGoalProgressEntries = newGoalProgressEntries
        self.updatedGoalProgressEntries = updatedGoalProgressEntries
        self.totalGoals = totalGoals
        self.newGoals = newGoals
        self.updatedGoals = updatedGoals
        self.totalWorkSessions = totalWorkSessions
        self.newWorkSessions = newWorkSessions
        self.updatedWorkSessions = updatedWorkSessions
    }
}
