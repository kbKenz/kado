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
}
