#if DEBUG
import Foundation
import SwiftData
import KadoCore

/// The data the Insights UI tests start from (`-uiTestSeedInsights`).
///
/// Four months of someone who applies to Cambridge, trains for a half
/// marathon and has a job: seven habits in six categories, two measured
/// goals, 42 tasks and 61 work sessions. Built so that every Insights
/// card has something to say for the last 90 days: tasks done on time,
/// done late, left undone and still to come; sessions in every part of
/// the day, 15 of them from a timed block (some longer, some shorter
/// than planned); a habit on its best streak; a negative habit with a
/// few slips.
///
/// Deterministic, like `ScreenshotSeed`: every miss, task and session
/// sits at a fixed offset from the logical today, so two runs give the
/// same history. Sessions stop yesterday. Today only holds the morning's
/// meditation and some water, and never anything after `now`.
///
/// English only: the UI tests run in English.
@MainActor
enum InsightsSeed {
    /// Days of habit history before today. More than the 90 days the
    /// cards must fill, so the month view has a full previous month.
    static let historyDays = 120

    static func seed(into context: ModelContext, calendar: Calendar = .current, now: Date = .now) {
        // Through the boundary, like the other seeds, so the history
        // lines up with the day Today and Insights show.
        let today = DayStartDefaults.boundary(calendar: calendar).startOfDay(for: now)
        let clock = InsightsSeedClock(calendar: calendar, today: today, now: now)
        InsightsSeedWriter(context: context, clock: clock).write()
        try? context.save()
    }
}

// MARK: - Habit history

extension InsightsSeed {
    /// Days on which most habits slip together, so the other days can
    /// be perfect.
    nonisolated static func isRoughDay(_ daysAgo: Int) -> Bool { daysAgo % 9 == 4 }

    /// In bed by 23:30: about 4 nights in 5. Logged at night, so never today.
    nonisolated static func bedtime(_ daysAgo: Int) -> Double? {
        guard daysAgo > 0, !isRoughDay(daysAgo), daysAgo % 10 != 7 else { return nil }
        return 1
    }

    /// Workouts skipped on purpose. Each one also makes the rest days
    /// after it due, as `.daysPerWeek` counts a rolling week.
    nonisolated static let skippedWorkouts: Set<Int> = [15, 43, 71, 99]

    /// Workout, 4 days a week: the same 4 days of every 7, 45 to 55
    /// minutes, never less than the target.
    nonisolated static func workoutSeconds(_ daysAgo: Int) -> Double? {
        guard daysAgo > 0, [1, 3, 4, 6].contains(daysAgo % 7), !skippedWorkouts.contains(daysAgo) else { return nil }
        return [2700, 3000, 2880, 3300][daysAgo % 4]
    }

    /// Read 20 pages: about 7 days in 10. Logged at night, so never today.
    nonisolated static func reading(_ daysAgo: Int) -> Double? {
        guard daysAgo > 0, !isRoughDay(daysAgo), daysAgo % 5 != 2 else { return nil }
        return 1
    }

    /// Meditation is done every day of the last `meditationStreak` days,
    /// today included, so its current streak is also its best.
    nonisolated static let meditationStreak = 45

    /// Meditate, 10 minutes: one day in four missed before the streak.
    nonisolated static func meditationSeconds(_ daysAgo: Int) -> Double? {
        if daysAgo >= meditationStreak && daysAgo % 4 == 1 { return nil }
        return [600, 660, 720][daysAgo % 3]
    }

    /// Glasses of water logged so far today, by midday.
    nonisolated static let glassesSoFarToday: Double = 4

    /// Drink water, 8 glasses: the full count on 3 days in 5, part of
    /// it on one, nothing logged on the last. Any record keeps a streak
    /// going, so the gaps keep this one short.
    nonisolated static func glasses(_ daysAgo: Int) -> Double? {
        guard daysAgo > 0 else { return nil }
        switch daysAgo % 5 {
        case 2: return [5, 6, 7][daysAgo % 3]
        case 3: return nil
        default: return [8, 9, 8, 10][daysAgo % 4]
        }
    }

