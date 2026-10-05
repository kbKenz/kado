import Testing
import Foundation
import SwiftData
@testable import Kado
import KadoCore

@Suite("KadoSchema + KadoMigrationPlan")
@MainActor
struct KadoSchemaTests {
    @Test("V1 version identifier is 1.0.0")
    func v1Version() {
        #expect(KadoSchemaV1.versionIdentifier == Schema.Version(1, 0, 0))
    }

    @Test("V2 version identifier is 2.0.0")
    func v2Version() {
        #expect(KadoSchemaV2.versionIdentifier == Schema.Version(2, 0, 0))
    }

    @Test("V3 version identifier is 3.0.0")
    func v3Version() {
        #expect(KadoSchemaV3.versionIdentifier == Schema.Version(3, 0, 0))
    }

    @Test("V4 version identifier is 4.0.0")
    func v4Version() {
        #expect(KadoSchemaV4.versionIdentifier == Schema.Version(4, 0, 0))
    }

    @Test("V5 version identifier is 5.0.0")
    func v5Version() {
        #expect(KadoSchemaV5.versionIdentifier == Schema.Version(5, 0, 0))
    }

    @Test("V8 version identifier is 8.0.0 and adds work sessions")
    func v8Version() {
        #expect(KadoSchemaV8.versionIdentifier == Schema.Version(8, 0, 0))
        #expect(KadoSchemaV8.models.contains { $0 == KadoSchemaV8.WorkSessionRecord.self })
    }

    @Test("V9 version identifier is 9.0.0 and keeps the same seven models")
    func v9Version() {
        #expect(KadoSchemaV9.versionIdentifier == Schema.Version(9, 0, 0))
        #expect(KadoSchemaV9.models.count == KadoSchemaV8.models.count)
        #expect(KadoSchemaV9.models.contains { $0 == KadoSchemaV9.WorkSessionRecord.self })
    }

    @Test("Deleting a block keeps its sessions; deleting a task removes them")
    func sessionDeleteRules() throws {
        let schema = Schema(versionedSchema: KadoSchemaV8.self)
        let store = try ModelContainer(
            for: schema,
            configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        )
        let context = store.mainContext
        let task = KadoSchemaV8.TaskRecord(title: "Research")
        context.insert(task)
        let block = KadoSchemaV8.ScheduleBlockRecord(task: task)
        context.insert(block)
        let session = KadoSchemaV8.WorkSessionRecord(startedAt: .now, task: task, scheduleBlock: block)
        context.insert(session)
        try context.save()

        context.delete(block)
        try context.save()
        let kept = try context.fetch(FetchDescriptor<KadoSchemaV8.WorkSessionRecord>())
        #expect(kept.count == 1)
        #expect(kept.first?.scheduleBlock == nil)

        context.delete(task)
        try context.save()
        #expect(try context.fetchCount(FetchDescriptor<KadoSchemaV8.WorkSessionRecord>()) == 0)
    }

