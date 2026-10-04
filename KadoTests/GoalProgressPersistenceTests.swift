import Foundation
import SwiftData
import Testing
import KadoCore

@Suite("Goal progress persistence") @MainActor
struct GoalProgressPersistenceTests {
    func container() throws -> ModelContainer {
        let schema = Schema(versionedSchema: KadoSchemaV8.self)
        return try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true))
    }
    @Test func portableRoundTripAndLegacyMerge() throws {
        let source = try container()
        let goal = GoalRecord(name: "Read")
        goal.measurement = GoalMeasurement(enabled: true, target: 100, unit: "pages")
        source.mainContext.insert(goal)
        let entry = GoalProgressEntryRecord(date: Date(timeIntervalSince1970: 1_700_000_000), amount: 5, note: "A, \"quote\"\nand line", goal: goal)
        source.mainContext.insert(entry)
        try source.mainContext.save()
        let exporter = DefaultBackupExporter()
        let document = try exporter.export(from: source.mainContext)
        #expect(document.goalProgressEntries.count == 1)
        for decoded in [try DefaultBackupImporter().parse(data: exporter.encode(document)), try CSVBackupCoder().decode(CSVBackupCoder().encode(document))] {
            let destination = try container()
            let summary = try DefaultBackupImporter().apply(decoded, to: destination.mainContext)
            #expect(summary.newGoalProgressEntries == 1)
            let copied = try #require(destination.mainContext.fetch(FetchDescriptor<GoalRecord>()).first)
            #expect(copied.measurement == goal.measurement)
            #expect(copied.progressEntries?.first?.note == entry.note)
            var legacy = document
            legacy.formatVersion = 3
            legacy.goals[0].measurement = nil
            legacy.goalProgressEntries = []
            try DefaultBackupImporter().apply(legacy, to: destination.mainContext)
            #expect(copied.measurement == goal.measurement)
            #expect(copied.progressEntries?.count == 1)
        }
    }
    @Test func deleteGoalPreservesTaskButDeletesEntries() throws {
        let store = try container()
        let goal = GoalRecord(name: "Read")
        let task = TaskRecord(title: "Chapter", goal: goal)
        store.mainContext.insert(goal); store.mainContext.insert(task)
        store.mainContext.insert(GoalProgressEntryRecord(amount: 1, goal: goal))
        try store.mainContext.save()
        store.mainContext.delete(goal)
        try store.mainContext.save()
        #expect(try store.mainContext.fetchCount(FetchDescriptor<GoalProgressEntryRecord>()) == 0)
        #expect(try store.mainContext.fetchCount(FetchDescriptor<TaskRecord>()) == 1)
        #expect(task.goal == nil)
    }
    @Test func invalidEntryDoesNotMutateStore() throws {
        let store = try container()
        let goal = GoalBackup(id: UUID(), name: "Read", createdAt: .now, updatedAt: .now)
        let document = BackupDocument(exportedAt: .now, appVersion: "test", habits: [], goals: [goal], goalProgressEntries: [GoalProgressEntry(goalID: goal.id, date: .now, amount: -1)])
        #expect(throws: (any Error).self) { try DefaultBackupImporter().apply(document, to: store.mainContext) }
        #expect(try store.mainContext.fetchCount(FetchDescriptor<GoalRecord>()) == 0)
    }
    @Test func unavailableSourceRoundTripsAfterReassignment() throws {
        let store = try container()
        let goal = GoalRecord(name: "Original")
        let destination = GoalRecord(name: "Destination")
        let habit = HabitRecord(name: "Read", type: .counter(target: 10), goal: destination)
        goal.measurement = GoalMeasurement(enabled: true, mode: .habit, target: 100, unit: "pages", habitID: habit.id)
        store.mainContext.insert(goal); store.mainContext.insert(destination); store.mainContext.insert(habit)
        try store.mainContext.save()
        let document = try DefaultBackupExporter().export(from: store.mainContext)
        let restored = try container()
        try DefaultBackupImporter().apply(document, to: restored.mainContext)
        let copied = try #require(restored.mainContext.fetch(FetchDescriptor<GoalRecord>()).first { $0.id == goal.id })
        #expect(copied.measurement.habitID == habit.id)
        let result = GoalProgressCalculator.calculate(goalID: copied.id, measurement: copied.measurement, today: .now, calendar: .current, habits: try restored.mainContext.fetch(FetchDescriptor<HabitRecord>()).map(\.snapshot))
        #expect(!result.isAvailable)
    }
    @Test func legacyCSVPreservesMeasurementAndEntries() throws {
        let store = try container()
        let goal = GoalRecord(name: "Read")
        goal.measurement = GoalMeasurement(enabled: true, target: 100, unit: "pages")
        store.mainContext.insert(goal); store.mainContext.insert(GoalProgressEntryRecord(amount: 3, goal: goal))
        try store.mainContext.save()
        let document = BackupDocument(formatVersion: 3, exportedAt: .now, appVersion: "old", habits: [], goals: [GoalBackup(id: goal.id, name: "Renamed", createdAt: .now, updatedAt: .now)])
        let rows = try CSVReader.parse(String(decoding: CSVBackupCoder().encode(document), as: UTF8.self))
        var legacyRows = [CSVBackupCoder.goalColumns]
        for row in rows.dropFirst() { var legacy = Array(row.prefix(CSVBackupCoder.goalColumns.count)); legacy[0] = "3"; legacyRows.append(legacy) }
        let decoded = try CSVBackupCoder().decode(Data(CSVWriter.write(legacyRows).utf8))
        #expect(decoded.formatVersion == 3)
        try DefaultBackupImporter().apply(decoded, to: store.mainContext)
        #expect(goal.name == "Renamed")
        #expect(goal.measurement.enabled)
        #expect(goal.progressEntries?.count == 1)
    }
    @Test func brokenOwnerAndDuplicateEntriesAreRejectedAtomically() throws {
        let store = try container()
        let goal = GoalBackup(id: UUID(), name: "Read", createdAt: .now, updatedAt: .now)
        let broken = GoalProgressEntry(goalID: UUID(), amount: 1)
        var document = BackupDocument(exportedAt: .now, appVersion: "test", habits: [], goals: [goal], goalProgressEntries: [broken])
        #expect(throws: (any Error).self) { try DefaultBackupImporter().apply(document, to: store.mainContext) }
        let entry = GoalProgressEntry(goalID: goal.id, amount: 1)
        document.goalProgressEntries = [entry, entry]
        #expect(throws: (any Error).self) { try DefaultBackupImporter().apply(document, to: store.mainContext) }
        #expect(try store.mainContext.fetchCount(FetchDescriptor<GoalRecord>()) == 0)
        #expect(try store.mainContext.fetchCount(FetchDescriptor<GoalProgressEntryRecord>()) == 0)
    }
    @Test func v6MigrationPreservesLinks() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("goal-v7-\(UUID()).store")
        defer { for suffix in ["", "-wal", "-shm"] { try? FileManager.default.removeItem(atPath: url.path + suffix) } }
        let goalID = UUID()
        do {
            let schema = Schema(versionedSchema: KadoSchemaV6.self)
            let store = try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, url: url))
            let goal = KadoSchemaV6.GoalRecord(id: goalID, name: "Existing")
            store.mainContext.insert(goal)
            store.mainContext.insert(KadoSchemaV6.TaskRecord(title: "Linked", goal: goal))
            try store.mainContext.save()
        }
        let schema = Schema(versionedSchema: KadoSchemaV8.self)
        let store = try ModelContainer(for: schema, migrationPlan: KadoMigrationPlan.self, configurations: ModelConfiguration(schema: schema, url: url))
        let goal = try #require(store.mainContext.fetch(FetchDescriptor<GoalRecord>()).first)
        #expect(goal.id == goalID)
        #expect(!goal.measurement.enabled)
        #expect(goal.tasks?.first?.title == "Linked")
        #expect(goal.progressEntries?.isEmpty ?? true)
    }
}