    /// Tidy up, on Wednesdays and Saturdays: one week in four skipped.
    nonisolated static func tidied(_ daysAgo: Int, on weekday: Weekday?) -> Double? {
        guard daysAgo > 0, weekday == .wednesday || weekday == .saturday, (daysAgo / 7) % 4 != 3 else { return nil }
        return 1
    }

    /// No sugar: seven slips in four months, none in the last week.
    nonisolated static let sugarSlips: Set<Int> = [9, 23, 38, 52, 66, 81, 103]

    /// Workout days that were tracked as a session at 18:00.
    nonisolated static let workoutSessionDays = [4, 6, 8, 11, 13, 18, 22, 25, 32, 39]

    /// Meditation days that were tracked as a session at 07:00.
    nonisolated static let meditationSessionDays = [1, 2, 5, 9, 14, 20]
}

// MARK: - Tasks and sessions

/// One seeded task. Day offsets are from the logical today.
struct InsightsSeedTask {
    enum Goal { case cambridge, marathon }

    let title: String
    /// `nil`: the category comes from the goal or from the title.
    let category: ItemCategory?
    let goal: Goal?
    let created: Int
    /// One block per day. The last one is the due day too.
    let planned: [Int]
    let done: Int?

    init(_ title: String, _ category: ItemCategory? = nil, goal: Goal? = nil, created: Int, planned: [Int] = [], done: Int? = nil) {
        self.title = title
        self.category = category
        self.goal = goal
        self.created = created
        self.planned = planned
        self.done = done
    }
}

/// One seeded session on a task, by the task's title.
struct InsightsSeedSession {
    let task: String
    let day: Int
    let start: (hour: Int, minute: Int)
    let minutes: Int
    /// The timed block it ran from: the block's start and length.
    let plan: (start: (hour: Int, minute: Int), minutes: Int)?

    init(
        _ task: String,
        day: Int,
        at start: (hour: Int, minute: Int),
        minutes: Int,
        planned plan: (start: (hour: Int, minute: Int), minutes: Int)? = nil
    ) {
        self.task = task
        self.day = day
        self.start = start
        self.minutes = minutes
        self.plan = plan
    }
}

extension InsightsSeed {
    static let tasks: [InsightsSeedTask] = cambridgeTasks + otherTasks

    /// The goal's twelve tasks: seven done (three of them late), two
    /// left undone, three still to come.
    private static let cambridgeTasks: [InsightsSeedTask] = [
        .init("Research Cambridge colleges", goal: .cambridge, created: -88, planned: [-84], done: -85),
        .init("Compare course requirements", goal: .cambridge, created: -84, planned: [-78], done: -78),
        .init("Contact professors at Cambridge", goal: .cambridge, created: -80, planned: [-72], done: -70),
        .init("Book the IELTS exam", goal: .cambridge, created: -70, planned: [-64], done: -64),
        .init("Ask for reference letters", goal: .cambridge, created: -66, planned: [-55], done: -50),
        .init("Draft the personal statement", goal: .cambridge, created: -60, planned: [-45, -43, -41], done: -41),
        .init("Revise the personal statement", goal: .cambridge, created: -40, planned: [-26], done: -24),
        .init("Order transcripts", goal: .cambridge, created: -35, planned: [-20]),
        .init("Prepare for the interview", goal: .cambridge, created: -20, planned: [-6, -3]),
        .init("Submit the UCAS application", goal: .cambridge, created: -15, planned: [10]),
        .init("Write to the admissions office", goal: .cambridge, created: -10, planned: [21]),
        .init("Book flights for the interview", goal: .cambridge, created: -5, planned: [45]),
    ]

