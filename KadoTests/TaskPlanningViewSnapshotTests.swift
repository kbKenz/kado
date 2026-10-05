import Foundation
import KadoCore
import SwiftData
import Testing
@testable import Kado

@Suite("Task planning view snapshots")
@MainActor
struct TaskPlanningViewSnapshotTests {
    private let calendar = TestCalendar.utc

    @Test("Snapshots survive destruction of their managed records")
    func snapshotsAreValues() throws {
        let schema = Schema(versionedSchema: KadoSchemaV9.self)
        let container = try ModelContainer(
            for: schema, migrationPlan: KadoMigrationPlan.self,
            configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        )
        let context = container.mainContext
        let task = TaskRecord(title: "Meeting with Thomas", dueDate: TestCalendar.referenceDate,
                              completedAt: TestCalendar.referenceDate, externalEventID: "google-event")
        context.insert(task)
        let block = ScheduleBlockRecord(plannedDay: TestCalendar.referenceDate, task: task)
        context.insert(block)
        try context.save()
        let taskID = task.id
        let blockID = block.id
        let taskItem = TaskListItem(task)
        let calendarItem = CalendarBlockItem(block, on: TestCalendar.referenceDate, calendar: calendar)
        context.delete(task)
        try context.save()

        #expect(taskItem.id == taskID)
        #expect(taskItem.title == "Meeting with Thomas")
        #expect(taskItem.isComplete)
        #expect(taskItem.isFromGoogle)
        #expect(taskItem.schedules.first?.id == blockID)
        #expect(calendarItem.id == blockID)
        #expect(calendarItem.task?.id == taskID)
        #expect(calendarItem.isComplete)
    }

    @Test("Task and goal list items carry the stored category, or nil")
    func listItemsCarryCategory() throws {
        let schema = Schema(versionedSchema: KadoSchemaV9.self)
        let container = try ModelContainer(
            for: schema,
            configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        )
        let context = container.mainContext
        let goal = GoalRecord(name: "Get into Cambridge", category: .study)
        let task = TaskRecord(title: "Contact professors", goal: goal, category: .work)
        let plain = TaskRecord(title: "No category")
        context.insert(goal)
        context.insert(task)
        context.insert(plain)
        try context.save()

        #expect(TaskListItem(task).category == .work)
        #expect(TaskListItem(plain).category == nil)
        #expect(GoalListItem(goal).category == .study)
        #expect(TaskListItem(title: "Direct").category == nil)
        #expect(GoalListItem(name: "Direct").category == nil)
    }

    @Test("A task row resolves its category as Insights does: stored, then the goal's, then the title")
    func taskResolvesCategory() throws {
        let schema = Schema(versionedSchema: KadoSchemaV9.self)
        let container = try ModelContainer(
            for: schema,
            configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        )
        let context = container.mainContext
        let goal = GoalRecord(name: "Get into Cambridge", category: .study)
        let uncategorizedGoal = GoalRecord(name: "Run a marathon")
        let stored = TaskRecord(title: "Contact professors", goal: goal, category: .work)
        let fromGoal = TaskRecord(title: "Pay the deposit", goal: goal)
        let fromTitle = TaskRecord(title: "Pay the deposit", goal: uncategorizedGoal)
        let unknown = TaskRecord(title: "Something else")
        [goal, uncategorizedGoal].forEach(context.insert)
        [stored, fromGoal, fromTitle, unknown].forEach(context.insert)
        try context.save()

        #expect(TaskListItem(stored).resolvedCategory == .work)
        #expect(TaskListItem(fromGoal).goalCategory == .study)
        #expect(TaskListItem(fromGoal).resolvedCategory == .study)
        // Only a goal's stored category passes down; its name is not guessed for the task.
        #expect(TaskListItem(fromTitle).goalCategory == nil)
        #expect(TaskListItem(fromTitle).resolvedCategory == .money)
        #expect(TaskListItem(unknown).resolvedCategory == .other)
    }

    @Test("A goal row resolves its category from what is stored, then from its name")
    func goalResolvesCategory() {
        #expect(GoalListItem(name: "Run a marathon", category: .health).resolvedCategory == .health)
        #expect(GoalListItem(name: "Run a marathon").resolvedCategory == .fitness)
        #expect(GoalListItem(name: "Be more present").resolvedCategory == .other)
    }

    @Test("A timed overnight block overlaps both civil days")
    func overnightMembership() {
        let start = TestCalendar.instant(calendar, 2026, 4, 13, 22)
        let end = TestCalendar.instant(calendar, 2026, 4, 14, 8)
        let item = TaskScheduleItem(plannedDay: start, startAt: start, endAt: end)
        #expect(item.belongs(to: TestCalendar.instant(calendar, 2026, 4, 13), calendar: calendar))
        #expect(item.belongs(to: TestCalendar.instant(calendar, 2026, 4, 14), calendar: calendar))
        #expect(!item.belongs(to: TestCalendar.instant(calendar, 2026, 4, 15), calendar: calendar))
    }

    @Test("An end at midnight does not occupy the following day")
    func exclusiveEnd() {
        let start = TestCalendar.instant(calendar, 2026, 4, 13, 22)
        let end = TestCalendar.instant(calendar, 2026, 4, 14)
        let item = TaskScheduleItem(plannedDay: start, startAt: start, endAt: end)
        #expect(item.belongs(to: start, calendar: calendar))
        #expect(!item.belongs(to: end, calendar: calendar))
    }

    @Test("An independent end or start retains its selected civil day", arguments: [true, false])
    func independentTimeMembership(hasStart: Bool) {
        let day = TestCalendar.referenceDate
        let clock = TestCalendar.instant(calendar, 2026, 4, 13, 9)
        let item = TaskScheduleItem(plannedDay: day, startAt: hasStart ? clock : nil, endAt: hasStart ? nil : clock)
        #expect(item.belongs(to: day, calendar: calendar))
        #expect(!item.belongs(to: TestCalendar.day(1), calendar: calendar))
    }
}
