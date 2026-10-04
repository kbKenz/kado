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
            TaskListItem(title: "Done then", dueDate: day, completedAt: cal.date(byAdding: .hour, value: 2, to: day)),
            TaskListItem(title: "Planned only", schedules: [TaskScheduleItem(plannedDay: day)]),
            TaskListItem(title: "Inbox"),
        ]
        let s = TaskDaySections.make(for: day, kind: .past, items: items, calendar: cal)
        #expect(Set(ids(s.due)) == ["Missed", "Planned only"])
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

    @Test("Planned order: timed blocks by start, then untimed by title")
    func planOrder() {
        let day = TestCalendar.day(3)
        func block(_ hours: Int) -> TaskScheduleItem {
            TaskScheduleItem(plannedDay: day,
                             startAt: cal.date(byAdding: .hour, value: hours, to: day),
                             endAt: cal.date(byAdding: .hour, value: hours + 1, to: day))
        }
        let items = [
            TaskListItem(title: "B", dueDate: day),
            TaskListItem(title: "Late", schedules: [block(2)]),
            TaskListItem(title: "A", dueDate: day),
            TaskListItem(title: "Early", schedules: [block(-4)]),
        ]
        for kind in [TodayDayKind.future, .past] {
            let s = TaskDaySections.make(for: day, kind: kind, items: items, calendar: cal)
            #expect(ids(s.due) == ["Early", "Late", "A", "B"])
        }
    }

    @Test("A multi-day task orders by its block on the shown day")
    func multiDayOrder() {
        let d2 = TestCalendar.day(2), d5 = TestCalendar.day(5)
        func block(_ day: Date, _ hours: Int) -> TaskScheduleItem {
            TaskScheduleItem(plannedDay: day,
                             startAt: cal.date(byAdding: .hour, value: hours, to: day),
                             endAt: cal.date(byAdding: .hour, value: hours + 1, to: day))
        }
        let multi = TaskListItem(title: "Multi", schedules: [block(d2, -4), block(d5, 6)])   // 08:00 and 18:00
        let single = TaskListItem(title: "Single", schedules: [block(d5, -3)])               // 09:00
        let s = TaskDaySections.make(for: d5, kind: .future, items: [multi, single], calendar: cal)
        #expect(ids(s.due) == ["Single", "Multi"])
    }
}