    /// Over the whole history (and so in a year report), Errands are
    /// the ones most often left undone. Over the last month, Study
    /// leads instead. A few titles have no category, so the keyword
    /// classifier finds it.
    private static let otherTasks: [InsightsSeedTask] = [
        .init("Buy running shoes", goal: .marathon, created: -58, planned: [-55], done: -56),
        .init("Sign up for the race", goal: .marathon, created: -50, planned: [-40], done: -40),

        .init("Prepare the quarterly report", .work, created: -50, planned: [-44], done: -44),
        .init("Review the design proposal", .work, created: -40, planned: [-36], done: -37),
        .init("Write slides for the meeting", .work, created: -30, planned: [-27], done: -27),
        .init("Reply to client emails", .work, created: -25, planned: [-21], done: -19),
        .init("Update the project roadmap", .work, created: -18, planned: [-14], done: -14),
        .init("Plan the next sprint", .work, created: -12, planned: [-8], done: -8),
        .init("Fix the onboarding bug", .work, created: -9, planned: [-5], done: -4),
        .init("Prepare the team offsite", .work, created: -6, planned: [5]),
        .init("Write the monthly newsletter", .work, created: -4, planned: [12]),

        .init("Pick up the dry cleaning", .errands, created: -60, planned: [-58], done: -58),
        .init("Renew passport", .errands, created: -55, planned: [-47]),
        .init("Return the parcel", .errands, created: -30, planned: [-28]),
        .init("Buy groceries", created: -12, planned: [-11], done: -11),
        .init("Get the car serviced", .errands, created: -9, planned: [-7]),
        .init("Pick up the new glasses", .errands, created: -5, planned: [2]),

        .init("Clean the kitchen", created: -40, planned: [-33], done: -33),
        .init("Fix the kitchen tap", .home, created: -35, planned: [-30], done: -25),
        .init("Clean the garage", .home, created: -20, planned: [-16]),
        .init("Hang the shelves", .home, created: -10, planned: [-9], done: -9),
        .init("Deep clean the oven", .home, created: -3, planned: [6]),

        .init("Call mom", created: -45, planned: [-42], done: -42),
        .init("Plan Sam's birthday dinner", .social, created: -30, planned: [-24], done: -26),
        .init("Write a thank-you card", .social, created: -14, planned: [-10]),
        .init("Catch up with Alex", .social, created: -2, planned: [4]),

        .init("Pay rent", created: -32, planned: [-31], done: -31),
        .init("Do the tax return", .money, created: -60, planned: [-40], done: -35),
        .init("Review the budget", .money, created: -20, planned: [-17], done: -17),
        .init("Cancel unused subscriptions", .money, created: -7),
    ]

