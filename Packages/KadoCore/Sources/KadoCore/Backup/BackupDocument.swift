import Foundation

/// Root of the JSON backup format exchanged by export / import.
///
/// The wire shape is decoupled from the SwiftData schema on purpose:
/// a schema bump that renames or reshapes `HabitRecord` must not
/// silently change what a previously exported file means. Bump
/// `formatVersion` and migrate explicitly.
public struct BackupDocument: Hashable, Codable, Sendable {
    /// Current format version written by this app. Importers compare
    /// against `BackupDocument.currentFormatVersion` and refuse files
    /// with a higher value than they understand.
    ///
    /// Version 6 adds `category` to habits, tasks and goals.
    public static let currentFormatVersion = 6

    public var formatVersion: Int
    public var exportedAt: Date
    public var appVersion: String
    public var habits: [HabitBackup]
    public var tasks: [TaskBackup]
    public var scheduleBlocks: [ScheduleBlockBackup]
    public var goals: [GoalBackup]
    public var goalProgressEntries: [GoalProgressEntry]
    public var workSessions: [WorkSessionBackup]

    public init(
        formatVersion: Int = BackupDocument.currentFormatVersion,
        exportedAt: Date,
        appVersion: String,
        habits: [HabitBackup],
        tasks: [TaskBackup] = [],
        scheduleBlocks: [ScheduleBlockBackup] = [],
        goals: [GoalBackup] = [],
        goalProgressEntries: [GoalProgressEntry] = [],
        workSessions: [WorkSessionBackup] = []
    ) {
        self.formatVersion = formatVersion
        self.exportedAt = exportedAt
        self.appVersion = appVersion
        self.habits = habits
        self.tasks = tasks
        self.scheduleBlocks = scheduleBlocks
        self.goals = goals
        self.goalProgressEntries = goalProgressEntries
        self.workSessions = workSessions
    }

    private enum CodingKeys: String, CodingKey {
        case formatVersion, exportedAt, appVersion, habits, tasks, scheduleBlocks, goals, goalProgressEntries, workSessions
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        formatVersion = try values.decode(Int.self, forKey: .formatVersion)
        exportedAt = try values.decode(Date.self, forKey: .exportedAt)
        appVersion = try values.decode(String.self, forKey: .appVersion)
        habits = try values.decode([HabitBackup].self, forKey: .habits)
        // Version 1 predates tasks and scheduling. Missing collections
        // have a defined migration instead of making older exports fail.
        tasks = try values.decodeIfPresent([TaskBackup].self, forKey: .tasks) ?? []
        scheduleBlocks = try values.decodeIfPresent([ScheduleBlockBackup].self, forKey: .scheduleBlocks) ?? []
        // Versions 1 and 2 predate goals and owner-to-goal links.
        goals = try values.decodeIfPresent([GoalBackup].self, forKey: .goals) ?? []
        goalProgressEntries = try values.decodeIfPresent([GoalProgressEntry].self, forKey: .goalProgressEntries) ?? []
        // Versions 1 to 4 predate tracked work sessions.
        workSessions = try values.decodeIfPresent([WorkSessionBackup].self, forKey: .workSessions) ?? []
    }
}
