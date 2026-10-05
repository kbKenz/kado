import Foundation
@testable import KadoCore

/// Builders for Insights calculator tests. Everything is pinned to
/// `TestCalendar.utc` unless a test passes another calendar, and
/// "today" is the start of `TestCalendar.referenceDate` (Monday
/// 2026-04-13) unless a test passes another day.
enum InsightsTestSupport {
    static let calendar = TestCalendar.utc

    /// Midnight of the reference day, `offset` days away.
    static func day(_ offset: Int, calendar: Calendar = calendar) -> Date {
        let today = calendar.startOfDay(for: TestCalendar.referenceDate)
        return calendar.startOfDay(for: calendar.date(byAdding: .day, value: offset, to: today)!)
    }

    /// An instant on the day `offset` days from the reference day, at
    /// `hour:minute` wall-clock time in `calendar`.
    static func time(_ offset: Int, _ hour: Int, _ minute: Int = 0, calendar: Calendar = calendar) -> Date {
        calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day(offset, calendar: calendar))!
    }

    static func context(
        period: InsightsPeriod = .week,
        today: Date? = nil,
        now: Date? = nil,
        calendar: Calendar = calendar,
        startHour: Int = 0
    ) -> InsightsContext {
        let todayValue = today ?? day(0, calendar: calendar)
        return InsightsContext(
            period: period,
            now: now ?? calendar.date(bySettingHour: 18, minute: 0, second: 0, of: todayValue)!,
            today: todayValue,
            calendar: calendar,
            dayBoundary: DayBoundary(calendar: calendar, startHour: startHour),
            frequencyEvaluator: DefaultFrequencyEvaluator(calendar: calendar),
            streakCalculator: DefaultStreakCalculator(calendar: calendar),
            scoreCalculator: DefaultHabitScoreCalculator(calendar: calendar)
        )
    }

    /// A habit created `createdDaysAgo` days before the reference day,
    /// with one completion per entry of `doneOffsets` (day offsets from
    /// the reference day, value `value`).
    static func habit(
        _ name: String = "Habit",
        id: UUID = UUID(),
        frequency: Frequency = .daily,
        type: HabitType = .binary,
        category: ItemCategory = .other,
        createdDaysAgo: Int = 60,
        archivedOffset: Int? = nil,
        doneOffsets: [Int] = [],
        value: Double = 1,
        color: HabitColor = .blue,
        icon: String = "circle",
        calendar: Calendar = calendar
    ) -> InsightsHabit {
        let model = Habit(
            id: id,
            name: name,
            frequency: frequency,
            type: type,
            createdAt: day(-createdDaysAgo, calendar: calendar),
            archivedAt: archivedOffset.map { day($0, calendar: calendar) },
            color: color,
            icon: icon
        )
        let completions = doneOffsets.map { offset in
            Completion(habitID: id, date: time(offset, 9, calendar: calendar), value: value)
        }
        return InsightsHabit(habit: model, category: category, completions: completions)
    }

    static func task(
        _ title: String = "Task",
        id: UUID = UUID(),
        category: ItemCategory = .other,
        createdDaysAgo: Int = 30,
        completedOffset: Int? = nil,
        plannedOffsets: [Int] = [],
        dueOffset: Int? = nil,
        archivedOffset: Int? = nil,
        goalID: UUID? = nil,
        isCancelled: Bool = false,
        calendar: Calendar = calendar
    ) -> InsightsTask {
        InsightsTask(
            id: id,
            title: title,
            category: category,
            createdAt: time(-createdDaysAgo, 8, calendar: calendar),
            completedAt: completedOffset.map { time($0, 17, calendar: calendar) },
            archivedAt: archivedOffset.map { time($0, 20, calendar: calendar) },
            dueDay: dueOffset.map { day($0, calendar: calendar) },
            plannedDays: plannedOffsets.sorted().map { day($0, calendar: calendar) },
            goalID: goalID,
            isCancelled: isCancelled
        )
    }

    /// A closed session that starts at `hour:minute` on the day
    /// `offset` days from the reference day and lasts `minutes`.
    static func session(
        offset: Int,
        hour: Int = 10,
        minute: Int = 0,
        minutes: Double,
        category: ItemCategory = .other,
        taskID: UUID? = nil,
        habitID: UUID? = nil,
        plannedMinutes: Double? = nil,
        calendar: Calendar = calendar
    ) -> InsightsSession {
        let start = time(offset, hour, minute, calendar: calendar)
        let end = start.addingTimeInterval(minutes * 60)
        return InsightsSession(
            id: UUID(),
            session: WorkSession(startedAt: start, endedAt: end),
            category: category,
            taskID: taskID,
            habitID: habitID,
            plannedRange: plannedMinutes.map { DateInterval(start: start, duration: $0 * 60) }
        )
    }

    static func report(_ input: InsightsInput, _ context: InsightsContext = context()) -> InsightsReport {
        InsightsCalculator().report(input: input, context: context)
    }

    static func scope(_ input: InsightsInput, _ context: InsightsContext = context()) -> InsightsScope {
        InsightsScope(input: input, context: context)
    }
}
