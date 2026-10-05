import Foundation

/// A count of successes out of a count of chances.
nonisolated public struct InsightsRate: Hashable, Sendable {
    public var done: Int
    public var total: Int

    public init(done: Int, total: Int) {
        self.done = done
        self.total = total
    }

    public static let empty = InsightsRate(done: 0, total: 0)

    /// `done / total`, or `nil` when there was no chance at all.
    public var fraction: Double? {
        total > 0 ? Double(done) / Double(total) : nil
    }
}

/// A name with a count, such as a workout type or a habit's best streak.
nonisolated public struct InsightsNamedCount: Hashable, Sendable {
    public var name: String
    public var count: Int

    public init(name: String, count: Int) {
        self.name = name
        self.count = count
    }
}

/// Everything the Insights feed shows for one period. Pure values: the
/// views only format them.
nonisolated public struct InsightsReport: Hashable, Sendable {
    public var period: InsightsPeriod
    /// The logical days of the period, oldest first, ending with today.
    public var days: [Date]
    public var pulse: InsightsPulse
    /// Up to four plain-language facts, most interesting first.
    public var highlights: [InsightsHighlight]
    public var activity: InsightsActivity
    public var focus: InsightsFocus
    /// Categories with anything to show in the period, busiest first.
    public var categories: [InsightsCategoryRow]
    public var sleep: InsightsSleep
    public var movement: InsightsMovement
    /// Active (not archived) habits.
    public var habits: [InsightsHabitRow]
    public var tasks: InsightsTasks
    /// Active goals.
    public var goals: [InsightsGoalRow]
    public var rhythm: InsightsRhythm
    public var allTime: InsightsAllTime
    /// No habit, task or session exists at all: the feed shows its
    /// first-run state instead of empty cards.
    public var isEmpty: Bool

    public init(
        period: InsightsPeriod,
        days: [Date],
        pulse: InsightsPulse = .empty,
        highlights: [InsightsHighlight] = [],
        activity: InsightsActivity = .empty,
        focus: InsightsFocus = .empty,
        categories: [InsightsCategoryRow] = [],
        sleep: InsightsSleep = .empty,
        movement: InsightsMovement = .empty,
        habits: [InsightsHabitRow] = [],
        tasks: InsightsTasks = .empty,
        goals: [InsightsGoalRow] = [],
        rhythm: InsightsRhythm = .empty,
        allTime: InsightsAllTime = .empty,
        isEmpty: Bool = true
    ) {
        self.period = period
        self.days = days
        self.pulse = pulse
        self.highlights = highlights
        self.activity = activity
        self.focus = focus
        self.categories = categories
        self.sleep = sleep
        self.movement = movement
        self.habits = habits
        self.tasks = tasks
        self.goals = goals
        self.rhythm = rhythm
        self.allTime = allTime
        self.isEmpty = isEmpty
    }
}

// MARK: - Pulse

/// The three dials at the top of the feed. Each has the same rate for
/// the previous period, for the "▲ 6 pts" change.
nonisolated public struct InsightsPulse: Hashable, Sendable {
    /// Habits: due habit-days done / due habit-days (see
    /// `HabitDayOutcome`).
    public var consistency: InsightsRate
    public var previousConsistency: InsightsRate
    /// Tasks: done / (done + left undone) (see `InsightsTasks`).
    public var followThrough: InsightsRate
    public var previousFollowThrough: InsightsRate
    /// Days with any activity / days counted. Activity is a positive
    /// record on a non-negative habit, a task completed, or a session
    /// started. Days before the user's first record are not counted,
    /// and today is counted only once it is active.
    public var activeDays: InsightsRate
    public var previousActiveDays: InsightsRate

    public init(
        consistency: InsightsRate = .empty,
        previousConsistency: InsightsRate = .empty,
        followThrough: InsightsRate = .empty,
        previousFollowThrough: InsightsRate = .empty,
        activeDays: InsightsRate = .empty,
        previousActiveDays: InsightsRate = .empty
    ) {
        self.consistency = consistency
        self.previousConsistency = previousConsistency
        self.followThrough = followThrough
        self.previousFollowThrough = previousFollowThrough
        self.activeDays = activeDays
        self.previousActiveDays = previousActiveDays
    }

    public static let empty = InsightsPulse()
}