    /// Task sessions: mostly mornings, some evenings, one late night.
    static let sessions: [InsightsSeedSession] = [
        .init("Research Cambridge colleges", day: -86, at: (9, 0), minutes: 60),
        .init("Research Cambridge colleges", day: -85, at: (20, 0), minutes: 45),
        .init("Compare course requirements", day: -79, at: (19, 30), minutes: 50),
        .init("Compare course requirements", day: -78, at: (8, 30), minutes: 40, planned: ((8, 30), 60)),
        .init("Contact professors at Cambridge", day: -72, at: (10, 0), minutes: 30, planned: ((10, 0), 30)),
        .init("Contact professors at Cambridge", day: -70, at: (16, 0), minutes: 25),
        .init("Book the IELTS exam", day: -64, at: (12, 30), minutes: 20),
        .init("Ask for reference letters", day: -55, at: (9, 0), minutes: 35),
        .init("Ask for reference letters", day: -50, at: (17, 0), minutes: 20),
        .init("Draft the personal statement", day: -45, at: (7, 5), minutes: 100, planned: ((7, 0), 90)),
        .init("Draft the personal statement", day: -43, at: (7, 0), minutes: 80, planned: ((7, 0), 90)),
        .init("Draft the personal statement", day: -41, at: (7, 10), minutes: 95, planned: ((7, 0), 90)),
        .init("Revise the personal statement", day: -28, at: (21, 0), minutes: 60),
        .init("Revise the personal statement", day: -26, at: (7, 30), minutes: 75, planned: ((7, 30), 60)),
        .init("Revise the personal statement", day: -24, at: (7, 30), minutes: 45),
        .init("Order transcripts", day: -21, at: (13, 0), minutes: 15),
        .init("Prepare for the interview", day: -6, at: (18, 30), minutes: 50, planned: ((18, 30), 60)),
        .init("Prepare for the interview", day: -3, at: (18, 30), minutes: 70, planned: ((18, 30), 60)),

        .init("Prepare the quarterly report", day: -46, at: (10, 0), minutes: 90),
        .init("Prepare the quarterly report", day: -45, at: (14, 0), minutes: 60),
        .init("Prepare the quarterly report", day: -44, at: (9, 0), minutes: 110, planned: ((9, 0), 120)),
        .init("Review the design proposal", day: -37, at: (15, 0), minutes: 45),
        .init("Write slides for the meeting", day: -28, at: (16, 0), minutes: 50),
        .init("Write slides for the meeting", day: -27, at: (14, 0), minutes: 100, planned: ((14, 0), 90)),
        .init("Reply to client emails", day: -21, at: (9, 30), minutes: 30),
        .init("Reply to client emails", day: -19, at: (9, 15), minutes: 40),
        .init("Update the project roadmap", day: -14, at: (10, 0), minutes: 55, planned: ((10, 0), 60)),
        .init("Plan the next sprint", day: -9, at: (11, 0), minutes: 45),
        .init("Plan the next sprint", day: -8, at: (13, 30), minutes: 60),
        .init("Fix the onboarding bug", day: -5, at: (9, 30), minutes: 150, planned: ((9, 30), 120)),
        .init("Fix the onboarding bug", day: -4, at: (10, 0), minutes: 80),
        .init("Prepare the team offsite", day: -2, at: (15, 0), minutes: 40),
        .init("Prepare the team offsite", day: -1, at: (10, 0), minutes: 50),
        .init("Write the monthly newsletter", day: -1, at: (16, 30), minutes: 35),

        .init("Fix the kitchen tap", day: -30, at: (10, 0), minutes: 45),
        .init("Fix the kitchen tap", day: -25, at: (11, 0), minutes: 60),
        .init("Hang the shelves", day: -9, at: (15, 0), minutes: 90, planned: ((15, 0), 60)),
        .init("Clean the garage", day: -16, at: (14, 0), minutes: 40, planned: ((14, 0), 60)),

        .init("Do the tax return", day: -40, at: (20, 0), minutes: 90, planned: ((20, 0), 60)),
        .init("Do the tax return", day: -37, at: (21, 0), minutes: 60),
        .init("Do the tax return", day: -36, at: (22, 0), minutes: 45),
        .init("Review the budget", day: -17, at: (20, 30), minutes: 30),

        .init("Call mom", day: -42, at: (18, 0), minutes: 25),
        .init("Plan Sam's birthday dinner", day: -27, at: (19, 0), minutes: 30),
        .init("Renew passport", day: -48, at: (12, 0), minutes: 25),
    ]
}

// MARK: - Writing

/// Day arithmetic through `Calendar`, never through seconds.
struct InsightsSeedClock {
    let calendar: Calendar
    /// Calendar midnight of the logical today.
    let today: Date
    let now: Date

    /// Midnight `offset` days from today. Re-anchored, so a zone whose
    /// day starts at 01:00 still gives that day's first instant.
    func day(_ offset: Int) -> Date {
        calendar.startOfDay(for: calendar.date(byAdding: .day, value: offset, to: today) ?? today)
    }

    /// `hour:minute` on the day `offset` days from today. Anything
    /// stamped today is moved back to `now` if it would be later.
    func at(_ offset: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        let day = day(offset)
        let instant = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? day
        return offset == 0 ? min(instant, now) : instant
    }

    func adding(minutes: Int, to date: Date) -> Date {
        calendar.date(byAdding: .minute, value: minutes, to: date) ?? date
    }
}

private struct InsightsSeedWriter {
    let context: ModelContext
    let clock: InsightsSeedClock

