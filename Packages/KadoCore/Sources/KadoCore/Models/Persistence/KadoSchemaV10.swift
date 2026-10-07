import Foundation
import SwiftData

/// Version 10 adds the monthly reflection: `ReflectionRecord`, one per
/// calendar month, and its `ReflectionAnswerRecord`s. Every other
/// model is the same as in V9. Additive, so V9 stores migrate lightweight.
public enum KadoSchemaV10: VersionedSchema {
    public static let versionIdentifier = Schema.Version(10, 0, 0)

    public static var models: [any PersistentModel.Type] {
        [HabitRecord.self, CompletionRecord.self, TaskRecord.self, ScheduleBlockRecord.self, GoalRecord.self, GoalProgressEntryRecord.self, WorkSessionRecord.self,
         ReflectionRecord.self, ReflectionAnswerRecord.self]
    }
}

public extension KadoSchemaV10 {
    /// A goal groups ongoing habits and one-off tasks. Deleting it
    /// removes their links while preserving those items and history.
    @Model
    public final class GoalRecord {
        public var id: UUID = UUID()
        public var name: String = ""
        public var details: String = ""
        public var statusRaw: String = "active"
        public var startDate: Date?
        public var targetDate: Date?
        public var createdAt: Date = Date()
        public var updatedAt: Date = Date()
        public var completedAt: Date?
        public var archivedAt: Date?
        public var measurementEnabled: Bool = false
        public var progressModeRaw: String = "manual"
        public var progressBaseline: Double = 0
        public var progressTarget: Double = 1
        public var progressUnit: String = ""
        public var progressHabitID: UUID?
        /// Raw `ItemCategory` value. Empty means "not set".
        public var categoryRaw: String = ""

        @Relationship(deleteRule: .cascade, inverse: \GoalProgressEntryRecord.goal)
        public var progressEntries: [GoalProgressEntryRecord]? = []

        public var measurement: GoalMeasurement {
            get { GoalMeasurement(enabled: measurementEnabled, mode: GoalProgressMode(rawValue: progressModeRaw) ?? .manual, baseline: progressBaseline, target: progressTarget, unit: progressUnit, habitID: progressHabitID) }
            set {
                measurementEnabled = newValue.enabled; progressModeRaw = newValue.mode.rawValue
                progressBaseline = newValue.baseline; progressTarget = newValue.target
                progressUnit = newValue.unit; progressHabitID = newValue.habitID
            }
        }

        @Relationship(deleteRule: .nullify, inverse: \TaskRecord.goal)
        public var tasks: [TaskRecord]? = []

        @Relationship(deleteRule: .nullify, inverse: \HabitRecord.goal)
        public var habits: [HabitRecord]? = []

        public init(
            id: UUID = UUID(),
            name: String = "",
            details: String = "",
            status: GoalStatus = .active,
            startDate: Date? = nil,
            targetDate: Date? = nil,
            createdAt: Date = .now,
            updatedAt: Date = .now,
            completedAt: Date? = nil,
            archivedAt: Date? = nil,
            tasks: [TaskRecord]? = [],
            habits: [HabitRecord]? = [],
            category: ItemCategory? = nil
        ) {
            self.id = id
            self.name = name
            self.details = details
            self.statusRaw = status.rawValue
            self.startDate = startDate
            self.targetDate = targetDate
            self.createdAt = createdAt
            self.updatedAt = updatedAt
            self.completedAt = completedAt
            self.archivedAt = archivedAt
            self.tasks = tasks
            self.habits = habits
            self.categoryRaw = category?.rawValue ?? ""
        }

        public var status: GoalStatus {
            get { GoalStatus(rawValue: statusRaw) ?? .active }
            set { statusRaw = newValue.rawValue }
        }

        /// The stored category, or `nil` when none is set. Readers that
        /// need a value use `CategoryResolver`.
        public var category: ItemCategory? {
            get { ItemCategory(storedRaw: categoryRaw) }
            set { categoryRaw = newValue?.rawValue ?? "" }
        }
    }

    @Model
    public final class GoalProgressEntryRecord {
        public var id: UUID = UUID()
        public var date: Date = Date()
        public var amount: Double = 1
        public var note: String?
        public var createdAt: Date = Date()
        public var updatedAt: Date = Date()
        public var goal: GoalRecord?

