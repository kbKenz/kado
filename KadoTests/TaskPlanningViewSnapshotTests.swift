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
        let schema = Schema(versionedSchema: KadoSchemaV7.self)
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
