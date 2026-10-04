import Foundation
import SwiftData
import Testing
@testable import Kado
import KadoCore

@Suite("Planning persistence and backup")
@MainActor
struct PlanningPersistenceTests {
    private let day = Date(timeIntervalSince1970: 1_700_000_000)

    private func container() throws -> ModelContainer {
        let schema = Schema(versionedSchema: KadoSchemaV8.self)
        return try ModelContainer(
            for: schema,
            configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        )
    }

    private func seed(_ context: ModelContext) throws {
        let habit = HabitRecord(name: "Walk", sortOrder: 8)
        let task = TaskRecord(
            title: "Meeting, with Thomas", notes: "Agenda\nReview plans", dueDate: day,
            createdAt: day, updatedAt: day, completedAt: day,
            externalAccountID: "account", externalCalendarID: "primary",
            externalEventID: "event", externalURL: "https://calendar.google.com/event",
            externalUpdatedAt: day, externalCancelledAt: day
        )
        context.insert(habit)
        context.insert(task)
        context.insert(ScheduleBlockRecord(
            plannedDay: day, startAt: day, createdAt: day, updatedAt: day, task: task
        ))
        context.insert(ScheduleBlockRecord(
            plannedDay: day, endAt: day,
            createdAt: day.addingTimeInterval(1), updatedAt: day, habit: habit
        ))
        try context.save()
    }

    @Test("JSON and CSV preserve tasks, independent times and relationships")
    func planningRoundTrip() throws {
        let source = try container()
        try seed(source.mainContext)
        let exporter = DefaultBackupExporter(now: { Date(timeIntervalSince1970: 0) }, appVersion: "test")
        let expected = try exporter.export(from: source.mainContext)
        let importer = DefaultBackupImporter()
        let csv = CSVBackupCoder()
        let documents = [
            try importer.parse(data: exporter.encode(expected)),
            try csv.decode(csv.encode(expected))
        ]

        for document in documents {
            #expect(document.tasks == expected.tasks)
            #expect(document.scheduleBlocks == expected.scheduleBlocks)
            let destination = try container()
            let preview = try importer.summary(for: document, in: destination.mainContext)
            #expect(preview.newTasks == 1)
            #expect(preview.newScheduleBlocks == 2)
            let summary = try importer.apply(document, to: destination.mainContext)
            #expect(summary == preview)
            let restored = try exporter.export(from: destination.mainContext)
            #expect(restored.tasks == expected.tasks)
            #expect(restored.scheduleBlocks == expected.scheduleBlocks)
            #expect(restored.habits.first?.sortOrder == 8)
            let task = try #require(destination.mainContext.fetch(FetchDescriptor<TaskRecord>()).first)
            #expect(task.scheduleBlocks?.count == 1)
            #expect(task.scheduleBlocks?.first?.startAt == day)
            #expect(task.scheduleBlocks?.first?.endAt == nil)
            #expect(task.completedAt == day)
            let repeated = try importer.apply(document, to: destination.mainContext)
            #expect(repeated.newTasks == 0)
            #expect(repeated.newScheduleBlocks == 0)
            #expect(try destination.mainContext.fetchCount(FetchDescriptor<ScheduleBlockRecord>()) == 2)
        }
    }

    @Test("Version 1 JSON without planning arrays remains importable")
    func legacyJSON() throws {
        let json = #"{"formatVersion":1,"exportedAt":"2023-11-16T02:00:00Z","appVersion":"1.0","habits":[]}"#
        let document = try DefaultBackupImporter().parse(data: Data(json.utf8))
        #expect(document.formatVersion == 1)
        #expect(document.tasks.isEmpty)
        #expect(document.scheduleBlocks.isEmpty)
    }

    @Test("Version 1 CSV header remains importable")
    func legacyCSV() throws {
        let csv = "format_version,habit_id,habit_name,frequency,type,created_at,archived_at,color,icon,reminders_enabled,reminder_hour,reminder_minute,completion_id,completion_date,value,note\n1,AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA,Read,daily,binary,2023-11-14T22:13:20Z,,blue,leaf,false,9,0,,,,\n"
        let document = try CSVBackupCoder().decode(Data(csv.utf8))
        #expect(document.habits.count == 1)
        #expect(document.tasks.isEmpty)
        #expect(document.scheduleBlocks.isEmpty)
    }

