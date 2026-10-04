import Foundation
import SwiftData

/// Parses a `BackupDocument` from bytes and merges it into the live
/// SwiftData store by UUID. Records whose IDs are absent from the
/// backup remain in the store.
@MainActor
public protocol BackupImporting: Sendable {
    /// Decode a backup document from JSON bytes. Throws
    /// `BackupError.invalidJSON` on structural failure, or
    /// `BackupError.unsupportedVersion` when the file's `formatVersion`
    /// exceeds what this app knows how to read.
    func parse(data: Data) throws -> BackupDocument

    /// Count how many goals, habits, completions, tasks and blocks would be new
    /// or updated if applied against the current store — without
    /// mutating anything. Backs the confirmation sheet.
    func summary(for document: BackupDocument, in context: ModelContext) throws -> ImportSummary

    /// Apply the document to the store via UUID-keyed upsert. Returns
    /// the actual counts after the merge. Incoming fields overwrite on
    /// conflict.
    @discardableResult
    func apply(_ document: BackupDocument, to context: ModelContext) throws -> ImportSummary
}

/// Production importer.
@MainActor
public struct DefaultBackupImporter: BackupImporting {
    public init() {}

    public func parse(data: Data) throws -> BackupDocument {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let document: BackupDocument
        do {
            document = try decoder.decode(BackupDocument.self, from: data)
        } catch {
            throw BackupError.invalidJSON
        }
        guard (1...BackupDocument.currentFormatVersion).contains(document.formatVersion) else {
            throw BackupError.unsupportedVersion(document.formatVersion)
        }
        return document
    }