    @Test("V7 to V8 keeps habits, tasks and blocks and accepts work sessions")
    func v7ToV8Migration() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("sessions-migration-\(UUID().uuidString).store")
        defer {
            for suffix in ["", "-wal", "-shm"] {
                try? FileManager.default.removeItem(atPath: url.path + suffix)
            }
        }
        let habitID = UUID()
        let taskID = UUID()
        let blockID = UUID()
        do {
            let schema = Schema(versionedSchema: KadoSchemaV7.self)
            let store = try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, url: url))
            let habit = KadoSchemaV7.HabitRecord(id: habitID, name: "Read")
            let task = KadoSchemaV7.TaskRecord(id: taskID, title: "Research")
            store.mainContext.insert(habit)
            store.mainContext.insert(task)
            store.mainContext.insert(KadoSchemaV7.ScheduleBlockRecord(id: blockID, task: task))
            try store.mainContext.save()
        }
        let schema = Schema(versionedSchema: KadoSchemaV8.self)
        let store = try ModelContainer(
            for: schema,
            migrationPlan: KadoMigrationPlan.self,
            configurations: ModelConfiguration(schema: schema, url: url)
        )
        let context = store.mainContext
        let task = try #require(context.fetch(FetchDescriptor<KadoSchemaV8.TaskRecord>()).first)
        #expect(task.id == taskID)
        #expect(task.scheduleBlocks?.first?.id == blockID)
        #expect(task.workSessions?.isEmpty ?? true)
        let habit = try #require(context.fetch(FetchDescriptor<KadoSchemaV8.HabitRecord>()).first)
        #expect(habit.id == habitID)
        #expect(habit.workSessions?.isEmpty ?? true)
        let block = try #require(task.scheduleBlocks?.first)
        let session = KadoSchemaV8.WorkSessionRecord(startedAt: .now, task: task, scheduleBlock: block)
        context.insert(session)
        try context.save()
        #expect(task.workSessions?.count == 1)
        #expect(block.workSessions?.count == 1)
    }

    @Test("V8 to V9 keeps goals, tasks, habits and links, with no category set")
    func v8ToV9Migration() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("categories-migration-\(UUID().uuidString).store")
        defer {
            for suffix in ["", "-wal", "-shm"] {
                try? FileManager.default.removeItem(atPath: url.path + suffix)
            }
        }
        let goalID = UUID()
        let taskID = UUID()
        let habitID = UUID()
        let completionID = UUID()
        do {
            let schema = Schema(versionedSchema: KadoSchemaV8.self)
            let store = try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, url: url))
            let goal = KadoSchemaV8.GoalRecord(id: goalID, name: "Get into Cambridge")
            store.mainContext.insert(goal)
            let task = KadoSchemaV8.TaskRecord(id: taskID, title: "Contact professors", goal: goal)
            store.mainContext.insert(task)
            let habit = KadoSchemaV8.HabitRecord(id: habitID, name: "Read", goal: goal)
            store.mainContext.insert(habit)
            store.mainContext.insert(KadoSchemaV8.CompletionRecord(id: completionID, value: 3, note: "Chapter", habit: habit))
            try store.mainContext.save()
        }
        let schema = Schema(versionedSchema: KadoSchemaV9.self)
        let store = try ModelContainer(
            for: schema,
            migrationPlan: KadoMigrationPlan.self,
            configurations: ModelConfiguration(schema: schema, url: url)
        )
        let context = store.mainContext
        let goal = try #require(context.fetch(FetchDescriptor<KadoSchemaV9.GoalRecord>()).first)
        let task = try #require(context.fetch(FetchDescriptor<KadoSchemaV9.TaskRecord>()).first)
        let habit = try #require(context.fetch(FetchDescriptor<KadoSchemaV9.HabitRecord>()).first)
        #expect(goal.id == goalID)
        #expect(goal.name == "Get into Cambridge")
        #expect(task.id == taskID)
        #expect(task.title == "Contact professors")
        #expect(task.goal?.id == goalID)
        #expect(habit.id == habitID)
        #expect(habit.name == "Read")
        #expect(habit.goal?.id == goalID)
        #expect(Set(goal.tasks?.map(\.id) ?? []) == [taskID])
        #expect(Set(goal.habits?.map(\.id) ?? []) == [habitID])
        let completion = try #require(habit.completions?.first)
        #expect(completion.id == completionID)
        #expect(completion.value == 3.0)
        #expect(completion.note == "Chapter")
        #expect(goal.categoryRaw == "")
        #expect(task.categoryRaw == "")
        #expect(habit.categoryRaw == "")
        #expect(goal.category == nil)
        #expect(task.category == nil)
        #expect(habit.category == nil)

        goal.category = .study
        task.category = .work
        habit.category = .mind
        try context.save()
        let refetchedGoal = try #require(context.fetch(FetchDescriptor<KadoSchemaV9.GoalRecord>()).first)
        let refetchedTask = try #require(context.fetch(FetchDescriptor<KadoSchemaV9.TaskRecord>()).first)
        let refetchedHabit = try #require(context.fetch(FetchDescriptor<KadoSchemaV9.HabitRecord>()).first)
        #expect(refetchedGoal.category == .study)
        #expect(refetchedTask.category == .work)
        #expect(refetchedHabit.category == .mind)
        #expect(refetchedGoal.categoryRaw == "study")
        #expect(refetchedTask.categoryRaw == "work")
        #expect(refetchedHabit.categoryRaw == "mind")
    }

    @Test("Migration plan declares a lightweight stage for each version through V9")
    func migrationPlanShape() {
        #expect(KadoMigrationPlan.schemas.count == 9)
        #expect(KadoMigrationPlan.stages.count == 8)
    }

    @Test("In-memory ModelContainer constructs from the current (V9) schema")
    func containerBuildsFromPlan() throws {
        let schema = Schema(versionedSchema: KadoSchemaV9.self)
        let container = try ModelContainer(
            for: schema,
            migrationPlan: KadoMigrationPlan.self,
            configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        )
        let habit = HabitRecord(name: "Smoke")
        container.mainContext.insert(habit)
        try container.mainContext.save()
        let fetched = try container.mainContext.fetch(FetchDescriptor<HabitRecord>())
        #expect(fetched.count == 1)
    }

    @Test("Lightweight migration from V1 populates default color and icon")
    func v1ToV2Migration() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("migration-test-\(UUID().uuidString).store")
        defer { try? FileManager.default.removeItem(at: url) }

        // Step 1: open a V1 store at the temp URL and insert a habit.
        do {
            let schema = Schema(versionedSchema: KadoSchemaV1.self)
            let config = ModelConfiguration(schema: schema, url: url)
            let container = try ModelContainer(
                for: schema,
                migrationPlan: nil,
                configurations: config
            )
            let habit = KadoSchemaV1.HabitRecord(name: "Pre-migration habit")
            container.mainContext.insert(habit)
            try container.mainContext.save()
        }

        // Step 2: reopen as V2 + migration plan; lightweight migration runs.
        let schema = Schema(versionedSchema: KadoSchemaV2.self)
        let config = ModelConfiguration(schema: schema, url: url)
        let container = try ModelContainer(
            for: schema,
            migrationPlan: KadoMigrationPlan.self,
            configurations: config
        )
        let habits = try container.mainContext.fetch(FetchDescriptor<KadoSchemaV2.HabitRecord>())
        #expect(habits.count == 1)
        let habit = try #require(habits.first)
        #expect(habit.name == "Pre-migration habit")
        #expect(habit.color == .blue)
        #expect(habit.icon == HabitIcon.default)
    }

    @Test("Lightweight migration from V2 populates default reminder fields")
    func v2ToV3Migration() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("migration-test-\(UUID().uuidString).store")
        defer { try? FileManager.default.removeItem(at: url) }

        // Step 1: seed a V2 store.
        do {
            let schema = Schema(versionedSchema: KadoSchemaV2.self)
            let config = ModelConfiguration(schema: schema, url: url)
            let container = try ModelContainer(
                for: schema,
                migrationPlan: nil,
                configurations: config
            )
            let habit = KadoSchemaV2.HabitRecord(name: "V2 habit", color: .orange)
            container.mainContext.insert(habit)
            try container.mainContext.save()
        }

        // Step 2: reopen as V3; lightweight stage fills reminder defaults.
        let schema = Schema(versionedSchema: KadoSchemaV3.self)
        let config = ModelConfiguration(schema: schema, url: url)
        let container = try ModelContainer(
            for: schema,
            migrationPlan: KadoMigrationPlan.self,
            configurations: config
        )
        let habits = try container.mainContext.fetch(FetchDescriptor<KadoSchemaV3.HabitRecord>())
        #expect(habits.count == 1)
        let habit = try #require(habits.first)
        #expect(habit.name == "V2 habit")
        #expect(habit.color == .orange)
        #expect(habit.remindersEnabled == false)
        #expect(habit.reminderHour == 9)
        #expect(habit.reminderMinute == 0)
    }

    @Test("Lightweight migration from V3 populates default sortOrder")
    func v3ToV4Migration() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("migration-test-\(UUID().uuidString).store")
        defer { try? FileManager.default.removeItem(at: url) }

        // Step 1: seed a V3 store.
        do {
            let schema = Schema(versionedSchema: KadoSchemaV3.self)
            let config = ModelConfiguration(schema: schema, url: url)
            let container = try ModelContainer(
                for: schema,
                migrationPlan: nil,
                configurations: config
            )
            let habit = KadoSchemaV3.HabitRecord(name: "V3 habit", color: .green)
            container.mainContext.insert(habit)
            try container.mainContext.save()
        }

        // Step 2: reopen as V4; lightweight stage fills sortOrder default.
        let schema = Schema(versionedSchema: KadoSchemaV4.self)
        let config = ModelConfiguration(schema: schema, url: url)
        let container = try ModelContainer(
            for: schema,
            migrationPlan: KadoMigrationPlan.self,
            configurations: config
        )
        let habits = try container.mainContext.fetch(FetchDescriptor<KadoSchemaV4.HabitRecord>())
        #expect(habits.count == 1)
        let habit = try #require(habits.first)
        #expect(habit.name == "V3 habit")
        #expect(habit.color == .green)
        #expect(habit.sortOrder == 0)
    }

    @Test("V4 to V5 preserves habits and completion history and accepts planning records")
    func v4ToV5Migration() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("planning-migration-\(UUID().uuidString).store")
        defer {
            for suffix in ["", "-wal", "-shm"] {
                try? FileManager.default.removeItem(atPath: url.path + suffix)
            }
        }
        let habitID = UUID()
        let completionID = UUID()
        do {
            let schema = Schema(versionedSchema: KadoSchemaV4.self)
            let store = try ModelContainer(
                for: schema,
                configurations: ModelConfiguration(schema: schema, url: url)
            )
            let habit = KadoSchemaV4.HabitRecord(id: habitID, name: "Existing habit", sortOrder: 9)
            store.mainContext.insert(habit)
            store.mainContext.insert(KadoSchemaV4.CompletionRecord(
                id: completionID, value: 42, note: "History", habit: habit
            ))
            try store.mainContext.save()
        }
        let schema = Schema(versionedSchema: KadoSchemaV5.self)
        let store = try ModelContainer(
            for: schema,
            migrationPlan: KadoMigrationPlan.self,
            configurations: ModelConfiguration(schema: schema, url: url)
        )
        let habit = try #require(store.mainContext.fetch(FetchDescriptor<KadoSchemaV5.HabitRecord>()).first)
        #expect(habit.id == habitID)
        #expect(habit.name == "Existing habit")
        #expect(habit.sortOrder == 9)
        #expect(habit.scheduleBlocks?.isEmpty ?? true)
        let completion = try #require(habit.completions?.first)
        #expect(completion.id == completionID)
        #expect(completion.value == 42)
        #expect(completion.note == "History")
        #expect(try store.mainContext.fetchCount(FetchDescriptor<KadoSchemaV5.TaskRecord>()) == 0)
        #expect(try store.mainContext.fetchCount(FetchDescriptor<KadoSchemaV5.ScheduleBlockRecord>()) == 0)
        let task = KadoSchemaV5.TaskRecord(title: "New task")
        store.mainContext.insert(task)
        store.mainContext.insert(KadoSchemaV5.ScheduleBlockRecord(task: task))
        try store.mainContext.save()
        #expect(try store.mainContext.fetchCount(FetchDescriptor<KadoSchemaV5.TaskRecord>()) == 1)
        #expect(task.scheduleBlocks?.count == 1)
    }
}