// MARK: - Highlights

/// Part of the day, by wall-clock start time.
nonisolated public enum InsightsPartOfDay: String, CaseIterable, Hashable, Sendable {
    /// 05:00 to 11:59.
    case morning
    /// 12:00 to 16:59.
    case afternoon
    /// 17:00 to 21:59.
    case evening
    /// 22:00 to 04:59.
    case night

    public static func of(hour: Int) -> InsightsPartOfDay {
        switch hour {
        case 5..<12: .morning
        case 12..<17: .afternoon
        case 17..<22: .evening
        default: .night
        }
    }
}

/// One plain-language fact. The view words it; the calculator picks it.
nonisolated public enum InsightsHighlight: Hashable, Sendable {
    /// A habit's current streak equals its best ever (at least 3).
    case streakRecord(habitName: String, days: Int)
    /// Habit consistency moved by at least 5 points against the previous
    /// period. Positive or negative.
    case consistencyChange(points: Int)
    /// The category whose tasks were most often left undone.
    case mostUndoneCategory(ItemCategory, undone: Int, total: Int)
    /// The category with the most focus time (at least 30 minutes).
    case topFocusCategory(ItemCategory, seconds: TimeInterval)
    /// Days in the period on which every due habit was done.
    case perfectDays(count: Int)
    /// Most focus time starts in this part of the day.
    case peakFocusTime(InsightsPartOfDay, share: Double)
    /// The weekday with the best habit consistency.
    case bestWeekday(Weekday, fraction: Double)
    /// A habit passed 10, 25, 50, 100, 250, 500 or 1000 days done during
    /// the period.
    case milestone(habitName: String, count: Int)
    /// The longest current streak across habits (at least 3).
    case longestStreak(habitName: String, days: Int)
    /// Total focus time in the period (at least one hour).
    case focusTotal(seconds: TimeInterval)
}

// MARK: - Activity

/// One cell of the activity heat map.
nonisolated public struct InsightsActivityDay: Hashable, Sendable, Identifiable {
    public var date: Date
    /// Share of the day's due habits that were done. `nil` when nothing
    /// was due (or the day is before the first record).
    public var habitFraction: Double?
    public var tasksDone: Int
    /// Seconds tracked in sessions that started this logical day.
    public var focusSeconds: TimeInterval
    /// `false` for the leading cells that only pad the first week.
    public var isInPeriod: Bool

    public var id: Date { date }

    public init(date: Date, habitFraction: Double? = nil, tasksDone: Int = 0, focusSeconds: TimeInterval = 0, isInPeriod: Bool = true) {
        self.date = date
        self.habitFraction = habitFraction
        self.tasksDone = tasksDone
        self.focusSeconds = focusSeconds
        self.isInPeriod = isInPeriod
    }
}

nonisolated public struct InsightsActivity: Hashable, Sendable {
    /// Whole weeks that cover the period: the first cell is the
    /// calendar's first weekday on or before the period's first day,
    /// the last cell is today (no future cells). Oldest first.
    public var days: [InsightsActivityDay]
    /// Days in the period on which at least one habit was due and every
    /// due habit was done.
    public var perfectDays: Int
    /// The longest run of consecutive perfect days in the period.
    public var longestPerfectRun: Int

    public init(days: [InsightsActivityDay] = [], perfectDays: Int = 0, longestPerfectRun: Int = 0) {
        self.days = days
        self.perfectDays = perfectDays
        self.longestPerfectRun = longestPerfectRun
    }

    public static let empty = InsightsActivity()
}

// MARK: - Focus

/// Tracked time in one bar of the focus chart.
nonisolated public struct InsightsFocusBucket: Hashable, Sendable, Identifiable {
    /// The day (week and month periods) or the first day of the month
    /// (year period).
    public var start: Date
    public var seconds: TimeInterval
    /// The same seconds split by category. Only categories with time.
    public var byCategory: [ItemCategory: TimeInterval]

    public var id: Date { start }

    public init(start: Date, seconds: TimeInterval = 0, byCategory: [ItemCategory: TimeInterval] = [:]) {
        self.start = start
        self.seconds = seconds
        self.byCategory = byCategory
    }
}