        public init(id: UUID = UUID(), date: Date = .now, amount: Double, note: String? = nil, createdAt: Date = .now, updatedAt: Date = .now, goal: GoalRecord? = nil) {
            self.id = id; self.date = date; self.amount = amount; self.note = note
            self.createdAt = createdAt; self.updatedAt = updatedAt; self.goal = goal
        }
        public var snapshot: GoalProgressEntry? {
            guard let goal else { return nil }
            return GoalProgressEntry(id: id, goalID: goal.id, date: date, amount: amount, note: note, createdAt: createdAt, updatedAt: updatedAt)
        }
    }

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
        public var goal: GoalRecord?
        public var externalAccountID: String?
        public var externalCalendarID: String?
        public var externalEventID: String?
        public var externalURL: String?
        public var externalUpdatedAt: Date?
        public var externalCancelledAt: Date?
        /// Raw `ItemCategory` value. Empty means "not set".
        public var categoryRaw: String = ""

        @Relationship(deleteRule: .cascade, inverse: \ScheduleBlockRecord.task)
        public var scheduleBlocks: [ScheduleBlockRecord]? = []

        @Relationship(deleteRule: .cascade, inverse: \WorkSessionRecord.task)
        public var workSessions: [WorkSessionRecord]? = []

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
            scheduleBlocks: [ScheduleBlockRecord]? = [],
            goal: GoalRecord? = nil,
            category: ItemCategory? = nil
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
            self.goal = goal
            self.categoryRaw = category?.rawValue ?? ""
        }

        /// The stored category, or `nil` when none is set. Readers that
        /// need a value use `CategoryResolver`.
        public var category: ItemCategory? {
            get { ItemCategory(storedRaw: categoryRaw) }
            set { categoryRaw = newValue?.rawValue ?? "" }
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

        /// Sessions started from this block. Deleting the block keeps
        /// the tracked time; the session just loses its plan link.
        @Relationship(deleteRule: .nullify, inverse: \WorkSessionRecord.scheduleBlock)
        public var workSessions: [WorkSessionRecord]? = []

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
        public var goal: GoalRecord?
        /// Raw `ItemCategory` value. Empty means "not set".
        public var categoryRaw: String = ""

        @Relationship(deleteRule: .cascade, inverse: \CompletionRecord.habit)
        public var completions: [CompletionRecord]? = []

        @Relationship(deleteRule: .cascade, inverse: \ScheduleBlockRecord.habit)
        public var scheduleBlocks: [ScheduleBlockRecord]? = []

        @Relationship(deleteRule: .cascade, inverse: \WorkSessionRecord.habit)
        public var workSessions: [WorkSessionRecord]? = []

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
            completions: [CompletionRecord]? = [],
            goal: GoalRecord? = nil,
            category: ItemCategory? = nil
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
            self.goal = goal
            self.categoryRaw = category?.rawValue ?? ""
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

        /// The stored category, or `nil` when none is set. Readers that
        /// need a value use `CategoryResolver`.
        public var category: ItemCategory? {
            get { ItemCategory(storedRaw: categoryRaw) }
            set { categoryRaw = newValue?.rawValue ?? "" }
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
                sortOrder: sortOrder,
                goalID: goal?.id,
                category: category
            )
        }

        private static func encode<T: Encodable>(_ value: T) -> Data {
            try! JSONEncoder().encode(value)
        }

        /// Shared rather than built per read: every `snapshot` reads
        /// `frequency` and `type`, and Today snapshots each habit on
        /// every pass. `decode` keeps no state between calls, so one
        /// instance serves every caller.
        private static let decoder = JSONDecoder()

        private static func decode<T: Decodable>(_ data: Data, fallback: T) -> T {
            (try? decoder.decode(T.self, from: data)) ?? fallback
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

    /// Real time spent on a task or habit. Open while `endedAt` is
    /// nil; paused while `pausedAt` is set. `pausedSeconds` holds the
    /// total of finished pauses only.
    @Model
    public final class WorkSessionRecord {
        public var id: UUID = UUID()
        public var startedAt: Date = Date()
        public var endedAt: Date?
        public var pausedAt: Date?
        public var pausedSeconds: Double = 0
        public var createdAt: Date = Date()
        public var updatedAt: Date = Date()
        public var task: TaskRecord?
        public var habit: HabitRecord?
        public var scheduleBlock: ScheduleBlockRecord?

        public init(
            id: UUID = UUID(),
            startedAt: Date = .now,
            endedAt: Date? = nil,
            pausedAt: Date? = nil,
            pausedSeconds: Double = 0,
            createdAt: Date = .now,
            updatedAt: Date = .now,
            task: TaskRecord? = nil,
            habit: HabitRecord? = nil,
            scheduleBlock: ScheduleBlockRecord? = nil
        ) {
            self.id = id
            self.startedAt = startedAt
            self.endedAt = endedAt
            self.pausedAt = pausedAt
            self.pausedSeconds = pausedSeconds
            self.createdAt = createdAt
            self.updatedAt = updatedAt
            self.task = task
            self.habit = habit
            self.scheduleBlock = scheduleBlock
        }

        /// The value-type view of this record, for display and math.
        public var snapshot: WorkSession {
            WorkSession(startedAt: startedAt, endedAt: endedAt, pausedAt: pausedAt, pausedSeconds: pausedSeconds)
        }
    }
}

