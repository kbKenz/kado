import Foundation
import SwiftData
import Testing
@testable import Kado
import KadoCore

@Suite("ReflectionStore")
@MainActor
struct ReflectionStoreTests {
    private let calendar = TestCalendar.utc
    private let october = ReflectionMonth(year: 2026, month: 10)
    private let now = Date(timeIntervalSince1970: 1_790_000_000)
    /// Held for the test's lifetime: a `ModelContext` does not retain its container.
    private let container: ModelContainer
    private let context: ModelContext

    init() throws {
        let schema = Schema(versionedSchema: KadoSchemaV10.self)
        container = try ModelContainer(for: schema, configurations: ModelConfiguration(UUID().uuidString, schema: schema, isStoredInMemoryOnly: true))
        context = ModelContext(container)
        context.autosaveEnabled = false
    }

    private var store: ReflectionStore { ReflectionStore(context: context, now: { self.now }) }

    @Test("Saving creates the month once and updates an answer in place")
    func saveUpserts() throws {
        try store.save(ReflectionAnswer(questionID: "core.word", prompt: "Word?", text: "Calm"), for: october)
        try store.save(ReflectionAnswer(questionID: "core.word", prompt: "Word?", text: "Steady"), for: october)
        try store.save(ReflectionAnswer(questionID: "rating.overall", rating: 8), for: october)
        #expect(try context.fetchCount(FetchDescriptor<ReflectionRecord>()) == 1)
        #expect(try context.fetchCount(FetchDescriptor<ReflectionAnswerRecord>()) == 2)
        let entry = try #require(try store.entry(for: october))
        #expect(entry.word == "Steady")
        #expect(entry.overall == 8.0)
        #expect(entry.answer("core.word")?.prompt == "Word?")
        #expect(!entry.isComplete)
    }

    @Test("An emptied answer is removed")
    func emptyRemoves() throws {
        try store.save(ReflectionAnswer(questionID: "core.word", text: "Calm"), for: october)
        try store.save(ReflectionAnswer(questionID: "core.word", text: "   "), for: october)
        #expect(try context.fetchCount(FetchDescriptor<ReflectionAnswerRecord>()) == 0)
        #expect(try store.entry(for: october)?.answers.isEmpty == true)
    }

    @Test("A follow-up keeps its status")
    func followUpStatus() throws {
        try store.save(ReflectionAnswer(questionID: ReflectionCatalog.followUpProblemID, status: .better), for: october)
        #expect(try store.entry(for: october)?.answer(ReflectionCatalog.followUpProblemID)?.status == .better)
    }

    @Test("Completing keeps the first finish date; deleting removes the month")
    func completeAndDelete() throws {
        try store.complete(october)
        let later = ReflectionStore(context: context, now: { self.now.addingTimeInterval(3600) })
        try later.complete(october)
        #expect(try store.entry(for: october)?.completedAt == now)
        try store.save(ReflectionAnswer(questionID: "core.word", text: "Calm"), for: october)
        try store.delete(october)
        #expect(try context.fetchCount(FetchDescriptor<ReflectionRecord>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<ReflectionAnswerRecord>()) == 0)
    }

    @Test("Months stay apart and list newest first")
    func entriesOrder() throws {
        try store.save(ReflectionAnswer(questionID: "core.word", text: "A"), for: october.previous)
        try store.save(ReflectionAnswer(questionID: "core.word", text: "B"), for: october)
        #expect(try store.entries().map(\.month) == [october, october.previous])
    }

    @Test("Month stats count tasks, habit logs, focus time and active days in the month only")
    func stats() throws {
        let inMonth = TestCalendar.instant(calendar, 2026, 10, 5, 10)
        let otherDay = TestCalendar.instant(calendar, 2026, 10, 9, 10)
        let outside = TestCalendar.instant(calendar, 2026, 11, 1, 10)
        context.insert(TaskRecord(title: "Done", completedAt: inMonth))
        context.insert(TaskRecord(title: "Next month", completedAt: outside))
        context.insert(TaskRecord(title: "Open"))
        let read = HabitRecord(name: "Read", type: .binary)
        let soda = HabitRecord(name: "Soda", type: .negative)
        context.insert(read)
        context.insert(soda)
        context.insert(CompletionRecord(date: inMonth, value: 1, habit: read))
        context.insert(CompletionRecord(date: otherDay, value: 1, habit: read))
        context.insert(CompletionRecord(date: otherDay, value: 1, habit: soda))
        context.insert(WorkSessionRecord(startedAt: inMonth, endedAt: inMonth.addingTimeInterval(5400)))
        context.insert(WorkSessionRecord(startedAt: outside, endedAt: outside.addingTimeInterval(600)))
        try context.save()

        let stats = ReflectionStatsBuilder(calendar: calendar).stats(for: october, in: context)
        #expect(stats == ReflectionMonthStats(tasksDone: 1, habitCheckIns: 2, focusSeconds: 5400, activeDays: 2))
    }
}
