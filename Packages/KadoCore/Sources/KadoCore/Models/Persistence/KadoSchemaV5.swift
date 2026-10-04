import Foundation
import SwiftData

/// Version 5 adds one-off tasks and planned calendar blocks.
/// Habit completion remains separate from planning. V4 stays frozen;
/// the additive migration preserves existing habits and their history.
public enum KadoSchemaV5: VersionedSchema {
    public static let versionIdentifier = Schema.Version(5, 0, 0)

    public static var models: [any PersistentModel.Type] {
        [HabitRecord.self, CompletionRecord.self, TaskRecord.self, ScheduleBlockRecord.self]
    }
}

public extension KadoSchemaV5 {
    /// Completion is represented only by `completedAt`; planned blocks
    /// never own or duplicate task completion state.
    @Model
    public final class TaskRecord {
        public var id: UUID = UUID()
        public var title: String = ""
        public var notes: String = ""
        public var dueDate: Date?
        public var createdAt: Date = Date()
        public var updatedAt: Date = Date()
        public var completedAt: Date?
        public var archivedAt: Date?
        public var externalAccountID: String?
        public var externalCalendarID: String?
        public var externalEventID: String?
        public var externalURL: String?
        public var externalUpdatedAt: Date?
        public var externalCancelledAt: Date?

        @Relationship(deleteRule: .cascade, inverse: \ScheduleBlockRecord.task)
        public var scheduleBlocks: [ScheduleBlockRecord]? = []

        public init(
            id: UUID = UUID(),
            title: String = "",
            notes: String = "",
            dueDate: Date? = nil,
            createdAt: Date = .now,
            updatedAt: Date = .now,
            completedAt: Date? = nil,
            archivedAt: Date? = nil,
            externalAccountID: String? = nil,
            externalCalendarID: String? = nil,
            externalEventID: String? = nil,
            externalURL: String? = nil,
            externalUpdatedAt: Date? = nil,
            externalCancelledAt: Date? = nil,
            scheduleBlocks: [ScheduleBlockRecord]? = []
        ) {
            self.id = id
            self.title = title
            self.notes = notes
            self.dueDate = dueDate
            self.createdAt = createdAt
            self.updatedAt = updatedAt
            self.completedAt = completedAt
            self.archivedAt = archivedAt
            self.externalAccountID = externalAccountID
            self.externalCalendarID = externalCalendarID
            self.externalEventID = externalEventID
            self.externalURL = externalURL
            self.externalUpdatedAt = externalUpdatedAt
            self.externalCancelledAt = externalCancelledAt
            self.scheduleBlocks = scheduleBlocks
        }
    }

    /// A planned occurrence on a civil day. Start and end are
    /// independently optional; absence of both represents an untimed
    /// item. These dates never represent actual tracked time.
    @Model
    public final class ScheduleBlockRecord {
        public var id: UUID = UUID()
        public var plannedDay: Date = Date()
        public var startAt: Date?
        public var endAt: Date?
        public var createdAt: Date = Date()
        public var updatedAt: Date = Date()
        public var task: TaskRecord?
        public var habit: HabitRecord?

        public init(
            id: UUID = UUID(),
            plannedDay: Date = .now,
            startAt: Date? = nil,
            endAt: Date? = nil,
            createdAt: Date = .now,
            updatedAt: Date = .now,
            task: TaskRecord? = nil,
            habit: HabitRecord? = nil
        ) {
            self.id = id
            self.plannedDay = plannedDay
            self.startAt = startAt
            self.endAt = endAt
            self.createdAt = createdAt
            self.updatedAt = updatedAt
            self.task = task
            self.habit = habit
        }
    }

    @Model
    public final class HabitRecord {
        public var id: UUID = UUID()
        public var name: String = ""
        private var frequencyData: Data = Data()
        private var typeData: Data = Data()
        public var createdAt: Date = Date()
        public var archivedAt: Date?
        private var colorRaw: String = "blue"
        public var icon: String = "circle"
        public var remindersEnabled: Bool = false
        public var reminderHour: Int = 9
        public var reminderMinute: Int = 0
        public var sortOrder: Int = 0

        @Relationship(deleteRule: .cascade, inverse: \CompletionRecord.habit)
        public var completions: [CompletionRecord]? = []

        @Relationship(deleteRule: .cascade, inverse: \ScheduleBlockRecord.habit)
        public var scheduleBlocks: [ScheduleBlockRecord]? = []

        public init(
            id: UUID = UUID(),
            name: String = "",
            frequency: Frequency = .daily,
            type: HabitType = .binary,
            createdAt: Date = .now,
            archivedAt: Date? = nil,
            color: HabitColor = HabitColor.blue,
            icon: String = HabitIcon.default,
            remindersEnabled: Bool = false,
            reminderHour: Int = 9,
            reminderMinute: Int = 0,
            sortOrder: Int = 0,
            completions: [CompletionRecord]? = []
        ) {
            self.id = id
            self.name = name
            self.frequencyData = Self.encode(frequency)
            self.typeData = Self.encode(type)
            self.createdAt = createdAt
            self.archivedAt = archivedAt
            self.colorRaw = color.rawValue
            self.icon = icon
            self.remindersEnabled = remindersEnabled
            self.reminderHour = reminderHour
            self.reminderMinute = reminderMinute
            self.sortOrder = sortOrder
            self.completions = completions
        }

        public var frequency: Frequency {
            get { Self.decode(frequencyData, fallback: .daily) }
            set { frequencyData = Self.encode(newValue) }
        }

        public var type: HabitType {
            get { Self.decode(typeData, fallback: .binary) }
            set { typeData = Self.encode(newValue) }
        }

        public var color: HabitColor {
            get { HabitColor(rawValue: colorRaw) ?? .blue }
            set { colorRaw = newValue.rawValue }
        }

        public var snapshot: Habit {
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
                sortOrder: sortOrder
            )
        }

        private static func encode<T: Encodable>(_ value: T) -> Data {
            try! JSONEncoder().encode(value)
        }

        private static func decode<T: Decodable>(_ data: Data, fallback: T) -> T {
            (try? JSONDecoder().decode(T.self, from: data)) ?? fallback
        }
    }

    @Model
    public final class CompletionRecord {
        public var id: UUID = UUID()
        public var date: Date = Date()
        public var value: Double = 1.0
        public var note: String?
        public var habit: HabitRecord?

        public init(
            id: UUID = UUID(),
            date: Date = .now,
            value: Double = 1.0,
            note: String? = nil,
            habit: HabitRecord? = nil
        ) {
            self.id = id
            self.date = date
            self.value = value
            self.note = note
            self.habit = habit
        }

        /// Projects to a value-type `Completion`, or `nil` when the
        /// `habit` inverse isn't set. The relationship is optional
        /// because CloudKit forbids required ones — and during a
        /// CloudKit import the inverse is transiently nil while records
        /// arrive out of order, so callers must tolerate that rather
        /// than force-unwrap (issue #54). Map with `compactMap(\.snapshot)`.
        public var snapshot: Completion? {
            guard let habitID = habit?.id else { return nil }
            return Completion(
                id: id,
                habitID: habitID,
                date: date,
                value: value,
                note: note
            )
        }
    }
}