/// Tracked work sessions. A session belongs to the logical day it
/// started on; an open session counts up to now.
nonisolated public struct InsightsFocus: Hashable, Sendable {
    public var total: TimeInterval
    public var previousTotal: TimeInterval
    public var sessionCount: Int
    public var averageSession: TimeInterval?
    public var longestSession: TimeInterval?
    /// One per day (week, month) or per calendar month (year), oldest
    /// first, with zero buckets kept so the chart has no gaps.
    public var buckets: [InsightsFocusBucket]
    /// Tracked / planned over sessions linked to a timed block. 1.2
    /// means sessions ran 20% longer than planned. `nil` without such
    /// sessions.
    public var planRatio: Double?
    /// The user tracked at least one session, ever. When `false` the
    /// card explains how to start one.
    public var hasEverTracked: Bool

    public init(
        total: TimeInterval = 0,
        previousTotal: TimeInterval = 0,
        sessionCount: Int = 0,
        averageSession: TimeInterval? = nil,
        longestSession: TimeInterval? = nil,
        buckets: [InsightsFocusBucket] = [],
        planRatio: Double? = nil,
        hasEverTracked: Bool = false
    ) {
        self.total = total
        self.previousTotal = previousTotal
        self.sessionCount = sessionCount
        self.averageSession = averageSession
        self.longestSession = longestSession
        self.buckets = buckets
        self.planRatio = planRatio
        self.hasEverTracked = hasEverTracked
    }

    public static let empty = InsightsFocus()
}

// MARK: - Categories

/// What happened in one category during the period.
nonisolated public struct InsightsCategoryRow: Hashable, Sendable, Identifiable {
    public var category: ItemCategory
    public var focusSeconds: TimeInterval
    /// Due habit-days done / due, over this category's habits.
    public var habitConsistency: InsightsRate
    /// Days with a positive record, over this category's non-negative
    /// habits.
    public var habitTimesDone: Int
    public var tasksDone: Int
    public var tasksUndone: Int

    public var id: ItemCategory { category }

    public init(
        category: ItemCategory,
        focusSeconds: TimeInterval = 0,
        habitConsistency: InsightsRate = .empty,
        habitTimesDone: Int = 0,
        tasksDone: Int = 0,
        tasksUndone: Int = 0
    ) {
        self.category = category
        self.focusSeconds = focusSeconds
        self.habitConsistency = habitConsistency
        self.habitTimesDone = habitTimesDone
        self.tasksDone = tasksDone
        self.tasksUndone = tasksUndone
    }
}

// MARK: - Habits

/// A habit's consistency in the period, for the sleep and movement cards.
nonisolated public struct InsightsHabitConsistency: Hashable, Sendable, Identifiable {
    public var habitID: UUID
    public var name: String
    public var icon: String
    public var color: HabitColor
    public var rate: InsightsRate

    public var id: UUID { habitID }

    public init(habitID: UUID, name: String, icon: String, color: HabitColor, rate: InsightsRate) {
        self.habitID = habitID
        self.name = name
        self.icon = icon
        self.color = color
        self.rate = rate
    }
}

/// One active habit in the Habits card.
nonisolated public struct InsightsHabitRow: Hashable, Sendable, Identifiable {
    public var habitID: UUID
    public var name: String
    public var icon: String
    public var color: HabitColor
    public var category: ItemCategory
    public var type: HabitType
    /// Due days done / due days in the period.
    public var rate: InsightsRate
    /// Days with a positive record in the period. For a negative habit
    /// these are slips.
    public var timesDone: Int
    /// Sum of positive values in the period: units for a counter,
    /// seconds for a timer, 0 for binary and negative habits.
    public var amount: Double
    public var allTimeTimesDone: Int
    public var allTimeAmount: Double
    public var currentStreak: Int
    public var bestStreak: Int
    /// EMA score, 0...1, as of today.
    public var score: Double

    public var id: UUID { habitID }

    public init(
        habitID: UUID,
        name: String,
        icon: String,
        color: HabitColor,
        category: ItemCategory,
        type: HabitType,
        rate: InsightsRate = .empty,
        timesDone: Int = 0,
        amount: Double = 0,
        allTimeTimesDone: Int = 0,
        allTimeAmount: Double = 0,
        currentStreak: Int = 0,
        bestStreak: Int = 0,
        score: Double = 0
    ) {
        self.habitID = habitID
        self.name = name
        self.icon = icon
        self.color = color
        self.category = category
        self.type = type
        self.rate = rate
        self.timesDone = timesDone
        self.amount = amount
        self.allTimeTimesDone = allTimeTimesDone
        self.allTimeAmount = allTimeAmount
        self.currentStreak = currentStreak
        self.bestStreak = bestStreak
        self.score = score
    }
}

