import Foundation

/// The task sections Today shows for one day.
///
/// - today: due and overdue, the inbox, and tasks completed today.
/// - past: tasks completed that day, then tasks due or scheduled that
///   day that are still open. Overdue tasks from earlier days show only
///   on today, as before.
/// - future: tasks due or scheduled that day, open and completed, so a
///   task completed early stays on its day with a tick.
///
/// Task days are civil days (as the Calendar tab); callers pass a civil
/// midnight for `day`.
struct TaskDaySections {
    var due: [TaskListItem] = []
    var inbox: [TaskListItem] = []
    var completed: [TaskListItem] = []

    static func make(for day: Date, kind: TodayDayKind, items: [TaskListItem], calendar: Calendar) -> TaskDaySections {
        let start = calendar.startOfDay(for: day)
        let pending = items.filter { !$0.isComplete }
        let onDay: (TaskListItem) -> Bool = { item in
            item.dueDate.map { calendar.isDate($0, inSameDayAs: start) } == true
                || item.schedules.contains { $0.belongs(to: start, calendar: calendar) }
        }
        let completedOnDay = items.filter { item in
            item.completedAt.map { calendar.isDate($0, inSameDayAs: start) } == true
        }.sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }

        switch kind {
        case .today:
            let due = pending.filter { item in
                item.dueDate.map { calendar.startOfDay(for: $0) <= start } == true
                    || item.schedules.contains { $0.belongs(to: start, calendar: calendar) }
            }
            let inbox = pending.filter { $0.dueDate == nil && $0.schedules.isEmpty }
            return TaskDaySections(due: sortedByPlan(due), inbox: inbox, completed: completedOnDay)
        case .past:
            return TaskDaySections(due: sortedByPlan(pending.filter(onDay)), completed: completedOnDay)
        case .future:
            return TaskDaySections(due: sortedByPlan(items.filter(onDay)))
        }
    }

    /// Due day, then start time, then title — the order Today always used.
    private static func sortedByPlan(_ items: [TaskListItem]) -> [TaskListItem] {
        items.sorted { lhs, rhs in
            let leftDate = lhs.dueDate ?? lhs.schedules.first?.plannedDay ?? .distantFuture
            let rightDate = rhs.dueDate ?? rhs.schedules.first?.plannedDay ?? .distantFuture
            if leftDate != rightDate { return leftDate < rightDate }
            let leftTime = lhs.schedules.first?.startAt ?? .distantFuture
            let rightTime = rhs.schedules.first?.startAt ?? .distantFuture
            return leftTime == rightTime
                ? lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
                : leftTime < rightTime
        }
    }
}
