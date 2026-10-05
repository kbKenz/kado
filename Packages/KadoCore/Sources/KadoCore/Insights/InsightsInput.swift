import Foundation

/// The window the Insights feed summarizes: a rolling run of logical
/// days that ends with today, compared with the run just before it.
nonisolated public enum InsightsPeriod: String, CaseIterable, Codable, Hashable, Sendable, Identifiable {
    case week
    case month
    case year

    public var id: String { rawValue }

    /// Logical days in the window, today included.
    public var dayCount: Int {
        switch self {
        case .week: 7
        case .month: 30
        case .year: 365
        }
    }
}

// MARK: - Input values

/// A habit with what the Insights read, as values. Archived habits are
/// included (their past days still count); `habit.archivedAt` says so.
nonisolated public struct InsightsHabit: Hashable, Sendable, Identifiable {
    public var habit: Habit
    /// Resolved by the caller: stored category, else the goal's, else
    /// the keyword classifier, else `.other`.
    public var category: ItemCategory
    /// This habit's completions only. Zero-value (note-only) records
    /// may be present; calculators ignore them.
    public var completions: [Completion]

    public var id: UUID { habit.id }

    public init(habit: Habit, category: ItemCategory, completions: [Completion]) {
        self.habit = habit
        self.category = category
        self.completions = completions
    }
}

/// A task, as values. Day fields are civil midnights.
nonisolated public struct InsightsTask: Hashable, Sendable, Identifiable {
    public var id: UUID
    public var title: String
    public var category: ItemCategory
    public var createdAt: Date
    public var completedAt: Date?
    public var archivedAt: Date?
    /// Civil midnight of the due date, if any.
    public var dueDay: Date?
    /// Civil midnights of the days the task is planned on (its schedule
    /// blocks' `plannedDay`), ascending, no duplicates.
    public var plannedDays: [Date]
    public var goalID: UUID?
    /// An imported calendar event cancelled upstream. Every calculator
    /// skips it.
    public var isCancelled: Bool

    public init(
        id: UUID,
        title: String,
        category: ItemCategory,
        createdAt: Date,
        completedAt: Date? = nil,
        archivedAt: Date? = nil,
        dueDay: Date? = nil,
        plannedDays: [Date] = [],
        goalID: UUID? = nil,
        isCancelled: Bool = false
    ) {
        self.id = id
        self.title = title
        self.category = category
        self.createdAt = createdAt
        self.completedAt = completedAt
        self.archivedAt = archivedAt
        self.dueDay = dueDay
        self.plannedDays = plannedDays
        self.goalID = goalID
        self.isCancelled = isCancelled
    }

    /// The day the task was meant to happen: its last planned day, else
    /// its due day. `nil` for a task with neither.
    public var targetDay: Date? { plannedDays.last ?? dueDay }
}

/// A tracked work session, as values.
nonisolated public struct InsightsSession: Hashable, Sendable, Identifiable {
    public var id: UUID
    public var session: WorkSession
    /// The category of the task or habit it ran on.
    public var category: ItemCategory
    public var taskID: UUID?
    public var habitID: UUID?
    /// The linked block's planned range, when that block has both a
    /// start and an end.
    public var plannedRange: DateInterval?

    public init(
        id: UUID,
        session: WorkSession,
        category: ItemCategory,
        taskID: UUID? = nil,
        habitID: UUID? = nil,
        plannedRange: DateInterval? = nil
    ) {
        self.id = id
        self.session = session
        self.category = category
        self.taskID = taskID
        self.habitID = habitID
        self.plannedRange = plannedRange
    }
}

/// A goal, as values.
nonisolated public struct InsightsGoal: Hashable, Sendable, Identifiable {
    public var id: UUID
    public var name: String
    public var category: ItemCategory
    public var status: GoalStatus
    public var isArchived: Bool
    public var startDate: Date?
    public var targetDate: Date?
    public var createdAt: Date
    /// 0...1 when the goal has a measurement and its progress is
    /// available (`GoalProgressCalculator`), else `nil`.
    public var progress: Double?
    public var linkedTaskIDs: [UUID]
    public var linkedHabitIDs: [UUID]

    public init(
        id: UUID,
        name: String,
        category: ItemCategory,
        status: GoalStatus = .active,
        isArchived: Bool = false,
        startDate: Date? = nil,
        targetDate: Date? = nil,
        createdAt: Date,
        progress: Double? = nil,
        linkedTaskIDs: [UUID] = [],
        linkedHabitIDs: [UUID] = []
    ) {
        self.id = id
        self.name = name
        self.category = category
        self.status = status
        self.isArchived = isArchived
        self.startDate = startDate
        self.targetDate = targetDate
        self.createdAt = createdAt
        self.progress = progress
        self.linkedTaskIDs = linkedTaskIDs
        self.linkedHabitIDs = linkedHabitIDs
    }
}

/// One Apple Health workout, read live and never stored.
nonisolated public struct InsightsWorkout: Hashable, Sendable {
    /// Already localized for display.
    public var name: String
    public var interval: DateInterval

    public init(name: String, interval: DateInterval) {
        self.name = name
        self.interval = interval
    }
}

/// Apple Health data for the window, read live and never stored.
nonisolated public struct InsightsHealth: Hashable, Sendable {
    /// The user turned Apple Health on and the device has it. When
    /// `false`, `sleep` and `workouts` are empty and the cards offer to
    /// connect instead of showing zeros.
    public var isConnected: Bool
    /// Merged sleep sessions (`SleepSessionBuilder` output) that overlap
    /// the current or the previous window.
    public var sleep: [DateInterval]
    /// Workouts that overlap the current or the previous window.
    public var workouts: [InsightsWorkout]

    public init(isConnected: Bool, sleep: [DateInterval] = [], workouts: [InsightsWorkout] = []) {
        self.isConnected = isConnected
        self.sleep = sleep
        self.workouts = workouts
    }

    public static let disconnected = InsightsHealth(isConnected: false)
}

/// Everything the calculator reads.
nonisolated public struct InsightsInput: Hashable, Sendable {
    public var habits: [InsightsHabit]
    public var tasks: [InsightsTask]
    public var sessions: [InsightsSession]
    public var goals: [InsightsGoal]
    public var health: InsightsHealth

    public init(
        habits: [InsightsHabit] = [],
        tasks: [InsightsTask] = [],
        sessions: [InsightsSession] = [],
        goals: [InsightsGoal] = [],
        health: InsightsHealth = .disconnected
    ) {
        self.habits = habits
        self.tasks = tasks
        self.sessions = sessions
        self.goals = goals
        self.health = health
    }

    public static let empty = InsightsInput()
}
