import Foundation
import Testing
@testable import KadoCore

@Suite("History builder")
struct HistoryBuilderTests {
    typealias T = InsightsTestSupport

    private func days(
        _ input: InsightsInput,
        _ query: HistoryQuery = HistoryQuery(),
        startHour: Int = 0
    ) -> [HistoryDay] {
        HistoryBuilder.days(
            input: input,
            query: query,
            calendar: T.calendar,
            dayBoundary: DayBoundary(calendar: T.calendar, startHour: startHour)
        )
    }

    @Test("Nothing done, no days")
    func empty() {
        #expect(days(InsightsInput()).isEmpty)
        #expect(days(InsightsInput(tasks: [T.task(dueOffset: -1)])).isEmpty)
    }

    @Test("Completed tasks and habit records group by day, newest day first")
    func groupsByDay() {
        let input = InsightsInput(
            habits: [T.habit("Read", doneOffsets: [0, -2])],
            tasks: [T.task("Email", completedOffset: 0), T.task("Open"), T.task("Bills", completedOffset: -5)]
        )
        let result = days(input)
        #expect(result.map(\.day) == [T.day(0), T.day(-2), T.day(-5)])
        #expect(result[0].tasksDone == 1)
        #expect(result[0].habitsDone == 1)
        #expect(result[1].entries.map(\.title) == ["Read"])
        #expect(result[2].entries.map(\.title) == ["Bills"])
    }

    @Test("Quiet days count the empty days between two shown days")
    func quietDays() {
        let input = InsightsInput(tasks: [
            T.task(completedOffset: 0), T.task(completedOffset: -1), T.task(completedOffset: -5),
        ])
        #expect(days(input).map(\.quietDaysBefore) == [0, 0, 3])
        let oldest = days(input, HistoryQuery(dayOrder: .oldestFirst))
        #expect(oldest.map(\.day) == [T.day(-5), T.day(-1), T.day(0)])
        #expect(oldest.map(\.quietDaysBefore) == [0, 3, 0])
    }

    @Test("Zero-value records, cancelled imports and open sessions are skipped")
    func skipped() {
        let taskID = UUID()
        var open = T.session(offset: 0, minutes: 30, taskID: taskID)
        open.session.endedAt = nil
        let input = InsightsInput(
            habits: [T.habit(doneOffsets: [0], value: 0)],
            tasks: [T.task(id: taskID), T.task(completedOffset: 0, isCancelled: true)],
            sessions: [open]
        )
        #expect(days(input).isEmpty)
    }

    @Test("Session time joins the task completed that day, else becomes a focus entry")
    func sessions() throws {
        let doneID = UUID()
        let openID = UUID()
        let input = InsightsInput(
            tasks: [T.task("Done", id: doneID, completedOffset: 0), T.task("Open", id: openID)],
            sessions: [
                T.session(offset: 0, minutes: 30, taskID: doneID),
                T.session(offset: 0, hour: 14, minutes: 15, taskID: doneID),
                T.session(offset: -1, minutes: 45, taskID: openID),
                T.session(offset: -1, hour: 15, minutes: 15, taskID: openID),
            ]
        )
        let result = days(input)
        #expect(result.count == 2)
        let done = try #require(result[0].entries.first)
        #expect(done.item == .task(id: doneID))
        #expect(done.trackedSeconds == 45.0 * 60)
        let focus = try #require(result[1].entries.first)
        #expect(result[1].entries.count == 1)
        #expect(focus.item == .focus(taskID: openID, habitID: nil))
        #expect(focus.trackedSeconds == 60.0 * 60)
        #expect(focus.time == T.time(-1, 10))
        #expect(result[1].tasksDone == 0)
        #expect(result[1].trackedSeconds == 60.0 * 60)
    }

    @Test("Sessions use the logical day, tasks the civil day")
    func sessionDay() {
        let taskID = UUID()
        let input = InsightsInput(
            tasks: [T.task(id: taskID)],
            sessions: [T.session(offset: 0, hour: 2, minutes: 30, taskID: taskID)]
        )
        #expect(days(input, startHour: 4).map(\.day) == [T.day(-1)])
        #expect(days(input).map(\.day) == [T.day(0)])
    }

    @Test("Habit sessions join the habit's record that day")
    func habitSession() {
        let habitID = UUID()
        let input = InsightsInput(
            habits: [T.habit("Run", id: habitID, doneOffsets: [0])],
            sessions: [T.session(offset: 0, minutes: 20, habitID: habitID)]
        )
        let entries = days(input)[0].entries
        #expect(entries.count == 1)
        #expect(entries[0].trackedSeconds == 20.0 * 60)
        #expect(entries[0].habitIcon == "circle")
    }