// MARK: - Sleep

/// One night of sleep from Apple Health.
nonisolated public struct InsightsNight: Hashable, Sendable, Identifiable {
    /// Civil midnight of the day the night ends on (the wake day).
    public var day: Date
    public var start: Date
    public var end: Date

    public var id: Date { day }
    public var duration: TimeInterval { end.timeIntervalSince(start) }

    public init(day: Date, start: Date, end: Date) {
        self.day = day
        self.start = start
        self.end = end
    }
}

nonisolated public struct InsightsSleep: Hashable, Sendable {
    public var isHealthConnected: Bool
    /// One per wake day in the period (the longest session of at least
    /// 2 hours that ends that day), oldest first.
    public var nights: [InsightsNight]
    public var averageDuration: TimeInterval?
    public var previousAverageDuration: TimeInterval?
    /// Nights of 7 hours or more / nights.
    public var nightsOverSevenHours: InsightsRate
    /// Nights whose bedtime is within 45 minutes of the median bedtime /
    /// nights. The "sleep consistency" figure.
    public var bedtimeConsistency: InsightsRate
    /// Median bedtime and wake time, in minutes after midnight (0..<1440).
    public var medianBedtimeMinutes: Int?
    public var medianWakeMinutes: Int?
    /// Active habits in the Sleep category, with their consistency.
    public var habits: [InsightsHabitConsistency]

    public init(
        isHealthConnected: Bool = false,
        nights: [InsightsNight] = [],
        averageDuration: TimeInterval? = nil,
        previousAverageDuration: TimeInterval? = nil,
        nightsOverSevenHours: InsightsRate = .empty,
        bedtimeConsistency: InsightsRate = .empty,
        medianBedtimeMinutes: Int? = nil,
        medianWakeMinutes: Int? = nil,
        habits: [InsightsHabitConsistency] = []
    ) {
        self.isHealthConnected = isHealthConnected
        self.nights = nights
        self.averageDuration = averageDuration
        self.previousAverageDuration = previousAverageDuration
        self.nightsOverSevenHours = nightsOverSevenHours
        self.bedtimeConsistency = bedtimeConsistency
        self.medianBedtimeMinutes = medianBedtimeMinutes
        self.medianWakeMinutes = medianWakeMinutes
        self.habits = habits
    }

    public static let empty = InsightsSleep()
}

// MARK: - Movement

