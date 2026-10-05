import Foundation
import SwiftData
import Testing
import KadoCore
@testable import Kado

/// `GoalProgressInputs` replaced snapshotting every table once per
/// goal row. Its results must equal the calculator's over the full
/// tables, whatever the links look like.
@Suite("GoalProgressInputs") @MainActor
struct GoalProgressInputsTests {
    private struct SplitMix: RandomNumberGenerator {
        var state: UInt64
        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
    }

    private func container() throws -> ModelContainer {
        let schema = Schema(versionedSchema: KadoSchemaV9.self)
        return try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true))
    }


    private func expectSame(_ a: GoalProgressResult, _ b: GoalProgressResult) {
        #expect(a.current == b.current)
        #expect(a.fraction == b.fraction)
        #expect(a.unit == b.unit)
        #expect(a.isAvailable == b.isAvailable)
        #expect(a.contributions == b.contributions)
    }

    /// One store and one fetch per table, kept short on purpose. A first
    /// cut fetched every table once per goal and held the main actor for
    /// seconds; the full suite then died in a SwiftData timer trap,
    /// though the suite passed on its own. The trap is in
    /// `ModelContext`'s autosave timer, so this test uses its own
    /// context with autosave off, not `mainContext`, and keeps the
    /// container alive until the last read: no timer is left behind
    /// to fire once the container is gone.
    @Test("Matches the full-table computation for every goal, over a random store")
    func matchesFullTables() throws {
        var rng = SplitMix(state: 7)
        let calendar = TestCalendar.utc
        let today = TestCalendar.day(0)
        let store = try container()
        defer { withExtendedLifetime(store) {} }
        let context = ModelContext(store)
        context.autosaveEnabled = false
        let goals = (0..<40).map { GoalRecord(name: "Goal \($0)") }
        goals.forEach(context.insert)
        let habitTypes: [HabitType] = [.counter(target: 5), .timer(targetSeconds: 600), .binary]
        let habits = (0..<20).map { _ in
            HabitRecord(
                name: "Habit",
                type: habitTypes.randomElement(using: &rng)!,
                goal: Bool.random(using: &rng) ? goals.randomElement(using: &rng) : nil
            )
        }
        habits.forEach(context.insert)
        for _ in 0..<200 {
            context.insert(CompletionRecord(
                date: TestCalendar.day(Int.random(in: -40...3, using: &rng)),
                value: [0, 1, 2.5, 30].randomElement(using: &rng)!,
                note: Bool.random(using: &rng) ? "note" : nil,
                habit: Int.random(in: 0..<10, using: &rng) == 0 ? nil : habits.randomElement(using: &rng)
            ))
        }
        for _ in 0..<80 {
            context.insert(TaskRecord(
                title: "Task",
                completedAt: Bool.random(using: &rng) ? TestCalendar.day(Int.random(in: -40...3, using: &rng)) : nil,
                goal: Int.random(in: 0..<4, using: &rng) == 0 ? nil : goals.randomElement(using: &rng)
            ))
        }
        for _ in 0..<80 {
            context.insert(GoalProgressEntryRecord(
                date: TestCalendar.day(Int.random(in: -40...3, using: &rng)),
                amount: [-1, 0, 1, 4].randomElement(using: &rng)!,
                goal: Int.random(in: 0..<5, using: &rng) == 0 ? nil : goals.randomElement(using: &rng)
            ))
        }
        for goal in goals {
            let mode: GoalProgressMode = [.manual, .tasks, .habit].randomElement(using: &rng)!
            goal.startDate = Bool.random(using: &rng) ? TestCalendar.day(-20) : nil
            goal.measurement = GoalMeasurement(
                enabled: Int.random(in: 0..<6, using: &rng) != 0,
                mode: mode,
                baseline: 0,
                target: 50,
                unit: "units",
                // Sometimes a habit linked to another goal, or to none.
                habitID: mode == .habit ? habits.randomElement(using: &rng)?.id : nil
            )
        }
        try context.save()

        let entries = try context.fetch(FetchDescriptor<GoalProgressEntryRecord>())
        let tasks = try context.fetch(FetchDescriptor<TaskRecord>())
        let habitRecords = try context.fetch(FetchDescriptor<HabitRecord>())
        let completions = try context.fetch(FetchDescriptor<CompletionRecord>())
        let inputs = GoalProgressInputs(
            measurements: goals.map(\.measurement),
            entries: entries, tasks: tasks, habits: habitRecords, completions: completions
        )
        // What the Goals list and the goal detail passed before: every
        // row of every table.
        let allEntries = entries.compactMap(\.snapshot)
        let allTasks = tasks.map {
            TaskBackup(id: $0.id, title: $0.title, createdAt: $0.createdAt, updatedAt: $0.updatedAt, completedAt: $0.completedAt, goalID: $0.goal?.id)
        }
        let allHabits = habitRecords.map(\.snapshot)
        let allCompletions = completions.compactMap(\.snapshot)
        for goal in goals {
            let grouped = inputs.progress(
                goalID: goal.id, measurement: goal.measurement, startDate: goal.startDate,
                today: today, calendar: calendar
            )
            let full = GoalProgressCalculator.calculate(
                goalID: goal.id, measurement: goal.measurement, startDate: goal.startDate, today: today, calendar: calendar,
                entries: allEntries, tasks: allTasks, habits: allHabits, completions: allCompletions
            )
            expectSame(grouped, full)
        }
    }
}