    func write() {
        let cambridge = GoalRecord(
            name: "Get into Cambridge",
            details: "Apply for the master's and get an offer.",
            startDate: clock.day(-90),
            targetDate: clock.day(120),
            createdAt: clock.at(-90, 9),
            updatedAt: clock.at(-90, 9),
            category: .study
        )
        cambridge.measurement = GoalMeasurement(enabled: true, mode: .tasks, target: 12, unit: "tasks")
        let marathon = GoalRecord(
            name: "Run a half marathon",
            details: "Finish the city half marathon in under two hours.",
            startDate: clock.day(-60),
            targetDate: clock.day(45),
            createdAt: clock.at(-60, 9),
            updatedAt: clock.at(-60, 9),
            category: .fitness
        )
        context.insert(cambridge)
        context.insert(marathon)

        let workout = writeHabits(cambridge: cambridge, marathon: marathon)
        // Progress in minutes of the workout habit, as the goal form sets it up.
        marathon.measurement = GoalMeasurement(enabled: true, mode: .habit, target: 3000, unit: "minutes", habitID: workout.id)

        let goals: [InsightsSeedTask.Goal: GoalRecord] = [.cambridge: cambridge, .marathon: marathon]
        var tasks: [String: (record: TaskRecord, blocks: [Int: ScheduleBlockRecord])] = [:]
        for spec in InsightsSeed.tasks {
            tasks[spec.title] = writeTask(spec, goal: spec.goal.flatMap { goals[$0] })
        }
        for spec in InsightsSeed.sessions {
            guard let task = tasks[spec.task] else { continue }
            writeSession(spec, on: task.record, block: task.blocks[spec.day])
        }
    }

    // MARK: Habits

    /// Writes the seven habits and their history; returns the workout.
    private func writeHabits(cambridge: GoalRecord, marathon: GoalRecord) -> HabitRecord {
        let start = clock.day(-InsightsSeed.historyDays)
        let bed = HabitRecord(name: "In bed by 23:30", frequency: .daily, type: .binary, createdAt: start,
                              color: .teal, icon: "bed.double.fill", sortOrder: 0, category: .sleep)
        let workout = HabitRecord(name: "Workout", frequency: .daysPerWeek(4), type: .timer(targetSeconds: 2700), createdAt: start,
                                  color: .orange, icon: "dumbbell.fill", sortOrder: 1, goal: marathon, category: .fitness)
        let read = HabitRecord(name: "Read 20 pages", frequency: .daily, type: .binary, createdAt: start,
                               color: .purple, icon: "book.fill", sortOrder: 2, goal: cambridge, category: .study)
        let meditate = HabitRecord(name: "Meditate", frequency: .daily, type: .timer(targetSeconds: 600), createdAt: start,
                                   color: .mint, icon: "figure.mind.and.body", sortOrder: 3, category: .mind)
        let water = HabitRecord(name: "Drink water", frequency: .daily, type: .counter(target: 8), createdAt: start,
                                color: .blue, icon: "drop.fill", sortOrder: 4, category: .health)
        let tidy = HabitRecord(name: "Tidy up", frequency: .specificDays([.wednesday, .saturday]), type: .binary, createdAt: start,
                               color: .green, icon: "house.fill", sortOrder: 5, category: .home)
        let sugar = HabitRecord(name: "No sugar", frequency: .daily, type: .negative, createdAt: start,
                                color: .red, icon: "fork.knife", sortOrder: 6, category: .health)

        writeHistory(of: bed, at: (23, 10), InsightsSeed.bedtime)
        writeHistory(of: workout, at: (19, 0), InsightsSeed.workoutSeconds)
        writeHistory(of: read, at: (21, 30), InsightsSeed.reading)
        writeHistory(of: meditate, at: (7, 20), InsightsSeed.meditationSeconds)
        writeHistory(of: water, at: (20, 0), InsightsSeed.glasses)
        context.insert(CompletionRecord(date: clock.at(0, 12), value: InsightsSeed.glassesSoFarToday, habit: water))
        writeHistory(of: tidy, at: (10, 30)) { daysAgo in
            let weekday = Weekday(rawValue: clock.calendar.component(.weekday, from: clock.day(-daysAgo)))
            return InsightsSeed.tidied(daysAgo, on: weekday)
        }
        writeHistory(of: sugar, at: (15, 0)) { InsightsSeed.sugarSlips.contains($0) ? 1 : nil }

        // Finishing a timer session logs its time, so these sessions
        // last exactly what the day's record holds.
        for daysAgo in InsightsSeed.workoutSessionDays {
            guard let seconds = InsightsSeed.workoutSeconds(daysAgo) else { continue }
            writeHabitSession(on: workout, day: -daysAgo, at: (18, 0), seconds: seconds)
        }
        for daysAgo in InsightsSeed.meditationSessionDays {
            guard let seconds = InsightsSeed.meditationSeconds(daysAgo) else { continue }
            writeHabitSession(on: meditate, day: -daysAgo, at: (7, 0), seconds: seconds)
        }
        return workout
    }

