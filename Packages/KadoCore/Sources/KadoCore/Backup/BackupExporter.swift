import Foundation
import SwiftData

/// Turns the live SwiftData store into a `BackupDocument` ready to
/// serialize as JSON. Protocol-defined so views can inject a mock in
/// previews.
@MainActor
public protocol BackupExporting: Sendable {
    /// Fetch the full goal, habit, task and schedule graph, including
    /// archived records, and wrap it in a `BackupDocument`.
    func export(from context: ModelContext) throws -> BackupDocument

    /// Convenience: encode the document to JSON bytes with the backup's
    /// canonical encoding (ISO8601 dates, sorted keys, pretty-printed).
    func encode(_ document: BackupDocument) throws -> Data
}

public extension BackupExporting {
    /// Default composite: build the document from the store and encode
    /// it in one step.
    func exportData(from context: ModelContext) throws -> Data {
        try encode(try export(from: context))
    }
}

/// Production exporter. Reads every `HabitRecord`, sorted by
/// `createdAt` for a stable on-disk order.
@MainActor
public struct DefaultBackupExporter: BackupExporting {
    private let now: @Sendable () -> Date
    private let appVersion: String

    public init(
        now: @escaping @Sendable () -> Date = { Date() },
        appVersion: String = DefaultBackupExporter.bundleVersion()
    ) {
        self.now = now
        self.appVersion = appVersion
    }

    public func export(from context: ModelContext) throws -> BackupDocument {
        let descriptor = FetchDescriptor<HabitRecord>(
            sortBy: [SortDescriptor(\.createdAt, order: .forward)]
        )
        let records = try context.fetch(descriptor)
        let habits = records.map(Self.backup(from:))
        let tasks = try context.fetch(FetchDescriptor<TaskRecord>(
            sortBy: [SortDescriptor(\.createdAt, order: .forward), SortDescriptor(\.title, order: .forward)]
        )).map(Self.backup(from:))
        let blocks = try context.fetch(FetchDescriptor<ScheduleBlockRecord>(
            sortBy: [SortDescriptor(\.plannedDay, order: .forward), SortDescriptor(\.createdAt, order: .forward)]
        )).map(Self.backup(from:))
        let goals = try context.fetch(FetchDescriptor<GoalRecord>(
            sortBy: [SortDescriptor(\.createdAt, order: .forward), SortDescriptor(\.name, order: .forward)]
        )).map(Self.backup(from:))
        return BackupDocument(
            exportedAt: now(),
            appVersion: appVersion,
            habits: habits,
            tasks: tasks,
            scheduleBlocks: blocks,
            goals: goals,
            goalProgressEntries: try context.fetch(FetchDescriptor<GoalProgressEntryRecord>(sortBy: [SortDescriptor(\.date)])).compactMap(\.snapshot)
        )
    }

    public func encode(_ document: BackupDocument) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(document)
    }

    /// Reads `CFBundleShortVersionString` from the main bundle with a
    /// safe fallback — previews and tests run with no version stamped.
    /// `nonisolated` so it's usable as a default-argument expression
    /// from any actor context.
    public nonisolated static func bundleVersion() -> String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "unknown"
    }

    private static func backup(from record: HabitRecord) -> HabitBackup {
        let habit = record.snapshot
        let completions = (record.completions ?? [])
            .sorted { $0.date < $1.date }
            .map { record in
                CompletionBackup(
                    id: record.id,
                    date: record.date,
                    value: record.value,
                    note: record.note
                )
            }
        return HabitBackup(
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
            completions: completions,
            sortOrder: habit.sortOrder,
            goalID: record.goal?.id
        )
    }

    private static func backup(from record: TaskRecord) -> TaskBackup {
        TaskBackup(
            id: record.id, title: record.title, notes: record.notes, dueDate: record.dueDate,
            createdAt: record.createdAt, updatedAt: record.updatedAt,
            completedAt: record.completedAt, archivedAt: record.archivedAt,
            externalAccountID: record.externalAccountID, externalCalendarID: record.externalCalendarID,
            externalEventID: record.externalEventID, externalURL: record.externalURL,
            externalUpdatedAt: record.externalUpdatedAt, externalCancelledAt: record.externalCancelledAt,
            goalID: record.goal?.id
        )
    }

    private static func backup(from record: ScheduleBlockRecord) -> ScheduleBlockBackup {
        ScheduleBlockBackup(
            id: record.id, plannedDay: record.plannedDay,
            startAt: record.startAt, endAt: record.endAt,
            createdAt: record.createdAt, updatedAt: record.updatedAt,
            taskID: record.task?.id, habitID: record.habit?.id
        )
    }

    private static func backup(from record: GoalRecord) -> GoalBackup {
        GoalBackup(
            id: record.id, name: record.name, details: record.details, status: record.status,
            startDate: record.startDate, targetDate: record.targetDate,
            createdAt: record.createdAt, updatedAt: record.updatedAt,
            completedAt: record.completedAt, archivedAt: record.archivedAt, measurement: record.measurement
        )
    }
}
