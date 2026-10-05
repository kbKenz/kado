#if DEBUG
import Foundation
import SwiftData
import KadoCore

extension UITestSupport.Argument {
    /// Insert goals and tasks across the categories, one task block
    /// current at launch and one later, so the category icons on Today,
    /// the Calendar, Goals and Now can be checked and photographed.
    /// The titles are English, like the runs that pass this.
    static let seedPlanner = "-uiTestSeedPlanner"
}

extension UITestSupport {
    /// Inserts the planner `-uiTestSeedPlanner` asks for, once. On the
    /// mounted container's context, for the reason
    /// `seedProductionIfRequested` gives. Call it after the habit seed,
    /// so the first habit gets a block on the Calendar too.
    @MainActor
    static func seedPlannerIfRequested(using context: ModelContext) {
        guard isRunningUITests,
              ProcessInfo.processInfo.arguments.contains(Argument.seedPlanner)
        else { return }
        let count = (try? context.fetchCount(FetchDescriptor<GoalRecord>())) ?? 0
        guard count == 0 else { return }
        insertPlanner(into: context, now: .now, calendar: .current)
        try? context.save()
    }

    /// Stored, goal-given and guessed categories, plus one with no
    /// match (Other), a long title and a completed task.
    @MainActor
    private static func insertPlanner(into context: ModelContext, now: Date, calendar: Calendar) {
        let today = calendar.startOfDay(for: now)
        func at(_ hour: Int, _ minute: Int = 0) -> Date {
            calendar.date(bySettingHour: hour, minute: minute, second: 0, of: today) ?? today
        }
        let inTwoMonths = calendar.date(byAdding: .month, value: 2, to: today)

        let cambridge = GoalRecord(name: "Get into Cambridge", targetDate: inTwoMonths, category: .study)
        let marathon = GoalRecord(name: "Run a half marathon")
        let present = GoalRecord(name: "Be more present")
        let japanese = GoalRecord(name: "Learn conversational Japanese", status: .paused)
        [cambridge, marathon, present, japanese].forEach(context.insert)

        let professors = TaskRecord(title: "Contact professors at Cambridge", dueDate: today, goal: cambridge)
        let bill = TaskRecord(title: "Pay the electricity bill", dueDate: today)
        let meeting = TaskRecord(title: "Team meeting", dueDate: today, category: .work)
        let slides = TaskRecord(
            title: "Prepare the slides for Thursday's quarterly planning meeting with the whole team",
            dueDate: today
        )
        let grandma = TaskRecord(title: "Call grandma", dueDate: today)
        let groceries = TaskRecord(title: "Buy groceries")
        let weekend = TaskRecord(title: "Think about the weekend")
        let revise = TaskRecord(title: "Revise chemistry notes")
        let run = TaskRecord(title: "Morning run", dueDate: today, completedAt: now, goal: marathon)
        [professors, bill, meeting, slides, grandma, groceries, weekend, revise, run].forEach(context.insert)

        // Now suggests the current block and lists the later one as Up next.
        context.insert(ScheduleBlockRecord(
            plannedDay: today,
            startAt: now.addingTimeInterval(-10 * 60),
            endAt: now.addingTimeInterval(50 * 60),
            task: revise
        ))
        context.insert(ScheduleBlockRecord(
            plannedDay: today,
            startAt: now.addingTimeInterval(70 * 60),
            endAt: now.addingTimeInterval(85 * 60),
            task: bill
        ))
        // The Calendar: a fixed afternoon meeting and a habit's morning slot.
        context.insert(ScheduleBlockRecord(plannedDay: today, startAt: at(14), endAt: at(15), task: meeting))
        let habits = FetchDescriptor<HabitRecord>(sortBy: [SortDescriptor(\.sortOrder), SortDescriptor(\.createdAt)])
        if let habit = try? context.fetch(habits).first {
            context.insert(ScheduleBlockRecord(plannedDay: today, startAt: at(7, 30), endAt: at(8), habit: habit))
        }
    }
}
#endif