nonisolated public struct InsightsMovement: Hashable, Sendable {
    public var isHealthConnected: Bool
    /// Apple Health workouts that started in the period.
    public var workoutCount: Int
    public var previousWorkoutCount: Int
    public var workoutTotal: TimeInterval
    public var averageWorkout: TimeInterval?
    /// The most frequent workout name and its count.
    public var topWorkout: InsightsNamedCount?
    /// Fitness-category days done (positive records on non-negative
    /// habits) plus fitness tasks completed, in the period.
    public var fitnessTimesDone: Int
    public var previousFitnessTimesDone: Int
    /// Timer seconds on fitness habits, plus sessions on fitness items
    /// that are not timer habits (a timer habit's session time is
    /// already in its completion value).
    public var fitnessTrackedTime: TimeInterval
    /// `fitnessTrackedTime` / the occurrences that carried time.
    public var averageFitnessTime: TimeInterval?
    /// Active habits in the Fitness category, with their consistency.
    public var habits: [InsightsHabitConsistency]

    public init(
        isHealthConnected: Bool = false,
        workoutCount: Int = 0,
        previousWorkoutCount: Int = 0,
        workoutTotal: TimeInterval = 0,
        averageWorkout: TimeInterval? = nil,
        topWorkout: InsightsNamedCount? = nil,
        fitnessTimesDone: Int = 0,
        previousFitnessTimesDone: Int = 0,
        fitnessTrackedTime: TimeInterval = 0,
        averageFitnessTime: TimeInterval? = nil,
        habits: [InsightsHabitConsistency] = []
    ) {
        self.isHealthConnected = isHealthConnected
        self.workoutCount = workoutCount
        self.previousWorkoutCount = previousWorkoutCount
        self.workoutTotal = workoutTotal
        self.averageWorkout = averageWorkout
        self.topWorkout = topWorkout
        self.fitnessTimesDone = fitnessTimesDone
        self.previousFitnessTimesDone = previousFitnessTimesDone
        self.fitnessTrackedTime = fitnessTrackedTime
        self.averageFitnessTime = averageFitnessTime
        self.habits = habits
    }

    public static let empty = InsightsMovement()
}

// MARK: - Tasks

nonisolated public struct InsightsCategoryUndone: Hashable, Sendable, Identifiable {
    public var category: ItemCategory
    public var undone: Int
    /// Done + undone.
    public var total: Int

    public var id: ItemCategory { category }

    public init(category: ItemCategory, undone: Int, total: Int) {
        self.category = category
        self.undone = undone
        self.total = total
    }
}

/// Tasks in the period. A task is **done** in the period when its
/// completion day (civil) is in it. It is **left undone** when it has
/// no completion and its target day (`InsightsTask.targetDay`) is in
/// the period and before today. Cancelled imports are skipped.
nonisolated public struct InsightsTasks: Hashable, Sendable {
    public var done: Int
    public var undone: Int
    public var previousDone: Int
    public var previousUndone: Int
    /// Among tasks done in the period that have a target day: done on
    /// or before it.
    public var onTime: InsightsRate
    /// Mean days from creation to completion (civil days, 0 for the
    /// same day), over tasks done in the period.
    public var averageDaysToFinish: Double?
    /// Categories with at least 2 tasks done or undone and at least 1
    /// undone, highest undone share first (ties: more undone, then
    /// category order). At most 3.
    public var undoneByCategory: [InsightsCategoryUndone]
    /// Open tasks (no completion, not archived) whose target day is
    /// before today, whatever the period.
    public var overdueOpen: Int

    public init(
        done: Int = 0,
        undone: Int = 0,
        previousDone: Int = 0,
        previousUndone: Int = 0,
        onTime: InsightsRate = .empty,
        averageDaysToFinish: Double? = nil,
        undoneByCategory: [InsightsCategoryUndone] = [],
        overdueOpen: Int = 0
    ) {
        self.done = done
        self.undone = undone
        self.previousDone = previousDone
        self.previousUndone = previousUndone
        self.onTime = onTime
        self.averageDaysToFinish = averageDaysToFinish
        self.undoneByCategory = undoneByCategory
        self.overdueOpen = overdueOpen
    }

    public static let empty = InsightsTasks()
}

// MARK: - Goals

nonisolated public enum InsightsGoalPace: String, Hashable, Sendable {
    case ahead
    case onTrack
    case behind
}

