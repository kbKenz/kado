import Foundation

/// Serializes a `BackupDocument` as consolidated CSV, and reads one
/// back.
///
/// The shape is one row per completion, with the owning habit's
/// metadata denormalized onto every row. A habit with no completions
/// still emits a single row with the four completion columns empty, so
/// it survives the round-trip.
///
/// **What "lossless" covers here**: goals, habits, completions, tasks, planned blocks, work sessions
/// and the categories of habits, tasks and goals. The
/// envelope fields `exportedAt` and `appVersion` are provenance rather
/// than user data and are not carried — a decoded document stamps
/// `exportedAt` from the injected clock and leaves `appVersion` empty.
///
/// Timestamps use the same ISO8601 seconds precision as the JSON
/// encoder's `.iso8601` strategy, so sub-second components are dropped
/// by both formats identically. Completion *days* — all the score and
/// streak logic depends on — are unaffected.
nonisolated public struct CSVBackupCoder: Sendable {
    /// The column contract. Order is part of the format: `decode`
    /// requires an exact match, which doubles as the "is this even a
    /// Kadō CSV" check.
    public static let legacyColumns = [
        "format_version",
        "habit_id",
        "habit_name",
        "frequency",
        "type",
        "created_at",
        "archived_at",
        "color",
        "icon",
        "reminders_enabled",
        "reminder_hour",
        "reminder_minute",
        "completion_id",
        "completion_date",
        "value",
        "note"
    ]

    /// Format 2 preserves the original habit columns and adds explicit
    /// entity rows. Empty irrelevant cells stay easy to inspect in a
    /// spreadsheet; IDs restore the graph when the file is imported.
    public static let planningColumns = legacyColumns + [
        "entity_type", "task_id", "task_title", "task_notes", "due_date",
        "updated_at", "completed_at", "external_account_id", "external_calendar_id",
        "external_event_id", "external_url", "external_updated_at", "external_cancelled_at",
        "schedule_block_id", "planned_day", "start_at", "end_at",
        "linked_task_id", "linked_habit_id", "habit_sort_order"
    ]

    /// Format 3 appends goal metadata and owner links without changing
    /// any position in the 36-column planning format. Goal rows reuse
    /// the shared lifecycle timestamp columns.
    public static let goalColumns = planningColumns + [
        "goal_id", "goal_name", "goal_details", "goal_status",
        "goal_start_date", "goal_target_date", "linked_goal_id"
    ]

    /// Format 4 appends goal measurement and progress-entry columns.
    public static let progressColumns = goalColumns + [
        "measurement_enabled", "progress_mode", "progress_baseline", "progress_target", "progress_unit", "progress_habit_id",
        "progress_entry_id", "progress_date", "progress_amount", "progress_note"
    ]

    /// Format 5 appends work-session columns. Session rows reuse
    /// `created_at`, `updated_at`, `linked_task_id` and `linked_habit_id`.
    public static let sessionColumns = progressColumns + [
        "work_session_id", "started_at", "ended_at", "paused_at", "paused_seconds", "linked_schedule_block_id"
    ]

    /// Format 6 appends the category of habit, task and goal rows (the
    /// raw `ItemCategory` value, empty when not set). This is the header
    /// the encoder writes.
    public static let columns = sessionColumns + ["category"]

    private let now: @Sendable () -> Date

    public init(now: @escaping @Sendable () -> Date = { Date() }) {
        self.now = now
    }

    // MARK: - Encoding

    public func encode(_ document: BackupDocument) -> Data {
        // Writing the current header migrates older in-memory DTOs to
        // the current format. Every row must declare that same version.
        let formatVersion = String(BackupDocument.currentFormatVersion)
        var rows: [[String]] = [Self.columns]

        for goal in document.goals {
            rows.append(Self.row([
                "format_version": formatVersion, "entity_type": "goal",
                "goal_id": goal.id.uuidString, "goal_name": goal.name,
                "goal_details": goal.details, "goal_status": goal.status.rawValue,
                "goal_start_date": goal.startDate.map(Self.encode(date:)) ?? "",
                "goal_target_date": goal.targetDate.map(Self.encode(date:)) ?? "",
                "created_at": Self.encode(date: goal.createdAt), "updated_at": Self.encode(date: goal.updatedAt),
                "completed_at": goal.completedAt.map(Self.encode(date:)) ?? "",
                "archived_at": goal.archivedAt.map(Self.encode(date:)) ?? "",
                "measurement_enabled": String((goal.measurement ?? GoalMeasurement()).enabled),
                "progress_mode": (goal.measurement ?? GoalMeasurement()).mode.rawValue,
                "progress_baseline": String((goal.measurement ?? GoalMeasurement()).baseline),
                "progress_target": String((goal.measurement ?? GoalMeasurement()).target),
                "progress_unit": (goal.measurement ?? GoalMeasurement()).unit,
                "progress_habit_id": goal.measurement?.habitID?.uuidString ?? "",
                "category": goal.category
            ]))
        }

        for entry in document.goalProgressEntries {
            rows.append(Self.row([
                "format_version": formatVersion, "entity_type": "goal_progress",
                "progress_entry_id": entry.id.uuidString, "linked_goal_id": entry.goalID.uuidString,
                "progress_date": Self.encode(date: entry.date), "progress_amount": String(entry.amount), "progress_note": entry.note ?? "",
                "created_at": Self.encode(date: entry.createdAt), "updated_at": Self.encode(date: entry.updatedAt)
            ]))
        }
        for habit in document.habits {
            let metadata = [
                formatVersion,
                habit.id.uuidString,
                habit.name,
                Self.encode(frequency: habit.frequency),
                Self.encode(type: habit.type),
                Self.encode(date: habit.createdAt),
                habit.archivedAt.map(Self.encode(date:)) ?? "",
                habit.color.rawValue,
                habit.icon,
                String(habit.remindersEnabled),
                String(habit.reminderHour),
                String(habit.reminderMinute)
            ]

            if habit.completions.isEmpty {
                rows.append(Self.habitRow(metadata + ["", "", "", ""], of: habit))
            } else {
                for completion in habit.completions {
                    rows.append(Self.habitRow(metadata + [
                        completion.id.uuidString,
                        Self.encode(date: completion.date),
                        String(completion.value),
                        completion.note ?? ""
                    ], of: habit))
                }
            }
        }

        for task in document.tasks {
            rows.append(Self.row([
                "format_version": formatVersion, "entity_type": "task",
                "task_id": task.id.uuidString, "task_title": task.title, "task_notes": task.notes,
                "due_date": task.dueDate.map(Self.encode(date:)) ?? "",
                "created_at": Self.encode(date: task.createdAt), "updated_at": Self.encode(date: task.updatedAt),
                "completed_at": task.completedAt.map(Self.encode(date:)) ?? "",
                "archived_at": task.archivedAt.map(Self.encode(date:)) ?? "",
                "external_account_id": task.externalAccountID ?? "", "external_calendar_id": task.externalCalendarID ?? "",
                "external_event_id": task.externalEventID ?? "", "external_url": task.externalURL ?? "",
                "external_updated_at": task.externalUpdatedAt.map(Self.encode(date:)) ?? "",
                "external_cancelled_at": task.externalCancelledAt.map(Self.encode(date:)) ?? "",
                "linked_goal_id": task.goalID?.uuidString ?? "",
                "category": task.category
            ]))
        }
        for block in document.scheduleBlocks {
            rows.append(Self.row([
                "format_version": formatVersion, "entity_type": "schedule_block",
                "schedule_block_id": block.id.uuidString, "planned_day": Self.encode(date: block.plannedDay),
                "start_at": block.startAt.map(Self.encode(date:)) ?? "", "end_at": block.endAt.map(Self.encode(date:)) ?? "",
                "created_at": Self.encode(date: block.createdAt), "updated_at": Self.encode(date: block.updatedAt),
                "linked_task_id": block.taskID?.uuidString ?? "", "linked_habit_id": block.habitID?.uuidString ?? ""
            ]))
        }
        for session in document.workSessions {
            rows.append(Self.row([
                "format_version": formatVersion, "entity_type": "work_session",
                "work_session_id": session.id.uuidString,
                "started_at": Self.encode(date: session.startedAt),
                "ended_at": session.endedAt.map(Self.encode(date:)) ?? "",
                "paused_at": session.pausedAt.map(Self.encode(date:)) ?? "",
                "paused_seconds": String(session.pausedSeconds),
                "created_at": Self.encode(date: session.createdAt), "updated_at": Self.encode(date: session.updatedAt),
                "linked_task_id": session.taskID?.uuidString ?? "", "linked_habit_id": session.habitID?.uuidString ?? "",
                "linked_schedule_block_id": session.scheduleBlockID?.uuidString ?? ""
            ]))
        }
        return Data(CSVWriter.write(rows).utf8)
    }

    // MARK: - Decoding

    public func decode(_ data: Data) throws -> BackupDocument {
        guard let text = String(data: data, encoding: .utf8) else {
            throw BackupError.invalidCSV
        }

        let rows: [[String]]
        do {
            rows = try CSVReader.parse(text)
        } catch {
            // CSVParseError is an implementation detail of the RFC 4180
            // layer; the UI only knows BackupError.
            throw BackupError.invalidCSV
        }

        // Each header the app ever wrote, oldest first. Its position is
        // the format version it represents.
        let headers = [
            Self.legacyColumns, Self.planningColumns, Self.goalColumns,
            Self.progressColumns, Self.sessionColumns, Self.columns
        ]
        guard let header = rows.first, let headerIndex = headers.firstIndex(of: header) else {
            throw BackupError.invalidCSV
        }

        let isLegacy = header == Self.legacyColumns
        let headerVersion = headerIndex + 1
        var goals: [GoalBackup] = []
        var entries: [GoalProgressEntry] = []
        var seenEntryIDs = Set<UUID>()
        var tasks: [TaskBackup] = []
        var blocks: [ScheduleBlockBackup] = []
        var seenTaskIDs: Set<UUID> = []
        var seenBlockIDs: Set<UUID> = []
        var sessions: [WorkSessionBackup] = []
        var seenSessionIDs: Set<UUID> = []
        var seenGoalIDs: Set<UUID> = []
        var order: [UUID] = []
        var habits: [UUID: HabitBackup] = [:]
        var seenCompletionIDs: Set<UUID> = []
        var formatVersion = headerVersion
        var declaredVersion: Int?

        for (offset, row) in rows.dropFirst().enumerated() {
            // Header occupies line 1, so the first data row is line 2.
            // Assumes no blank lines, which the reader skips silently.
            let line = offset + 2

            guard row.count == header.count else {
                throw BackupError.malformedRow(line: line)
            }

            guard let version = Int(row[0]) else { throw BackupError.invalidCSV }
            guard (1...BackupDocument.currentFormatVersion).contains(version) else {
                throw BackupError.unsupportedVersion(version)
            }
            // A header cannot represent a newer format. Mixed row
            // versions would make optional-link merge rules ambiguous.
            guard version <= headerVersion,
                  declaredVersion == nil || declaredVersion == version else { throw BackupError.invalidCSV }
            declaredVersion = version
            formatVersion = version

            func field(_ name: String) -> String {
                guard let index = header.firstIndex(of: name) else { return "" }
                return row[index]
            }
            if !isLegacy {
                switch field("entity_type") {
                case "goal_progress":
                    guard version >= 4, let id = UUID(uuidString: field("progress_entry_id")),
                          let goalID = UUID(uuidString: field("linked_goal_id")), let amount = Double(field("progress_amount")), amount.isFinite, amount > 0 else { throw BackupError.invalidCSV }
                    guard seenEntryIDs.insert(id).inserted else { continue }
                    entries.append(GoalProgressEntry(id: id, goalID: goalID, date: try Self.decodeDate(field("progress_date")), amount: amount, note: Self.optionalString(field("progress_note")), createdAt: try Self.decodeDate(field("created_at")), updatedAt: try Self.decodeDate(field("updated_at"))))
                    continue
                case "goal":
                    guard version >= 3,
                          let id = UUID(uuidString: field("goal_id")),
                          let status = GoalStatus(rawValue: field("goal_status")) else { throw BackupError.invalidCSV }
                    guard seenGoalIDs.insert(id).inserted else { continue }
                    var measurement: GoalMeasurement?
                    if version >= 4 {
                        guard let mode = GoalProgressMode(rawValue: field("progress_mode")),
                              let baseline = Double(field("progress_baseline")), let target = Double(field("progress_target")) else { throw BackupError.invalidCSV }
                        measurement = GoalMeasurement(enabled: try Self.decodeBool(field("measurement_enabled")), mode: mode, baseline: baseline, target: target, unit: field("progress_unit"), habitID: try Self.decodeOptionalUUID(field("progress_habit_id")))
                        guard measurement!.isValid else { throw BackupError.invalidCSV }
                    }
                    goals.append(GoalBackup(
                        id: id, name: field("goal_name"), details: field("goal_details"), status: status,
                        startDate: try Self.decodeOptionalDate(field("goal_start_date")),
                        targetDate: try Self.decodeOptionalDate(field("goal_target_date")),
                        createdAt: try Self.decodeDate(field("created_at")), updatedAt: try Self.decodeDate(field("updated_at")),
                        completedAt: try Self.decodeOptionalDate(field("completed_at")), archivedAt: try Self.decodeOptionalDate(field("archived_at")), measurement: measurement,
                        category: version >= 6 ? field("category") : ""
                    ))
                    continue
                case "task":
                    guard let id = UUID(uuidString: field("task_id")) else { throw BackupError.invalidCSV }
                    guard seenTaskIDs.insert(id).inserted else { continue }
                    tasks.append(TaskBackup(
                        id: id, title: field("task_title"), notes: field("task_notes"),
                        dueDate: try Self.decodeOptionalDate(field("due_date")),
                        createdAt: try Self.decodeDate(field("created_at")), updatedAt: try Self.decodeDate(field("updated_at")),
                        completedAt: try Self.decodeOptionalDate(field("completed_at")), archivedAt: try Self.decodeOptionalDate(field("archived_at")),
                        externalAccountID: Self.optionalString(field("external_account_id")),
                        externalCalendarID: Self.optionalString(field("external_calendar_id")),
                        externalEventID: Self.optionalString(field("external_event_id")),
                        externalURL: Self.optionalString(field("external_url")),
                        externalUpdatedAt: try Self.decodeOptionalDate(field("external_updated_at")),
                        externalCancelledAt: try Self.decodeOptionalDate(field("external_cancelled_at")),
                        goalID: version >= 3 ? try Self.decodeOptionalUUID(field("linked_goal_id")) : nil,
                        category: version >= 6 ? field("category") : ""
                    ))
                    continue
                case "schedule_block":
                    guard let id = UUID(uuidString: field("schedule_block_id")) else { throw BackupError.invalidCSV }
                    guard seenBlockIDs.insert(id).inserted else { continue }
                    blocks.append(ScheduleBlockBackup(
                        id: id, plannedDay: try Self.decodeDate(field("planned_day")),
                        startAt: try Self.decodeOptionalDate(field("start_at")), endAt: try Self.decodeOptionalDate(field("end_at")),
                        createdAt: try Self.decodeDate(field("created_at")), updatedAt: try Self.decodeDate(field("updated_at")),
                        taskID: try Self.decodeOptionalUUID(field("linked_task_id")), habitID: try Self.decodeOptionalUUID(field("linked_habit_id"))
                    ))
                    continue
                case "work_session":
                    guard version >= 5, let id = UUID(uuidString: field("work_session_id")) else { throw BackupError.invalidCSV }
                    guard seenSessionIDs.insert(id).inserted else { continue }
                    guard let paused = Double(field("paused_seconds")), paused.isFinite else { throw BackupError.invalidCSV }
                    sessions.append(WorkSessionBackup(
                        id: id, startedAt: try Self.decodeDate(field("started_at")),
                        endedAt: try Self.decodeOptionalDate(field("ended_at")),
                        pausedAt: try Self.decodeOptionalDate(field("paused_at")), pausedSeconds: paused,
                        createdAt: try Self.decodeDate(field("created_at")), updatedAt: try Self.decodeDate(field("updated_at")),
                        taskID: try Self.decodeOptionalUUID(field("linked_task_id")),
                        habitID: try Self.decodeOptionalUUID(field("linked_habit_id")),
                        scheduleBlockID: try Self.decodeOptionalUUID(field("linked_schedule_block_id"))
                    ))
                    continue
                case "habit":
                    break
                default:
                    throw BackupError.invalidCSV
                }
            }

            guard let habitID = UUID(uuidString: row[1]) else {
                throw BackupError.invalidCSV
            }

            // First row for a habit id wins. Later rows contribute only
            // their completion, so a hand-edited file with inconsistent
            // metadata resolves deterministically instead of by
            // whichever row happened to land last.
            if habits[habitID] == nil {
                habits[habitID] = HabitBackup(
                    id: habitID,
                    name: row[2],
                    frequency: try Self.decodeFrequency(row[3]),
                    type: try Self.decodeType(row[4]),
                    createdAt: try Self.decodeDate(row[5]),
                    archivedAt: try Self.decodeOptionalDate(row[6]),
                    color: try Self.decodeColor(row[7]),
                    icon: row[8],
                    remindersEnabled: try Self.decodeBool(row[9]),
                    reminderHour: try Self.decodeInt(row[10]),
                    reminderMinute: try Self.decodeInt(row[11]),
                    completions: [],
                    sortOrder: isLegacy ? 0 : try Self.decodeInt(field("habit_sort_order")),
                    goalID: version >= 3 ? try Self.decodeOptionalUUID(field("linked_goal_id")) : nil,
                    category: version >= 6 ? field("category") : ""
                )
                order.append(habitID)
            }

            // An empty completion id marks a metadata-only row, which is
            // how a habit with no completions survives.
            guard !row[12].isEmpty else { continue }
            guard let completionID = UUID(uuidString: row[12]) else {
                throw BackupError.invalidCSV
            }

            // First row for a completion id wins, matching the habit
            // metadata rule above. Duplicates are reachable by
            // copy-pasting a row in a spreadsheet, and letting both
            // through would insert two CompletionRecords sharing a
            // UUID: CloudKit forbids `@Attribute(.unique)`, and
            // `DefaultBackupImporter.apply` snapshots the existing
            // completions once before its loop, so neither insert sees
            // the other.
            guard seenCompletionIDs.insert(completionID).inserted else { continue }

            guard let value = Double(row[14]) else { throw BackupError.invalidCSV }

            habits[habitID]?.completions.append(
                CompletionBackup(
                    id: completionID,
                    date: try Self.decodeDate(row[13]),
                    value: value,
                    note: row[15].isEmpty ? nil : row[15]
                )
            )
        }

        return BackupDocument(
            formatVersion: formatVersion,
            exportedAt: now(),
            appVersion: "",
            habits: order.compactMap { habits[$0] },
            tasks: tasks,
            scheduleBlocks: blocks,
            goals: goals, goalProgressEntries: entries,
            workSessions: sessions
        )
    }

    private static func row(_ fields: [String: String]) -> [String] {
        columns.map { fields[$0] ?? "" }
    }

    /// One habit row. Every row of a habit repeats its metadata, the
    /// category included, so any row can rebuild the habit.
    private static func habitRow(_ legacy: [String], of habit: HabitBackup) -> [String] {
        var fields = Dictionary(uniqueKeysWithValues: zip(legacyColumns, legacy))
        fields["entity_type"] = "habit"
        fields["habit_sort_order"] = String(habit.sortOrder)
        fields["linked_goal_id"] = habit.goalID?.uuidString ?? ""
        fields["category"] = habit.category
        return row(fields)
    }

    private static func optionalString(_ field: String) -> String? {
        field.isEmpty ? nil : field
    }

    private static func decodeOptionalUUID(_ field: String) throws -> UUID? {
        guard !field.isEmpty else { return nil }
        guard let id = UUID(uuidString: field) else { throw BackupError.invalidCSV }
        return id
    }

    // MARK: - Field encoding

    static func encode(date: Date) -> String {
        date.formatted(.iso8601)
    }

    static func encode(frequency: Frequency) -> String {
        switch frequency {
        case .daily:
            return "daily"
        case .daysPerWeek(let count):
            return "days_per_week:\(count)"
        case .specificDays(let days):
            let raw = days.map(\.rawValue).sorted().map(String.init).joined(separator: "|")
            return "specific_days:\(raw)"
        case .everyNDays(let interval):
            return "every_n_days:\(interval)"
        }
    }

    static func encode(type: HabitType) -> String {
        switch type {
        case .binary:
            return "binary"
        case .negative:
            return "negative"
        case .counter(let target):
            return "counter:\(target)"
        case .timer(let targetSeconds):
            return "timer:\(targetSeconds)"
        }
    }

    // MARK: - Field decoding

    /// Split a `kind:payload` field. `omittingEmptySubsequences: false`
    /// so `specific_days:` with no days still yields a payload rather
    /// than collapsing to a bare kind.
    private static func parts(_ field: String) -> (kind: String, payload: String?) {
        let pieces = field.split(
            separator: ":",
            maxSplits: 1,
            omittingEmptySubsequences: false
        ).map(String.init)
        return (pieces[0], pieces.count > 1 ? pieces[1] : nil)
    }

    static func decodeFrequency(_ field: String) throws -> Frequency {
        let (kind, payload) = parts(field)
        switch kind {
        case "daily":
            return .daily
        case "days_per_week":
            guard let payload, let count = Int(payload) else { throw BackupError.invalidCSV }
            return .daysPerWeek(count)
        case "specific_days":
            guard let payload else { throw BackupError.invalidCSV }
            let days = try payload
                .split(separator: "|")
                .map { raw -> Weekday in
                    guard let value = Int(raw), let day = Weekday(rawValue: value) else {
                        throw BackupError.invalidCSV
                    }
                    return day
                }
            return .specificDays(Set(days))
        case "every_n_days":
            guard let payload, let interval = Int(payload) else { throw BackupError.invalidCSV }
            return .everyNDays(interval)
        default:
            throw BackupError.invalidCSV
        }
    }

    static func decodeType(_ field: String) throws -> HabitType {
        let (kind, payload) = parts(field)
        switch kind {
        case "binary":
            return .binary
        case "negative":
            return .negative
        case "counter":
            guard let payload, let target = Double(payload) else { throw BackupError.invalidCSV }
            return .counter(target: target)
        case "timer":
            guard let payload, let seconds = Double(payload) else { throw BackupError.invalidCSV }
            return .timer(targetSeconds: seconds)
        default:
            throw BackupError.invalidCSV
        }
    }

    static func decodeDate(_ field: String) throws -> Date {
        guard let date = try? Date(field, strategy: .iso8601) else {
            throw BackupError.invalidCSV
        }
        return date
    }

    static func decodeOptionalDate(_ field: String) throws -> Date? {
        field.isEmpty ? nil : try decodeDate(field)
    }

    static func decodeColor(_ field: String) throws -> HabitColor {
        guard let color = HabitColor(rawValue: field) else { throw BackupError.invalidCSV }
        return color
    }

    /// Lowercased before parsing: spreadsheets normalize a boolean
    /// column to `TRUE` / `FALSE` on save, and rejecting those would
    /// break the round-trip that motivates shipping CSV at all.
    static func decodeBool(_ field: String) throws -> Bool {
        guard let value = Bool(field.lowercased()) else { throw BackupError.invalidCSV }
        return value
    }

    static func decodeInt(_ field: String) throws -> Int {
        guard let value = Int(field) else { throw BackupError.invalidCSV }
        return value
    }
}