public extension KadoSchemaV10 {
    /// What the user wrote about one calendar month. `year` and `month`
    /// name it as numbers rather than as an instant, so the entry for
    /// October stays October in every time zone.
    @Model
    public final class ReflectionRecord {
        public var id: UUID = UUID()
        public var year: Int = 0
        /// 1 to 12.
        public var month: Int = 0
        public var createdAt: Date = Date()
        public var updatedAt: Date = Date()
        /// Set when the user finishes the check-in. An entry without it
        /// is a draft the user can continue.
        public var completedAt: Date?

        @Relationship(deleteRule: .cascade, inverse: \ReflectionAnswerRecord.reflection)
        public var answers: [ReflectionAnswerRecord]? = []

        public init(
            id: UUID = UUID(),
            year: Int,
            month: Int,
            createdAt: Date = .now,
            updatedAt: Date = .now,
            completedAt: Date? = nil
        ) {
            self.id = id
            self.year = year
            self.month = month
            self.createdAt = createdAt
            self.updatedAt = updatedAt
            self.completedAt = completedAt
        }
    }

    /// One answer in a monthly reflection. `questionID` is the stable
    /// key the question catalog uses; `prompt` keeps the words as asked,
    /// so a reworded or retired question still reads back as it was.
    @Model
    public final class ReflectionAnswerRecord {
        public var id: UUID = UUID()
        public var questionID: String = ""
        public var prompt: String = ""
        public var text: String = ""
        /// 1 to 10 for a rating question; nil otherwise.
        public var rating: Double?
        /// A follow-up's choice (a `ReflectionFollowUpStatus` raw
        /// value), empty when there is none.
        public var statusRaw: String = ""
        public var createdAt: Date = Date()
        public var updatedAt: Date = Date()
        public var reflection: ReflectionRecord?

        public init(
            id: UUID = UUID(),
            questionID: String,
            prompt: String = "",
            text: String = "",
            rating: Double? = nil,
            statusRaw: String = "",
            createdAt: Date = .now,
            updatedAt: Date = .now,
            reflection: ReflectionRecord? = nil
        ) {
            self.id = id
            self.questionID = questionID
            self.prompt = prompt
            self.text = text
            self.rating = rating
            self.statusRaw = statusRaw
            self.createdAt = createdAt
            self.updatedAt = updatedAt
            self.reflection = reflection
        }
    }
}

public typealias HabitRecord = KadoSchemaV10.HabitRecord
public typealias CompletionRecord = KadoSchemaV10.CompletionRecord
public typealias TaskRecord = KadoSchemaV10.TaskRecord
public typealias ScheduleBlockRecord = KadoSchemaV10.ScheduleBlockRecord
public typealias GoalRecord = KadoSchemaV10.GoalRecord
public typealias GoalProgressEntryRecord = KadoSchemaV10.GoalProgressEntryRecord
public typealias WorkSessionRecord = KadoSchemaV10.WorkSessionRecord
public typealias ReflectionRecord = KadoSchemaV10.ReflectionRecord
public typealias ReflectionAnswerRecord = KadoSchemaV10.ReflectionAnswerRecord