    /// Inserts `habit` and one record per day `value` answers, from the
    /// first day of history to today.
    private func writeHistory(of habit: HabitRecord, at time: (hour: Int, minute: Int), _ value: (Int) -> Double?) {
        context.insert(habit)
        for daysAgo in stride(from: InsightsSeed.historyDays, through: 0, by: -1) {
            guard let logged = value(daysAgo) else { continue }
            context.insert(CompletionRecord(date: clock.at(-daysAgo, time.hour, time.minute), value: logged, habit: habit))
        }
    }

    private func writeHabitSession(on habit: HabitRecord, day: Int, at time: (Int, Int), seconds: Double) {
        let start = clock.at(day, time.0, time.1)
        let end = start.addingTimeInterval(seconds)
        context.insert(WorkSessionRecord(startedAt: start, endedAt: end, createdAt: start, updatedAt: end, habit: habit))
    }

    // MARK: Tasks

    private func writeTask(_ spec: InsightsSeedTask, goal: GoalRecord?) -> (record: TaskRecord, blocks: [Int: ScheduleBlockRecord]) {
        let created = clock.at(spec.created, 8, 30)
        let completed = spec.done.map { clock.at($0, 17, 30) }
        let task = TaskRecord(
            title: spec.title,
            dueDate: spec.planned.last.map { clock.day($0) },
            createdAt: created,
            updatedAt: completed ?? created,
            completedAt: completed,
            goal: goal,
            category: spec.category
        )
        context.insert(task)
        var blocks: [Int: ScheduleBlockRecord] = [:]
        for offset in spec.planned {
            let block = ScheduleBlockRecord(plannedDay: clock.day(offset), createdAt: created, updatedAt: created, task: task)
            context.insert(block)
            blocks[offset] = block
        }
        return (task, blocks)
    }

    private func writeSession(_ spec: InsightsSeedSession, on task: TaskRecord, block: ScheduleBlockRecord?) {
        let start = clock.at(spec.day, spec.start.hour, spec.start.minute)
        let end = clock.adding(minutes: spec.minutes, to: start)
        var plannedBlock: ScheduleBlockRecord?
        if let plan = spec.plan, let block {
            let plannedStart = clock.at(spec.day, plan.start.hour, plan.start.minute)
            block.startAt = plannedStart
            block.endAt = clock.adding(minutes: plan.minutes, to: plannedStart)
            plannedBlock = block
        }
        context.insert(WorkSessionRecord(startedAt: start, endedAt: end, createdAt: start, updatedAt: end, task: task, scheduleBlock: plannedBlock))
        // A task finished on the day of a later session is ticked off
        // right after it.
        if let completed = task.completedAt, clock.calendar.isDate(completed, inSameDayAs: start), completed < end {
            task.completedAt = clock.adding(minutes: 10, to: end)
            task.updatedAt = task.completedAt ?? task.updatedAt
        }
    }
}
#endif
