import Foundation
import SwiftData
import Testing
@testable import Kado
import KadoCore

@Suite("Reflection backup")
@MainActor
struct ReflectionBackupTests {
    private let created = Date(timeIntervalSince1970: 1_790_000_000)

    private func container() throws -> ModelContainer {
        let schema = Schema(versionedSchema: KadoSchemaV10.self)
        return try ModelContainer(for: schema, configurations: ModelConfiguration(UUID().uuidString, schema: schema, isStoredInMemoryOnly: true))
    }

    private func seed(_ context: ModelContext) throws -> ReflectionRecord {
        let reflection = ReflectionRecord(year: 2026, month: 10, createdAt: created, updatedAt: created, completedAt: created.addingTimeInterval(900))
        context.insert(reflection)
        context.insert(ReflectionAnswerRecord(questionID: "core.word", prompt: "Describe this month in one word.",
                                              text: "Steady, \"mostly\"\nyes", createdAt: created, updatedAt: created, reflection: reflection))
        context.insert(ReflectionAnswerRecord(questionID: "rating.overall", prompt: "Overall", rating: 7,
                                              createdAt: created, updatedAt: created, reflection: reflection))
        context.insert(ReflectionAnswerRecord(questionID: "followup.problem", prompt: "Money → now", statusRaw: "better",
                                              createdAt: created, updatedAt: created, reflection: reflection))
        try context.save()
        return reflection
    }

    private func entries(_ context: ModelContext) throws -> [ReflectionEntry] {
        try context.fetch(FetchDescriptor<ReflectionRecord>()).mergedEntries
    }

    @Test("JSON export and import restore every reflection field")
    func jsonRoundTrip() throws {
        let source = try container()
        let sourceContext = ModelContext(source)
        _ = try seed(sourceContext)
        let exporter = DefaultBackupExporter(now: { self.created }, appVersion: "test")
        let data = try exporter.encode(try exporter.export(from: sourceContext))

        let importer = DefaultBackupImporter()
        let document = try importer.parse(data: data)
        #expect(document.formatVersion == 7)
        #expect(document.reflections.count == 1)
        #expect(document.reflections.first?.answers.count == 3)

        let target = try container()
        let targetContext = ModelContext(target)
        let summary = try importer.apply(document, to: targetContext)
        #expect(summary.newReflections == 1)
        #expect(try entries(targetContext) == entries(sourceContext))

        // A second import updates in place.
        let again = try importer.apply(document, to: targetContext)
        #expect(again.updatedReflections == 1)
        #expect(try targetContext.fetchCount(FetchDescriptor<ReflectionRecord>()) == 1)
        #expect(try targetContext.fetchCount(FetchDescriptor<ReflectionAnswerRecord>()) == 3)
    }

    @Test("CSV export and import restore every reflection field")
    func csvRoundTrip() throws {
        let source = try container()
        let sourceContext = ModelContext(source)
        _ = try seed(sourceContext)
        let exporter = DefaultBackupExporter(now: { self.created }, appVersion: "test")
        let coder = CSVBackupCoder(now: { self.created })
        let document = try exporter.export(from: sourceContext)
        let decoded = try coder.decode(coder.encode(document))
        #expect(decoded.reflections == document.reflections)

        let target = try container()
        let targetContext = ModelContext(target)
        try DefaultBackupImporter().apply(decoded, to: targetContext)
        #expect(try entries(targetContext) == entries(sourceContext))
    }

    @Test("An older file without reflections still imports")
    func olderFile() throws {
        let json = #"{"formatVersion":6,"exportedAt":"2026-10-01T00:00:00Z","appVersion":"1","habits":[]}"#
        let document = try DefaultBackupImporter().parse(data: Data(json.utf8))
        #expect(document.reflections.isEmpty)
    }

    @Test("A rating out of range or an unknown status is refused")
    func validation() throws {
        let target = try container()
        let answer = ReflectionAnswerBackup(id: UUID(), questionID: "rating.overall", prompt: "", text: "", rating: 11,
                                            status: "", createdAt: created, updatedAt: created)
        let reflection = ReflectionBackup(id: UUID(), year: 2026, month: 10, createdAt: created, updatedAt: created,
                                          completedAt: nil, answers: [answer])
        let document = BackupDocument(exportedAt: created, appVersion: "t", habits: [], reflections: [reflection])
        #expect(throws: BackupError.invalidJSON) { try DefaultBackupImporter().apply(document, to: ModelContext(target)) }

        var badStatus = reflection
        badStatus.answers = [ReflectionAnswerBackup(id: UUID(), questionID: "followup.problem", prompt: "", text: "",
                                                    rating: nil, status: "maybe", createdAt: created, updatedAt: created)]
        let second = BackupDocument(exportedAt: created, appVersion: "t", habits: [], reflections: [badStatus])
        #expect(throws: BackupError.invalidJSON) { try DefaultBackupImporter().apply(second, to: ModelContext(target)) }
    }

    @Test("Two records for one month merge, the later edit winning")
    func mergesDuplicates() throws {
        let target = try container()
        let context = ModelContext(target)
        let first = ReflectionRecord(year: 2026, month: 10, createdAt: created)
        let second = ReflectionRecord(year: 2026, month: 10, createdAt: created.addingTimeInterval(60))
        context.insert(first)
        context.insert(second)
        context.insert(ReflectionAnswerRecord(questionID: "core.word", text: "Old", updatedAt: created, reflection: first))
        context.insert(ReflectionAnswerRecord(questionID: "core.word", text: "New", updatedAt: created.addingTimeInterval(5), reflection: second))
        context.insert(ReflectionAnswerRecord(questionID: "core.people", text: "Mum", updatedAt: created, reflection: second))
        try context.save()
        let merged = try entries(context)
        #expect(merged.count == 1)
        #expect(merged.first?.id == first.id)
        #expect(merged.first?.word == "New")
        #expect(merged.first?.text("core.people") == "Mum")
    }
}