/// One active goal.
nonisolated public struct InsightsGoalRow: Hashable, Sendable, Identifiable {
    public var goalID: UUID
    public var name: String
    public var category: ItemCategory
    public var progress: Double?
    /// Linked tasks done, ever, and linked tasks in total (cancelled
    /// imports skipped).
    public var tasksDone: Int
    public var tasksTotal: Int
    public var tasksDoneInPeriod: Int
    /// Due habit-days done / due, over the goal's linked habits, in the
    /// period.
    public var habitConsistency: InsightsRate
    /// Progress against elapsed time. Needs a progress, a target date and
    /// a start (start date, else creation). `progress - elapsedShare`:
    /// at least +0.1 is ahead, at least -0.1 on track, else behind.
    public var pace: InsightsGoalPace?
    /// Civil days from today to the target date, 0 on the day. `nil`
    /// without a target date or after it.
    public var daysLeft: Int?

    public var id: UUID { goalID }

    public init(
        goalID: UUID,
        name: String,
        category: ItemCategory,
        progress: Double? = nil,
        tasksDone: Int = 0,
        tasksTotal: Int = 0,
        tasksDoneInPeriod: Int = 0,
        habitConsistency: InsightsRate = .empty,
        pace: InsightsGoalPace? = nil,
        daysLeft: Int? = nil
    ) {
        self.goalID = goalID
        self.name = name
        self.category = category
        self.progress = progress
        self.tasksDone = tasksDone
        self.tasksTotal = tasksTotal
        self.tasksDoneInPeriod = tasksDoneInPeriod
        self.habitConsistency = habitConsistency
        self.pace = pace
        self.daysLeft = daysLeft
    }
}

// MARK: - Rhythm

nonisolated public struct InsightsWeekdayRate: Hashable, Sendable, Identifiable {
    public var weekday: Weekday
    public var rate: InsightsRate

    public var id: Weekday { weekday }

    public init(weekday: Weekday, rate: InsightsRate) {
        self.weekday = weekday
        self.rate = rate
    }
}

nonisolated public struct InsightsPartOfDayFocus: Hashable, Sendable, Identifiable {
    public var part: InsightsPartOfDay
    public var seconds: TimeInterval

    public var id: InsightsPartOfDay { part }

    public init(part: InsightsPartOfDay, seconds: TimeInterval) {
        self.part = part
        self.seconds = seconds
    }
}

nonisolated public struct InsightsRhythm: Hashable, Sendable {
    /// Habit consistency per weekday in the period, starting with the
    /// calendar's first weekday. Always 7 entries.
    public var weekdays: [InsightsWeekdayRate]
    /// The weekday with the highest fraction among weekdays seen on at
    /// least 2 dates with at least 2 due habit-days. Ties go to the
    /// earlier weekday in the week. `nil` for the week period.
    public var bestWeekday: Weekday?
    /// Focus seconds by part of the day the session started in. Always
    /// 4 entries, in `InsightsPartOfDay.allCases` order.
    public var focusByPartOfDay: [InsightsPartOfDayFocus]
    /// The part with the most focus, when there are at least 3 sessions.
    public var peakPartOfDay: InsightsPartOfDay?

    public init(
        weekdays: [InsightsWeekdayRate] = [],
        bestWeekday: Weekday? = nil,
        focusByPartOfDay: [InsightsPartOfDayFocus] = [],
        peakPartOfDay: InsightsPartOfDay? = nil
    ) {
        self.weekdays = weekdays
        self.bestWeekday = bestWeekday
        self.focusByPartOfDay = focusByPartOfDay
        self.peakPartOfDay = peakPartOfDay
    }

    public static let empty = InsightsRhythm()
}

// MARK: - All time

nonisolated public struct InsightsAllTime: Hashable, Sendable {
    /// Civil midnight of the earliest record: a habit or task created,
    /// a completion, or a session.
    public var firstDay: Date?
    /// Days from `firstDay` to today, both included.
    public var daysSinceStart: Int
    /// Days with a positive record, over all non-negative habits
    /// (archived included).
    public var habitTimesDone: Int
    public var tasksDone: Int
    public var focusSeconds: TimeInterval
    /// The habit with the best streak ever, and that streak.
    public var bestStreak: InsightsNamedCount?

    public init(
        firstDay: Date? = nil,
        daysSinceStart: Int = 0,
        habitTimesDone: Int = 0,
        tasksDone: Int = 0,
        focusSeconds: TimeInterval = 0,
        bestStreak: InsightsNamedCount? = nil
    ) {
        self.firstDay = firstDay
        self.daysSinceStart = daysSinceStart
        self.habitTimesDone = habitTimesDone
        self.tasksDone = tasksDone
        self.focusSeconds = focusSeconds
        self.bestStreak = bestStreak
    }

    public static let empty = InsightsAllTime()
}
