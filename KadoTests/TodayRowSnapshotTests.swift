import Foundation
import SwiftData
import Testing
@testable import Kado
import KadoCore

/// Today snapshots its habits once per pass and derives the day strip's
/// range, its rings and the list sections from those rows. These pin
/// that the rows carry the same answers the records gave.
@Suite("TodayRow snapshot")
@MainActor
struct TodayRowSnapshotTests {
    private let calendar = TestCalendar.utc

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema(versionedSchema: KadoSchemaV10.self)
        return try ModelContainer(
            for: schema,
            migrationPlan: KadoMigrationPlan.self,
            configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        )
    }

    @Test("The earliest date is the creation day or the oldest record, zero values included")
    func earliestDate() throws {
        // Held for the whole test: a context outlives a released container
        // only until its autosave fires, which traps.
        let container = try makeContainer()
        let ctx = container.mainContext
        let created = TestCalendar.day(-5)
        let habit = HabitRecord(name: "Read", frequency: .daily, type: .binary, createdAt: created)
        ctx.insert(habit)
        try ctx.save()
        #expect(TodayRow(habit).earliestDate == created)

        // A backfill before creation, and a cleared (zero) record before
        // that: the strip used every record's date, whatever its value.
        ctx.insert(CompletionRecord(date: TestCalendar.day(-8), value: 1, habit: habit))
        ctx.insert(CompletionRecord(date: TestCalendar.day(-9), value: 0, habit: habit))
        ctx.insert(CompletionRecord(date: TestCalendar.day(-1), value: 1, habit: habit))
        try ctx.save()
        let row = TodayRow(habit)
        let allDates = [habit.createdAt] + (habit.completions ?? []).map(\.date)
        #expect(row.earliestDate == allDates.min())
        #expect(row.earliestDate == TestCalendar.day(-9))

        let value = TodayRow(habit: row.habit, completions: row.completions)
        #expect(value.earliestDate == row.earliestDate)
    }

    @Test("Sections from rows equal sections from records")
    func sectionsFromRowsMatchRecords() throws {
        // Held for the whole test: a context outlives a released container
        // only until its autosave fires, which traps.
        let container = try makeContainer()
        let ctx = container.mainContext
        let evaluator = DefaultFrequencyEvaluator(calendar: calendar)
        let frequencies: [Frequency] = [
            .daily, .specificDays([.monday]), .specificDays([.tuesday, .friday]),
            .everyNDays(2), .everyNDays(3), .daysPerWeek(2),
        ]
        let types: [HabitType] = [.binary, .counter(target: 3), .negative]
        var index = 0
        for frequency in frequencies {
            for type in types {
                let habit = HabitRecord(
                    name: "H\(index)", frequency: frequency, type: type,
                    createdAt: TestCalendar.day(-(index % 9)), sortOrder: index
                )
                ctx.insert(habit)
                for offset in stride(from: -(index % 7), to: 2, by: 1 + index % 3) {
                    ctx.insert(CompletionRecord(date: TestCalendar.day(offset), value: Double(index % 4), habit: habit))
                }
                index += 1
            }
        }
        try ctx.save()
        let records = try ctx.fetch(FetchDescriptor<HabitRecord>(sortBy: [SortDescriptor(\.sortOrder)]))
        let rows = records.map { TodayRow($0) }

        for offset in -10...3 {
            let day = TestCalendar.day(offset)
            let fromRecords = TodayRow.sections(from: records, on: day, evaluator: evaluator, calendar: calendar)
            let fromRows = TodayRow.sections(from: rows, on: day, evaluator: evaluator, calendar: calendar)
            #expect(fromRows.due.map(\.id) == fromRecords.due.map(\.id), "due, day \(offset)")
            #expect(fromRows.other.map(\.id) == fromRecords.other.map(\.id), "other, day \(offset)")
        }
    }
}
