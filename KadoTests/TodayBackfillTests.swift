import Foundation
import SwiftData
import Testing
@testable import Kado
import KadoCore

/// Pins the logging contract `TodayView` relies on when it shows a
/// past day: a write pinned to that day lands on that day only.
@Suite("Today backfill")
@MainActor
struct TodayBackfillTests {
    private let cal = TestCalendar.utc

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema(versionedSchema: KadoSchemaV10.self)
        return try ModelContainer(
            for: schema,
            migrationPlan: KadoMigrationPlan.self,
            configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        )
    }

    @Test("Toggling on a past day writes that day's completion")
    func toggleOnPastDay() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let habit = HabitRecord(name: "Read", frequency: .daily, type: .binary, createdAt: TestCalendar.day(-10))
        ctx.insert(habit)
        let past = cal.startOfDay(for: TestCalendar.day(-3))
        let instant = DayBoundary(calendar: cal).loggingInstant(for: TestCalendar.referenceDate, on: past)
        CompletionToggler(calendar: cal).toggleToday(for: habit, on: instant, in: ctx)
        let dates = (habit.completions ?? []).map(\.date)
        #expect(dates.count == 1)
        #expect(cal.isDate(dates[0], inSameDayAs: past))
    }

    @Test("A counter + on a past day changes only that day")
    func counterOnPastDay() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let habit = HabitRecord(name: "Water", frequency: .daily, type: .counter(target: 8), createdAt: TestCalendar.day(-10))
        ctx.insert(habit)
        let past = cal.startOfDay(for: TestCalendar.day(-2))
        let boundary = DayBoundary(calendar: cal)
        let logger = CompletionLogger(calendar: cal)
        logger.incrementCounter(
            for: habit,
            on: boundary.loggingInstant(for: TestCalendar.referenceDate, on: past),
            in: ctx
        )
        #expect(logger.value(for: habit, on: past) == 1.0)
        #expect(logger.value(for: habit, on: TestCalendar.referenceDate) == 0.0)
    }
}