    @Test("Deleting a task cascades to its planned blocks")
    func taskDeletion() throws {
        let store = try container()
        try seed(store.mainContext)
        let task = try #require(store.mainContext.fetch(FetchDescriptor<TaskRecord>()).first)
        store.mainContext.delete(task)
        try store.mainContext.save()
        let blocks = try store.mainContext.fetch(FetchDescriptor<ScheduleBlockRecord>())
        #expect(blocks.count == 1)
        #expect(blocks.first?.habit != nil)
    }

    @Test("Broken planning references are rejected before changing the store")
    func unresolvedReference() throws {
        let store = try container()
        let backup = BackupDocument(
            exportedAt: day, appVersion: "test", habits: [],
            tasks: [TaskBackup(id: UUID(), title: "Valid task", createdAt: day, updatedAt: day)],
            scheduleBlocks: [ScheduleBlockBackup(
                id: UUID(), plannedDay: day, createdAt: day, updatedAt: day, taskID: UUID()
            )]
        )
        #expect(throws: BackupError.invalidJSON) {
            try DefaultBackupImporter().apply(backup, to: store.mainContext)
        }
        #expect(try store.mainContext.fetchCount(FetchDescriptor<TaskRecord>()) == 0)
        #expect(try store.mainContext.fetchCount(FetchDescriptor<ScheduleBlockRecord>()) == 0)
    }

    @Test("Duplicate task and block rows are collapsed during CSV decoding")
    func duplicatePlanningRows() throws {
        let taskID = UUID()
        let document = BackupDocument(
            exportedAt: day, appVersion: "test", habits: [],
            tasks: [TaskBackup(id: taskID, title: "Meeting", createdAt: day, updatedAt: day)],
            scheduleBlocks: [ScheduleBlockBackup(
                id: UUID(), plannedDay: day, createdAt: day, updatedAt: day, taskID: taskID
            )]
        )
        let coder = CSVBackupCoder()
        let csv = String(decoding: coder.encode(document), as: UTF8.self)
        let rows = csv.split(separator: "\n").map(String.init)
        let duplicated = (rows + rows.dropFirst()).joined(separator: "\n") + "\n"
        let parsed = try coder.decode(Data(duplicated.utf8))
        #expect(parsed.tasks == document.tasks)
        #expect(parsed.scheduleBlocks == document.scheduleBlocks)
    }

    @Test("JSON and CSV preserve work sessions and their links")
    func sessionRoundTrip() throws {
        let source = try container()
        let context = source.mainContext
        let task = TaskRecord(title: "Research", createdAt: day, updatedAt: day)
        context.insert(task)
        let block = ScheduleBlockRecord(plannedDay: day, startAt: day, createdAt: day, updatedAt: day, task: task)
        context.insert(block)
        context.insert(WorkSessionRecord(
            startedAt: day, endedAt: day.addingTimeInterval(3000), pausedSeconds: 120,
            createdAt: day, updatedAt: day, task: task, scheduleBlock: block
        ))
        try context.save()

        let exporter = DefaultBackupExporter(now: { Date(timeIntervalSince1970: 0) }, appVersion: "test")
        let expected = try exporter.export(from: context)
        #expect(expected.workSessions.count == 1)
        let importer = DefaultBackupImporter()
        let csv = CSVBackupCoder()
        for document in [try importer.parse(data: exporter.encode(expected)), try csv.decode(csv.encode(expected))] {
            #expect(document.workSessions == expected.workSessions)
            let destination = try container()
            let summary = try importer.apply(document, to: destination.mainContext)
            #expect(summary.newWorkSessions == 1)
            #expect(try exporter.export(from: destination.mainContext).workSessions == expected.workSessions)
            let restored = try #require(destination.mainContext.fetch(FetchDescriptor<WorkSessionRecord>()).first)
            #expect(restored.task?.title == "Research")
            #expect(restored.scheduleBlock?.id == block.id)
            #expect(try importer.apply(document, to: destination.mainContext).newWorkSessions == 0)
        }
    }

    @Test("A session ending before it starts is rejected")
    func invalidSession() throws {
        var document = BackupDocument(exportedAt: day, appVersion: "test", habits: [])
        document.workSessions = [WorkSessionBackup(
            id: UUID(), startedAt: day, endedAt: day.addingTimeInterval(-1), pausedAt: nil, pausedSeconds: 0,
            createdAt: day, updatedAt: day, taskID: nil, habitID: nil, scheduleBlockID: nil
        )]
        let destination = try container()
        #expect(throws: BackupError.self) {
            try DefaultBackupImporter().apply(document, to: destination.mainContext)
        }
    }

    @Test("A session linking both task and habit, or an unknown target, is rejected")
    func invalidSessionLinks() throws {
        let taskID = UUID()
        let habitID = UUID()
        func session(task: UUID?, habit: UUID?, block: UUID?) -> WorkSessionBackup {
            WorkSessionBackup(
                id: UUID(), startedAt: day, endedAt: nil, pausedAt: nil, pausedSeconds: 0,
                createdAt: day, updatedAt: day, taskID: task, habitID: habit, scheduleBlockID: block
            )
        }
        let habit = HabitBackup(
            id: habitID, name: "Walk", frequency: .daily, type: .binary, createdAt: day, archivedAt: nil,
            color: .blue, icon: "figure.walk", remindersEnabled: false, reminderHour: 9, reminderMinute: 0,
            completions: [], sortOrder: 0, goalID: nil
        )
        let cases = [
            session(task: taskID, habit: habitID, block: nil),
            session(task: UUID(), habit: nil, block: nil),
            session(task: nil, habit: UUID(), block: nil),
            session(task: nil, habit: nil, block: UUID())
        ]
        for bad in cases {
            var document = BackupDocument(
                exportedAt: day, appVersion: "test", habits: [habit],
                tasks: [TaskBackup(id: taskID, title: "Task", createdAt: day, updatedAt: day)]
            )
            document.workSessions = [bad]
            let destination = try container()
            #expect(throws: BackupError.invalidJSON) {
                try DefaultBackupImporter().apply(document, to: destination.mainContext)
            }
            #expect(try destination.mainContext.fetchCount(FetchDescriptor<WorkSessionRecord>()) == 0)
        }
    }

    @Test("A version 4 JSON document without workSessions still imports with no sessions")
    func versionFourJSON() throws {
        let json = """
        {"formatVersion":4,"exportedAt":"2023-11-14T22:13:20Z","appVersion":"old","habits":[]}
        """
        let importer = DefaultBackupImporter()
        let document = try importer.parse(data: Data(json.utf8))
        #expect(document.workSessions.isEmpty)
        let destination = try container()
        let summary = try importer.apply(document, to: destination.mainContext)
        #expect(summary.totalWorkSessions == 0)
    }

    @Test("A version 4 CSV header without session columns still decodes with no sessions")
    func versionFourCSV() throws {
        let coder = CSVBackupCoder()
        let header = CSVBackupCoder.progressColumns
        var row = Array(repeating: "", count: header.count)
        row[0] = "4"
        row[header.firstIndex(of: "entity_type")!] = "task"
        row[header.firstIndex(of: "task_id")!] = UUID().uuidString
        row[header.firstIndex(of: "task_title")!] = "Old"
        row[header.firstIndex(of: "created_at")!] = "2023-11-14T22:13:20Z"
        row[header.firstIndex(of: "updated_at")!] = "2023-11-14T22:13:20Z"
        let text = [header, row].map { $0.joined(separator: ",") }.joined(separator: "\n") + "\n"
        let document = try coder.decode(Data(text.utf8))
        #expect(document.tasks.count == 1)
        #expect(document.workSessions.isEmpty)
        #expect(document.formatVersion == 4)
    }
}
