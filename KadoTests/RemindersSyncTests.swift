import Foundation
import SwiftData
import Testing
import UserNotifications
@testable import Kado
import KadoCore

/// `RemindersSync` reads less than the whole store; the scheduler must
/// not be able to tell.
@Suite("RemindersSync")
@MainActor
struct RemindersSyncTests {
    private func makeContainer() throws -> ModelContainer {
        let schema = Schema(versionedSchema: KadoSchemaV10.self)
        return try ModelContainer(
            for: schema,
            migrationPlan: KadoMigrationPlan.self,
            configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        )
    }

    private func seed(_ context: ModelContext) {
        let calendar = TestCalendar.utc
        func daysAgo(_ n: Int) -> Date {
            calendar.date(byAdding: .day, value: -n, to: TestCalendar.day(0))!
        }
        let shapes: [(String, Frequency, HabitType, Bool, Date?)] = [
            ("Daily, done today", .daily, .binary, true, nil),
            ("Weekly", .daysPerWeek(3), .binary, true, nil),
            ("Tue/Thu", .specificDays([.tuesday, .thursday]), .counter(target: 5), true, nil),
            ("Cycle", .everyNDays(3), .binary, true, nil),
            ("No reminders", .daily, .binary, false, nil),
            ("Archived", .daily, .binary, true, daysAgo(2)),
        ]
        for (index, (name, frequency, type, reminders, archivedAt)) in shapes.enumerated() {
            let habit = HabitRecord(name: name, frequency: frequency, type: type,
                                    createdAt: daysAgo(30), archivedAt: archivedAt)
            habit.remindersEnabled = reminders
            habit.reminderHour = 8 + index
            context.insert(habit)
            // Streaks of different lengths, so the streak line in the
            // body differs per habit; index 0 is logged today.
            for n in index..<(index + 10) {
                context.insert(CompletionRecord(date: daysAgo(n), value: 5, habit: habit))
            }
        }
    }

    private func pendingSet(habits: [Habit], completions: [Completion]) async -> [String] {
        let center = FakeUserNotificationCenter()
        let scheduler = DefaultNotificationScheduler(
            center: center,
            frequencyEvaluator: DefaultFrequencyEvaluator(calendar: TestCalendar.utc),
            streakCalculator: DefaultStreakCalculator(calendar: TestCalendar.utc),
            calendar: TestCalendar.utc,
            now: { TestCalendar.day(0) }
        )
        await scheduler.rescheduleAll(habits: habits, completions: completions)
        return center.pending.map { request in
            let trigger = request.trigger as? UNCalendarNotificationTrigger
            return "\(request.identifier)|\(request.content.title)|\(request.content.body)|\(String(describing: trigger?.dateComponents))"
        }.sorted()
    }

    private func wholeStore(_ context: ModelContext) throws -> ([Habit], [Completion]) {
        (
            try context.fetch(FetchDescriptor<HabitRecord>()).map(\.snapshot),
            try context.fetch(FetchDescriptor<CompletionRecord>()).compactMap(\.snapshot)
        )
    }

    @Test("The narrowed read schedules exactly what the whole store would")
    func narrowedReadMatchesWholeStore() async throws {
        let container = try makeContainer()
        seed(container.mainContext)
        try container.mainContext.save()

        let (allHabits, allCompletions) = try wholeStore(container.mainContext)
        let narrowed = RemindersSync.inputs(from: container.mainContext)
        let expected = await pendingSet(habits: allHabits, completions: allCompletions)

        #expect(!expected.isEmpty)
        #expect(narrowed.habits.allSatisfy { $0.remindersEnabled && $0.archivedAt == nil })
        #expect(narrowed.habits.count == 4)
        #expect(await pendingSet(habits: narrowed.habits, completions: narrowed.completions) == expected)
    }

    @Test("The widget pass's store read schedules exactly what the whole store would")
    func widgetSourceMatchesWholeStore() async throws {
        let container = try makeContainer()
        seed(container.mainContext)
        try container.mainContext.save()

        let (allHabits, allCompletions) = try wholeStore(container.mainContext)
        let source = WidgetSnapshotBuilder.Source(context: container.mainContext)
        let expected = await pendingSet(habits: allHabits, completions: allCompletions)
        #expect(await pendingSet(habits: source.habits, completions: source.allCompletions) == expected)
    }
}