    @Test("A negative habit's record is a slip, not a habit done")
    func slips() {
        let input = InsightsInput(habits: [T.habit("Smoke", type: .negative, doneOffsets: [0])])
        let day = days(input)[0]
        #expect(day.habitsDone == 0)
        #expect(day.slips == 1)
        #expect(day.entries[0].isSlip)
    }

    @Test("Kind, category and search filters narrow the entries and drop empty days")
    func filters() {
        let goalID = UUID()
        let input = InsightsInput(
            habits: [T.habit("Read", category: .study, doneOffsets: [0])],
            tasks: [
                T.task("Café run", category: .errands, completedOffset: 0),
                T.task("Email professor", category: .study, completedOffset: -1, goalID: goalID),
            ],
            goals: [InsightsGoal(id: goalID, name: "Get into Cambridge", category: .study, createdAt: T.day(-30))]
        )
        #expect(days(input, HistoryQuery(kind: .tasks)).flatMap(\.entries).map(\.title) == ["Café run", "Email professor"])
        #expect(days(input, HistoryQuery(kind: .habits)).flatMap(\.entries).map(\.title) == ["Read"])
        #expect(days(input, HistoryQuery(categories: [.study])).map(\.day) == [T.day(0), T.day(-1)])
        #expect(days(input, HistoryQuery(categories: [.errands])).map(\.day) == [T.day(0)])
        // Case and accent insensitive; goal names match too.
        #expect(days(input, HistoryQuery(search: "CAFE")).flatMap(\.entries).map(\.title) == ["Café run"])
        #expect(days(input, HistoryQuery(search: "cambridge")).flatMap(\.entries).map(\.title) == ["Email professor"])
        #expect(days(input, HistoryQuery(search: "  ")).count == 2)
        #expect(HistoryQuery(search: " ").isFiltered == false)
        #expect(HistoryQuery(kind: .tasks).isFiltered)
    }

    @Test("Items sort by time, category or name")
    func itemOrder() {
        let morning = InsightsTask(id: UUID(), title: "Zebra", category: .work, createdAt: T.day(-3), completedAt: T.time(0, 8))
        let evening = InsightsTask(id: UUID(), title: "Apple", category: .home, createdAt: T.day(-3), completedAt: T.time(0, 20))
        let noon = InsightsTask(id: UUID(), title: "mango", category: .study, createdAt: T.day(-3), completedAt: T.time(0, 12))
        let input = InsightsInput(tasks: [morning, evening, noon])
        func titles(_ query: HistoryQuery) -> [String] { days(input, query)[0].entries.map(\.title) }

        #expect(titles(HistoryQuery(itemOrder: .time)) == ["Apple", "mango", "Zebra"])
        #expect(titles(HistoryQuery(dayOrder: .oldestFirst, itemOrder: .time)) == ["Zebra", "mango", "Apple"])
        // Category order: work, study, …, home.
        #expect(titles(HistoryQuery(itemOrder: .category)) == ["Zebra", "mango", "Apple"])
        #expect(titles(HistoryQuery(itemOrder: .name)) == ["Apple", "mango", "Zebra"])
    }

    @Test("Goal names reach task and habit entries")
    func goalNames() {
        let goalID = UUID()
        var habit = T.habit("Read", doneOffsets: [0])
        habit.habit.goalID = goalID
        let input = InsightsInput(
            habits: [habit],
            tasks: [T.task("Apply", completedOffset: 0, goalID: goalID)],
            goals: [InsightsGoal(id: goalID, name: "Cambridge", category: .study, createdAt: T.day(-30))]
        )
        #expect(days(input)[0].entries.allSatisfy { $0.goalName == "Cambridge" })
    }

    @Test("Quiet days stay right across a day that starts at 01:00")
    func quietDaysAcrossDST() {
        let calendar = TestCalendar.havana
        let first = calendar.startOfDay(for: calendar.date(from: DateComponents(year: 2026, month: 3, day: 6, hour: 12))!)
        let second = calendar.startOfDay(for: calendar.date(from: DateComponents(year: 2026, month: 3, day: 10, hour: 12))!)
        #expect(HistoryBuilder.quietDays(between: second, and: first, calendar: calendar) == 3)
    }
}
