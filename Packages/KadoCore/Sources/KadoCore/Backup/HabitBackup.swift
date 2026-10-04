import Foundation

/// DTO mirror of `Habit` with completions nested underneath. The
/// nested shape avoids orphan completions on import (no dangling
/// `habitID` references) and matches the SwiftData relationship graph.
public struct HabitBackup: Hashable, Codable, Sendable {
    public var id: UUID
    public var name: String
    public var frequency: Frequency
    public var type: HabitType
    public var createdAt: Date
    public var archivedAt: Date?
    public var color: HabitColor
    public var icon: String
    public var remindersEnabled: Bool
    public var reminderHour: Int
    public var reminderMinute: Int
    public var sortOrder: Int
    public var completions: [CompletionBackup]
    public var goalID: UUID?

    public init(
        id: UUID,
        name: String,
        frequency: Frequency,
        type: HabitType,
        createdAt: Date,
        archivedAt: Date? = nil,
        color: HabitColor,
        icon: String,
        remindersEnabled: Bool,
        reminderHour: Int,
        reminderMinute: Int,
        completions: [CompletionBackup],
        sortOrder: Int = 0,
        goalID: UUID? = nil
    ) {
        self.id = id
        self.name = name
        self.frequency = frequency
        self.type = type
        self.createdAt = createdAt
        self.archivedAt = archivedAt
        self.color = color
        self.icon = icon
        self.remindersEnabled = remindersEnabled
        self.reminderHour = reminderHour
        self.reminderMinute = reminderMinute
        self.completions = completions
        self.sortOrder = sortOrder
        self.goalID = goalID
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, frequency, type, createdAt, archivedAt, color, icon
        case remindersEnabled, reminderHour, reminderMinute, completions, sortOrder, goalID
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        name = try values.decode(String.self, forKey: .name)
        frequency = try values.decode(Frequency.self, forKey: .frequency)
        type = try values.decode(HabitType.self, forKey: .type)
        createdAt = try values.decode(Date.self, forKey: .createdAt)
        archivedAt = try values.decodeIfPresent(Date.self, forKey: .archivedAt)
        color = try values.decode(HabitColor.self, forKey: .color)
        icon = try values.decode(String.self, forKey: .icon)
        remindersEnabled = try values.decode(Bool.self, forKey: .remindersEnabled)
        reminderHour = try values.decode(Int.self, forKey: .reminderHour)
        reminderMinute = try values.decode(Int.self, forKey: .reminderMinute)
        completions = try values.decode([CompletionBackup].self, forKey: .completions)
        sortOrder = try values.decodeIfPresent(Int.self, forKey: .sortOrder) ?? 0
        goalID = try values.decodeIfPresent(UUID.self, forKey: .goalID)
    }
}

public extension HabitBackup {
    /// Build a backup DTO from a domain `Habit` and its associated
    /// completions. The completions are filtered to those whose
    /// `habitID` matches this habit, then sorted by date for a stable
    /// on-disk order.
    init(habit: Habit, completions: [Completion]) {
        self.init(
            id: habit.id,
            name: habit.name,
            frequency: habit.frequency,
            type: habit.type,
            createdAt: habit.createdAt,
            archivedAt: habit.archivedAt,
            color: habit.color,
            icon: habit.icon,
            remindersEnabled: habit.remindersEnabled,
            reminderHour: habit.reminderHour,
            reminderMinute: habit.reminderMinute,
            completions: completions
                .filter { $0.habitID == habit.id }
                .sorted { $0.date < $1.date }
                .map(CompletionBackup.init(completion:)),
            sortOrder: habit.sortOrder,
            goalID: habit.goalID
        )
    }

    /// Project this DTO back to a domain `Habit` (completions excluded;
    /// they travel as their own array via `completionSnapshots`).
    var habitSnapshot: Habit {
        Habit(
            id: id,
            name: name,
            frequency: frequency,
            type: type,
            createdAt: createdAt,
            archivedAt: archivedAt,
            color: color,
            icon: icon,
            remindersEnabled: remindersEnabled,
            reminderHour: reminderHour,
            reminderMinute: reminderMinute,
            sortOrder: sortOrder,
            goalID: goalID
        )
    }

    /// Project the nested completion DTOs back to domain values, each
    /// stamped with this habit's id.
    var completionSnapshots: [Completion] {
        completions.map { $0.completionSnapshot(habitID: id) }
    }
}
