import Foundation
import Testing
@testable import Kado

@Suite("TaskDaySections")
struct TaskDaySectionsTests {
    private let cal = TestCalendar.utc
    private var today: Date { cal.startOfDay(for: TestCalendar.referenceDate) }

    private func ids(_ items: [TaskListItem]) -> [String] { items.map(\.title) }

    @Test("Today keeps overdue, inbox and completed-today")
    func todaySections() {
        let items = [
            TaskListItem(title: "Overdue", dueDate: TestCalendar.day(-2)),
            TaskListItem(title: "Due", dueDate: TestCalendar.day(0)),
            TaskListItem(title: "Inbox"),
            TaskListItem(title: "Later", dueDate: TestCalendar.day(3)),
            TaskListItem(title: "Done", dueDate: TestCalendar.day(0), completedAt: TestCalendar.day(0)),
        ]
        let s = TaskDaySections.make(for: today, kind: .today, items: items, calendar: cal)
        #expect(ids(s.due) == ["Overdue", "Due"])
        #expect(ids(s.inbox) == ["Inbox"])
        #expect(ids(s.completed) == ["Done"])
    }

    @Test("Past day: completed that day, still-open due that day, no overdue, no inbox")
    func pastSections() {
        let day = TestCalendar.day(-2)
        let items = [
            TaskListItem(title: "Older", dueDate: TestCalendar.day(-5)),
            TaskListItem(title: "Missed", dueDate: day),
            TaskListItem(title: "Done then", completedAt: cal.date(byAdding: .hour, value: 2, to: day)),
            TaskListItem(title: "Inbox"),
        ]
        let s = TaskDaySections.make(for: day, kind: .past, items: items, calendar: cal)
        #expect(ids(s.due) == ["Missed"])
        #expect(ids(s.completed) == ["Done then"])
        #expect(s.inbox.isEmpty)
    }

    @Test("Future day: planned tasks, open and completed")
    func futureSections() {
        let day = TestCalendar.day(3)
        let items = [
            TaskListItem(title: "Plan", dueDate: day),
            TaskListItem(title: "Early", dueDate: day, completedAt: TestCalendar.day(0)),
            TaskListItem(title: "Other", dueDate: TestCalendar.day(4)),
        ]
        let s = TaskDaySections.make(for: day, kind: .future, items: items, calendar: cal)
        #expect(Set(ids(s.due)) == ["Plan", "Early"])
        #expect(s.completed.isEmpty && s.inbox.isEmpty)
    }

    @Test("A block across midnight belongs to both days")
    func acrossMidnight() {
        let d1 = TestCalendar.day(2), d2 = TestCalendar.day(3)
        let block = TaskScheduleItem(plannedDay: d1,
                                     startAt: cal.date(byAdding: .hour, value: 11, to: d1),   // 23:00 (reference is 12:00)
                                     endAt: cal.date(byAdding: .hour, value: 13, to: d1))     // 01:00 next day
        let item = TaskListItem(title: "Night", schedules: [block])
        #expect(ids(TaskDaySections.make(for: d1, kind: .future, items: [item], calendar: cal).due) == ["Night"])
        #expect(ids(TaskDaySections.make(for: d2, kind: .future, items: [item], calendar: cal).due) == ["Night"])
    }
}