    public func summary(for document: BackupDocument, in context: ModelContext) throws -> ImportSummary {
        let existing = try existingHabits(in: context)
        let tasks = try existingTasks(in: context)
        let blocks = try existingBlocks(in: context)
        let goals = try existingGoals(in: context)
        try validate(document, habits: existing, tasks: tasks, goals: goals)
        var summary = ImportSummary()
        let progressEntries = Dictionary(try context.fetch(FetchDescriptor<GoalProgressEntryRecord>()).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for goal in document.goals {
            summary.totalGoals += 1
            if goals[goal.id] == nil {
                summary.newGoals += 1
            } else {
                summary.updatedGoals += 1
            }
        }
        for habitBackup in document.habits {
            summary.totalHabits += 1
            summary.totalCompletions += habitBackup.completions.count

            if let existingHabit = existing[habitBackup.id] {
                summary.updatedHabits += 1
                let existingCompletions = Self.completionsByID(existingHabit)
                for completionBackup in habitBackup.completions {
                    if existingCompletions[completionBackup.id] != nil {
                        summary.updatedCompletions += 1
                    } else {
                        summary.newCompletions += 1
                    }
                }
            } else {
                summary.newHabits += 1
                summary.newCompletions += habitBackup.completions.count
            }
        }
        var taskIDs = Set(tasks.keys)
        for task in document.tasks {
            summary.totalTasks += 1
            if taskIDs.insert(task.id).inserted {
                summary.newTasks += 1
            } else {
                summary.updatedTasks += 1
            }
        }
        var blockIDs = Set(blocks.keys)
        for block in document.scheduleBlocks {
            summary.totalScheduleBlocks += 1
            if blockIDs.insert(block.id).inserted {
                summary.newScheduleBlocks += 1
            } else {
                summary.updatedScheduleBlocks += 1
            }
        }
        if document.formatVersion >= 4 {
            for entry in document.goalProgressEntries {
                summary.totalGoalProgressEntries += 1
                if progressEntries[entry.id] == nil { summary.newGoalProgressEntries += 1 }
                else { summary.updatedGoalProgressEntries += 1 }
            }
        }
        return summary
    }

    @discardableResult
    public func apply(_ document: BackupDocument, to context: ModelContext) throws -> ImportSummary {
        var existing = try existingHabits(in: context)
        var tasks = try existingTasks(in: context)
        var blocks = try existingBlocks(in: context)
        var goals = try existingGoals(in: context)
        try validate(document, habits: existing, tasks: tasks, goals: goals)
        var summary = ImportSummary()
        var progressEntries = Dictionary(try context.fetch(FetchDescriptor<GoalProgressEntryRecord>()).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        // Create goals first so every owner link can resolve in one merge.
        for backup in document.goals {
            summary.totalGoals += 1
            let record: GoalRecord
            if let found = goals[backup.id] {
                record = found
                summary.updatedGoals += 1
            } else {
                record = GoalRecord(id: backup.id)
                context.insert(record)
                goals[backup.id] = record
                summary.newGoals += 1
            }
            Self.overwrite(record, with: backup)
            if document.formatVersion >= 4 { record.measurement = backup.measurement ?? GoalMeasurement() }
        }

        for habitBackup in document.habits {
            summary.totalHabits += 1
            summary.totalCompletions += habitBackup.completions.count

            let record: HabitRecord
            if let existingRecord = existing[habitBackup.id] {
                Self.overwrite(existingRecord, with: habitBackup)
                record = existingRecord
                summary.updatedHabits += 1
            } else {
                let newRecord = HabitRecord(
                    id: habitBackup.id,
                    name: habitBackup.name,
                    frequency: habitBackup.frequency,
                    type: habitBackup.type,
                    createdAt: habitBackup.createdAt,
                    archivedAt: habitBackup.archivedAt,
                    color: habitBackup.color,
                    icon: habitBackup.icon,
                    remindersEnabled: habitBackup.remindersEnabled,
                    reminderHour: habitBackup.reminderHour,
                    reminderMinute: habitBackup.reminderMinute,
                    sortOrder: habitBackup.sortOrder
                )
                context.insert(newRecord)
                existing[habitBackup.id] = newRecord
                record = newRecord
                summary.newHabits += 1
            }

            // Older exports did not contain links. Importing one must
            // not erase a goal assigned since that export was made.
            if document.formatVersion >= 3 {
                record.goal = habitBackup.goalID.flatMap { goals[$0] }
            }

            var existingCompletions = Self.completionsByID(record)
            for completionBackup in habitBackup.completions {
                if let existingCompletion = existingCompletions[completionBackup.id] {
                    existingCompletion.date = completionBackup.date
                    existingCompletion.value = completionBackup.value
                    existingCompletion.note = completionBackup.note
                    summary.updatedCompletions += 1
                } else {
                    let completion = CompletionRecord(
                        id: completionBackup.id,
                        date: completionBackup.date,
                        value: completionBackup.value,
                        note: completionBackup.note,
                        habit: record
                    )
                    context.insert(completion)
                    existingCompletions[completion.id] = completion
                    summary.newCompletions += 1
                }
            }
        }

        for backup in document.tasks {
            summary.totalTasks += 1
            let record: TaskRecord
            if let found = tasks[backup.id] {
                record = found
                summary.updatedTasks += 1
            } else {
                record = TaskRecord(id: backup.id)
                context.insert(record)
                tasks[backup.id] = record
                summary.newTasks += 1
            }
            Self.overwrite(record, with: backup)
            if document.formatVersion >= 3 {
                record.goal = backup.goalID.flatMap { goals[$0] }
            }
        }

        // Resolve relationships after all owners have been upserted.
        for backup in document.scheduleBlocks {
            summary.totalScheduleBlocks += 1
            let record: ScheduleBlockRecord
            if let found = blocks[backup.id] {
                record = found
                summary.updatedScheduleBlocks += 1
            } else {
                record = ScheduleBlockRecord(id: backup.id)
                context.insert(record)
                blocks[backup.id] = record
                summary.newScheduleBlocks += 1
            }
            record.plannedDay = backup.plannedDay
            record.startAt = backup.startAt
            record.endAt = backup.endAt
            record.createdAt = backup.createdAt
            record.updatedAt = backup.updatedAt
            record.task = backup.taskID.flatMap { tasks[$0] }
            record.habit = backup.habitID.flatMap { existing[$0] }
        }

        if document.formatVersion >= 4 {
            for entry in document.goalProgressEntries {
                summary.totalGoalProgressEntries += 1
                let record: GoalProgressEntryRecord
                if let found = progressEntries[entry.id] {
                    record = found; summary.updatedGoalProgressEntries += 1
                } else {
                    record = GoalProgressEntryRecord(id: entry.id, amount: entry.amount)
                    context.insert(record); progressEntries[entry.id] = record
                    summary.newGoalProgressEntries += 1
                }
                record.goal = goals[entry.goalID]; record.date = entry.date; record.amount = entry.amount
                record.note = entry.note; record.createdAt = entry.createdAt; record.updatedAt = entry.updatedAt
            }
        }
        do {
            try context.save()
        } catch {
            // A failed merge must not remain eligible for a later
            // autosave after the UI reports that import failed.
            context.rollback()
            throw error
        }
        return summary
    }

    // MARK: - Helpers

    private func existingHabits(in context: ModelContext) throws -> [UUID: HabitRecord] {
        let records = try context.fetch(FetchDescriptor<HabitRecord>())
        return Dictionary(uniqueKeysWithValues: records.map { ($0.id, $0) })
    }

    private func existingTasks(in context: ModelContext) throws -> [UUID: TaskRecord] {
        let records = try context.fetch(FetchDescriptor<TaskRecord>())
        return Dictionary(records.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    private func existingBlocks(in context: ModelContext) throws -> [UUID: ScheduleBlockRecord] {
        let records = try context.fetch(FetchDescriptor<ScheduleBlockRecord>())
        return Dictionary(records.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    private func existingGoals(in context: ModelContext) throws -> [UUID: GoalRecord] {
        let records = try context.fetch(FetchDescriptor<GoalRecord>())
        return Dictionary(records.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    /// Reject broken references before changing the live store. Nil
    /// relationships remain valid because CloudKit can deliver an
    /// owner after its block; explicit IDs must resolve without loss.
    private func validate(
        _ document: BackupDocument,
        habits: [UUID: HabitRecord],
        tasks: [UUID: TaskRecord],
        goals: [UUID: GoalRecord]
    ) throws {
        guard (1...BackupDocument.currentFormatVersion).contains(document.formatVersion) else {
            throw BackupError.unsupportedVersion(document.formatVersion)
        }
        let habitIDs = Set(habits.keys).union(document.habits.map(\.id))
        let taskIDs = Set(tasks.keys).union(document.tasks.map(\.id))
        let incomingGoalIDs = Set(document.goals.map(\.id))
        guard incomingGoalIDs.count == document.goals.count else { throw BackupError.invalidJSON }
        let goalIDs = Set(goals.keys).union(incomingGoalIDs)
        for goal in document.goals {
            // Codable rejects unknown status raw values before this
            // step. Validate ranges and required metadata before writes.
            guard !goal.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  [goal.createdAt, goal.updatedAt].allSatisfy({ $0.timeIntervalSinceReferenceDate.isFinite }),
                  [goal.startDate, goal.targetDate, goal.completedAt, goal.archivedAt]
                    .compactMap({ $0 }).allSatisfy({ $0.timeIntervalSinceReferenceDate.isFinite }) else {
                throw BackupError.invalidJSON
            }
            if let start = goal.startDate, let target = goal.targetDate, target < start {
                throw BackupError.invalidJSON
            }
        }
        if document.formatVersion >= 4 {
            guard Set(document.goalProgressEntries.map(\.id)).count == document.goalProgressEntries.count else { throw BackupError.invalidJSON }
            for entry in document.goalProgressEntries {
                guard entry.isValid, goalIDs.contains(entry.goalID) else { throw BackupError.invalidJSON }
            }
            for goal in document.goals {
                if let measurement = goal.measurement, !measurement.isValid { throw BackupError.invalidJSON }
            }
        }
        if document.formatVersion >= 3 {
            for habit in document.habits {
                if let goalID = habit.goalID, !goalIDs.contains(goalID) { throw BackupError.invalidJSON }
            }
            for task in document.tasks {
                if let goalID = task.goalID, !goalIDs.contains(goalID) { throw BackupError.invalidJSON }
            }
        }
        for block in document.scheduleBlocks {
            if let taskID = block.taskID, !taskIDs.contains(taskID) { throw BackupError.invalidJSON }
            if let habitID = block.habitID, !habitIDs.contains(habitID) { throw BackupError.invalidJSON }
            if block.taskID != nil && block.habitID != nil { throw BackupError.invalidJSON }
            if let start = block.startAt, let end = block.endAt, end <= start {
                throw BackupError.invalidJSON
            }
        }
    }

    private static func completionsByID(_ record: HabitRecord) -> [UUID: CompletionRecord] {
        Dictionary(uniqueKeysWithValues: (record.completions ?? []).map { ($0.id, $0) })
    }

    private static func overwrite(_ record: HabitRecord, with backup: HabitBackup) {
        record.name = backup.name
        record.frequency = backup.frequency
        record.type = backup.type
        record.createdAt = backup.createdAt
        record.archivedAt = backup.archivedAt
        record.color = backup.color
        record.icon = backup.icon
        record.remindersEnabled = backup.remindersEnabled
        record.reminderHour = backup.reminderHour
        record.reminderMinute = backup.reminderMinute
        record.sortOrder = backup.sortOrder
    }

    private static func overwrite(_ record: TaskRecord, with backup: TaskBackup) {
        record.title = backup.title
        record.notes = backup.notes
        record.dueDate = backup.dueDate
        record.createdAt = backup.createdAt
        record.updatedAt = backup.updatedAt
        record.completedAt = backup.completedAt
        record.archivedAt = backup.archivedAt
        record.externalAccountID = backup.externalAccountID
        record.externalCalendarID = backup.externalCalendarID
        record.externalEventID = backup.externalEventID
        record.externalURL = backup.externalURL
        record.externalUpdatedAt = backup.externalUpdatedAt
        record.externalCancelledAt = backup.externalCancelledAt
    }

    private static func overwrite(_ record: GoalRecord, with backup: GoalBackup) {
        record.name = backup.name
        record.details = backup.details
        record.status = backup.status
        record.startDate = backup.startDate
        record.targetDate = backup.targetDate
        record.createdAt = backup.createdAt
        record.updatedAt = backup.updatedAt
        record.completedAt = backup.completedAt
        record.archivedAt = backup.archivedAt
    }
}
