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

    var isEmpty: Bool { due.isEmpty && inbox.isEmpty && completed.isEmpty }

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
            return TaskDaySections(due: sortedByPlan(due, calendar: calendar), inbox: inbox, completed: completedOnDay)
        case .past:
            return TaskDaySections(due: sortedByPlan(pending.filter(onDay), on: start, calendar: calendar), completed: completedOnDay)
        case .future:
            return TaskDaySections(due: sortedByPlan(items.filter(onDay), on: start, calendar: calendar))
        }
    }

    /// Whether a task can land in any section `make` builds for `day`,
    /// read from fields that are cheap on a record. Lets Today skip
    /// building an item for each task completed on another day, which
    /// is most of them once Google sync has run for a while. A superset:
    /// `make` still decides, so it gets the same items it would pick
    /// from the full list, in the same order.
    static func mayInclude(
        completedAt: Date?,
        dueDate: Date?,
        hasSchedules: () -> Bool,
        on day: Date,
        kind: TodayDayKind,
        calendar: Calendar
    ) -> Bool {
        // Open tasks feed due, overdue and the inbox.
        guard let completedAt else { return true }
        let start = calendar.startOfDay(for: day)
        if calendar.isDate(completedAt, inSameDayAs: start) { return true }
        // A future day also lists tasks done early, on their due or
        // planned day.
        guard kind == .future else { return false }
        return dueDate.map { calendar.isDate($0, inSameDayAs: start) } == true || hasSchedules()
    }

    /// Due day, then start time, then title — the order Today always used.
    /// With `day` (past and future views) a multi-day task orders by its
    /// block on that day; today passes nil and keeps the first block.
    private static func sortedByPlan(_ items: [TaskListItem], on day: Date? = nil, calendar: Calendar) -> [TaskListItem] {
        func block(_ item: TaskListItem) -> TaskScheduleItem? {
            if let day, let match = item.schedules.first(where: { $0.belongs(to: day, calendar: calendar) }) {
                return match
            }
            return item.schedules.first
        }
        return items.sorted { lhs, rhs in
            let leftDate = lhs.dueDate ?? block(lhs)?.plannedDay ?? .distantFuture
            let rightDate = rhs.dueDate ?? block(rhs)?.plannedDay ?? .distantFuture
            if leftDate != rightDate { return leftDate < rightDate }
            let leftTime = block(lhs)?.startAt ?? .distantFuture
            let rightTime = block(rhs)?.startAt ?? .distantFuture
            return leftTime == rightTime
                ? lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
                : leftTime < rightTime
        }
    }
}
