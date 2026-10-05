import Foundation
import KadoCore

/// Insights reports for previews and for the UI suite's fixture run
/// (`-uiTestInsightsFixture`). Plain values: no store and no
/// calculator. Every id is fixed and every date hangs off one fixed
/// day, so each render shows the same feed.
///
/// - `rich`: a user a year in, with every section filled, for each
///   period (`rich(for:)`).
/// - `sparse`: a user four days in, with two habits, no sessions and
///   no Apple Health.
/// - `empty`: nothing at all, the first-run state.
enum InsightsPreviewData {

    // MARK: - Clock

    /// The device's calendar, so the heat map's weeks start where the
    /// app's do.
    static let calendar = Calendar.current

    /// The day the fixture calls today: Monday 13 April 2026.
    static let today: Date = {
        let components = DateComponents(year: 2026, month: 4, day: 13)
        return calendar.startOfDay(for: calendar.date(from: components) ?? Date(timeIntervalSinceReferenceDate: 797_731_200))
    }()

    // MARK: - Ids

    enum ID {
        static let readHabit = UUID(uuidString: "1A5E0001-0000-4000-8000-000000000001")!
        static let meditateHabit = UUID(uuidString: "1A5E0001-0000-4000-8000-000000000002")!
        static let waterHabit = UUID(uuidString: "1A5E0001-0000-4000-8000-000000000003")!
        static let sleepHabit = UUID(uuidString: "1A5E0001-0000-4000-8000-000000000004")!
        static let runHabit = UUID(uuidString: "1A5E0001-0000-4000-8000-000000000005")!
        static let takeoutHabit = UUID(uuidString: "1A5E0001-0000-4000-8000-000000000006")!
        static let walkHabit = UUID(uuidString: "1A5E0001-0000-4000-8000-000000000007")!
        static let cambridgeGoal = UUID(uuidString: "1A5E0002-0000-4000-8000-000000000001")!
        static let marathonGoal = UUID(uuidString: "1A5E0002-0000-4000-8000-000000000002")!
        static let pianoGoal = UUID(uuidString: "1A5E0002-0000-4000-8000-000000000003")!
        static let garageGoal = UUID(uuidString: "1A5E0002-0000-4000-8000-000000000004")!
    }

    // MARK: - Reports

    static let rich = richReport(.month)
    static let richWeek = richReport(.week)
    static let richYear = richReport(.year)

    /// The rich report for a period.
    static func rich(for period: InsightsPeriod) -> InsightsReport {
        switch period {
        case .week: richWeek
        case .month: rich
        case .year: richYear
        }
    }

    static let sparse = sparseReport()

    static let empty = InsightsReport(period: .month, days: days(.month))

    /// One highlight of every kind, for the Highlights card's previews.
    static let everyHighlight: [InsightsHighlight] = [
        .streakRecord(habitName: "Read", days: 12),
        .consistencyChange(points: 6),
        .consistencyChange(points: -4),
        .mostUndoneCategory(.errands, undone: 5, total: 9),
        .topFocusCategory(.study, seconds: 9 * 3_600 + 20 * 60),
        .perfectDays(count: 14),
        .peakFocusTime(.morning, share: 0.62),
        .peakFocusTime(.night, share: 0.41),
        .bestWeekday(.tuesday, fraction: 0.96),
        .milestone(habitName: "Meditate", count: 100),
        .longestStreak(habitName: "Meditate", days: 23),
        .focusTotal(seconds: 15 * 3_600 + 40 * 60),
    ]

    /// Goals in the states `rich` does not show: behind, due today, and
    /// one with no measurement or date.
    static let behindGoals: [InsightsGoalRow] = [
        InsightsGoalRow(
            goalID: ID.pianoGoal,
            name: "Learn a piano piece",
            category: .creative,
            progress: 0.15,
            tasksDone: 1,
            tasksTotal: 6,
            pace: .behind,
            daysLeft: 0
        ),
        InsightsGoalRow(
            goalID: ID.garageGoal,
            name: "Tidy the garage",
            category: .home,
            tasksDone: 2,
            tasksTotal: 5
        ),
    ]

    // MARK: - Rich

    private static func richReport(_ period: InsightsPeriod) -> InsightsReport {
        InsightsReport(
            period: period,
            days: days(period),
            pulse: pulse(period),
            highlights: highlights(period),
            activity: activity(period),
            focus: focus(period),
            categories: categories(period),
            sleep: sleep(period),
            movement: movement(period),
            habits: habits(period),
            tasks: tasks(period),
            goals: goals(period),
            rhythm: rhythm(period),
            allTime: allTime,
            isEmpty: false
        )
    }

    private static func pulse(_ period: InsightsPeriod) -> InsightsPulse {
        switch period {
        case .week:
            InsightsPulse(
                consistency: InsightsRate(done: 36, total: 41),
                previousConsistency: InsightsRate(done: 33, total: 41),
                followThrough: InsightsRate(done: 6, total: 9),
                previousFollowThrough: InsightsRate(done: 5, total: 8),
                activeDays: InsightsRate(done: 6, total: 7),
                previousActiveDays: InsightsRate(done: 7, total: 7)
            )
        case .month:
            InsightsPulse(
                consistency: InsightsRate(done: 141, total: 172),
                previousConsistency: InsightsRate(done: 129, total: 170),
                followThrough: InsightsRate(done: 25, total: 39),
                previousFollowThrough: InsightsRate(done: 24, total: 36),
                activeDays: InsightsRate(done: 27, total: 30),
                previousActiveDays: InsightsRate(done: 27, total: 30)
            )
        case .year:
            InsightsPulse(
                consistency: InsightsRate(done: 1_650, total: 2_090),
                previousConsistency: InsightsRate(done: 1_712, total: 2_080),
                followThrough: InsightsRate(done: 301, total: 420),
                previousFollowThrough: .empty,
                activeDays: InsightsRate(done: 331, total: 365),
                previousActiveDays: InsightsRate(done: 30, total: 36)
            )
        }
    }

    private static func highlights(_ period: InsightsPeriod) -> [InsightsHighlight] {
        switch period {
        case .week:
            let focus = focusBuckets(.week)
            return [
                .longestStreak(habitName: "Meditate", days: 23),
                .consistencyChange(points: 8),
                .topFocusCategory(.study, seconds: focus.reduce(0) { $0 + ($1.byCategory[.study] ?? 0) }),
                .focusTotal(seconds: focus.reduce(0) { $0 + $1.seconds }),
            ]
        case .month:
            return [
                .streakRecord(habitName: "Read", days: 12),
                .mostUndoneCategory(.errands, undone: 5, total: 9),
                .peakFocusTime(.morning, share: 0.62),
                .consistencyChange(points: 6),
            ]
        case .year:
            return [
                .milestone(habitName: "Read", count: 250),
                .bestWeekday(.tuesday, fraction: 0.91),
                .perfectDays(count: activity(.year).perfectDays),
                .consistencyChange(points: -3),
            ]
        }
    }

    // MARK: Activity

    /// The month's habit days, oldest first: mostly done, a few partial
    /// days, one with nothing done and one with nothing due.
    private static let monthPattern: [Double?] = [
        1, 0.75, 1, 0.5, 1, 1, nil, 0.8, 1, 0.33,
        1, 1, 0.6, 1, 0, 1, 1, 0.83, 1, 1,
        0.66, 1, 1, 1, 0.5, 1, 0.8, 1, 1, 0.75,
    ]

    /// The share of habits done on the day at `index` of `count`. The
    /// last 30 days follow `monthPattern`; older days a fixed mix.
    private static func fraction(at index: Int, of count: Int) -> Double? {
        let fromEnd = count - 1 - index
        if fromEnd < monthPattern.count {
            return monthPattern[monthPattern.count - 1 - fromEnd]
        }
        let draw = (index * 7_919 + 13) % 100
        switch draw {
        case ..<6: return nil
        case ..<12: return 0
        case ..<55: return 1
        default: return Double(draw % 6 + 1) / 7
        }
    }

    private static func activity(_ period: InsightsPeriod) -> InsightsActivity {
        let periodDays = days(period)
        var cells = leadingPadding(before: periodDays.first)
        for (index, day) in periodDays.enumerated() {
            cells.append(InsightsActivityDay(
                date: day,
                habitFraction: fraction(at: index, of: periodDays.count),
                tasksDone: (index * 3) % 4,
                focusSeconds: Double((index * 37) % 5) * 1_200,
                isInPeriod: true
            ))
        }
        return InsightsActivity(
            days: cells,
            perfectDays: cells.filter { $0.isInPeriod && $0.habitFraction == 1 }.count,
            longestPerfectRun: longestPerfectRun(cells)
        )
    }

    /// The cells from the calendar's first weekday up to `first`, which
    /// only pad the first week.
    private static func leadingPadding(before first: Date?) -> [InsightsActivityDay] {
        guard var lead = first else { return [] }
        var padding: [InsightsActivityDay] = []
        while calendar.component(.weekday, from: lead) != calendar.firstWeekday, padding.count < 6 {
            lead = InsightsScope.step(lead, by: -1, calendar: calendar)
            padding.insert(InsightsActivityDay(date: lead, isInPeriod: false), at: 0)
        }
        return padding
    }

    private static func longestPerfectRun(_ cells: [InsightsActivityDay]) -> Int {
        var longest = 0
        var run = 0
        for cell in cells where cell.isInPeriod {
            if cell.habitFraction == 1 {
                run += 1
                longest = max(longest, run)
            } else {
                run = 0
            }
        }
        return longest
    }

    // MARK: Focus

    private static func focus(_ period: InsightsPeriod) -> InsightsFocus {
        let buckets = focusBuckets(period)
        let total = buckets.reduce(0) { $0 + $1.seconds }
        let sessions: Int
        switch period {
        case .week: sessions = 8
        case .month: sessions = 31
        case .year: sessions = 342
        }
        return InsightsFocus(
            total: total,
            previousTotal: (total * 0.84 / 60).rounded() * 60,
            sessionCount: sessions,
            averageSession: (total / Double(sessions) / 60).rounded() * 60,
            longestSession: 112 * 60,
            buckets: buckets,
            planRatio: 1.18,
            hasEverTracked: true
        )
    }

    /// A bucket per day for the week and the month, per calendar month
    /// for the year, split between Study, Work and Creative.
    private static func focusBuckets(_ period: InsightsPeriod) -> [InsightsFocusBucket] {
        guard period == .year else {
            return days(period).enumerated().map { index, day in
                let study = Double(((index * 37) % 5) * 20) * 60
                let work = calendar.isDateInWeekend(day) ? 0 : Double(((index * 53) % 4) * 25) * 60
                let creative: TimeInterval = index % 6 == 0 ? 40 * 60 : 0
                return bucket(day, [.study: study, .work: work, .creative: creative])
            }
        }
        guard let first = days(period).first else { return [] }
        var starts: [Date] = []
        var cursor = calendar.dateInterval(of: .month, for: first)?.start ?? first
        while cursor <= today, starts.count < 14 {
            starts.append(cursor)
            guard let next = calendar.date(byAdding: .month, value: 1, to: cursor) else { break }
            cursor = calendar.startOfDay(for: next)
        }
        return starts.enumerated().map { index, start in
            let study = Double(18 + (index * 7) % 11) * 3_600
            let work = Double(9 + (index * 5) % 8) * 3_600
            let creative = Double((index * 3) % 4) * 3_600
            return bucket(start, [.study: study, .work: work, .creative: creative])
        }
    }

    private static func bucket(_ start: Date, _ parts: [ItemCategory: TimeInterval]) -> InsightsFocusBucket {
        let byCategory = parts.filter { $0.value > 0 }
        return InsightsFocusBucket(start: start, seconds: byCategory.values.reduce(0, +), byCategory: byCategory)
    }

    private static func focusSeconds(_ category: ItemCategory, _ period: InsightsPeriod) -> TimeInterval {
        focusBuckets(period).reduce(0) { $0 + ($1.byCategory[category] ?? 0) }
    }

    // MARK: Categories

    private static func categories(_ period: InsightsPeriod) -> [InsightsCategoryRow] {
        [
            InsightsCategoryRow(
                category: .study,
                focusSeconds: focusSeconds(.study, period),
                habitConsistency: rate(25, 30, period),
                habitTimesDone: scaled(26, period),
                tasksDone: scaled(6, period),
                tasksUndone: scaled(2, period)
            ),
            InsightsCategoryRow(
                category: .work,
                focusSeconds: focusSeconds(.work, period),
                tasksDone: scaled(9, period),
                tasksUndone: scaled(4, period)
            ),
            InsightsCategoryRow(category: .mind, habitConsistency: rate(27, 30, period), habitTimesDone: scaled(27, period)),
            InsightsCategoryRow(category: .health, habitConsistency: rate(18, 30, period), habitTimesDone: scaled(28, period)),
            InsightsCategoryRow(category: .sleep, habitConsistency: rate(22, 30, period), habitTimesDone: scaled(22, period)),
            InsightsCategoryRow(
                category: .fitness,
                habitConsistency: rate(10, 13, period),
                habitTimesDone: scaled(11, period),
                tasksDone: scaled(1, period)
            ),
            InsightsCategoryRow(category: .creative, focusSeconds: focusSeconds(.creative, period), tasksDone: scaled(1, period)),
            InsightsCategoryRow(category: .errands, tasksDone: scaled(4, period), tasksUndone: scaled(5, period)),
            InsightsCategoryRow(category: .home, habitConsistency: rate(26, 30, period)),
        ]
    }

    // MARK: Sleep and movement

    private static func sleep(_ period: InsightsPeriod) -> InsightsSleep {
        let periodDays = days(period)
        var nights: [InsightsNight] = []
        // Three nights in ten have no record, as when the watch charges.
        for (index, day) in periodDays.enumerated() where ![2, 5, 8].contains(index % 10) {
            let bedtime = 21 * 60 + 55 + (index * 17) % 125
            let wake = 6 * 60 + 5 + (index * 23) % 70
            let evening = InsightsScope.step(day, by: -1, calendar: calendar)
            guard let start = calendar.date(bySettingHour: bedtime / 60, minute: bedtime % 60, second: 0, of: evening),
                  let end = calendar.date(bySettingHour: wake / 60, minute: wake % 60, second: 0, of: day)
            else { continue }
            nights.append(InsightsNight(day: day, start: start, end: end))
        }
        let durations = nights.map(\.duration)
        let average = durations.isEmpty ? nil : durations.reduce(0, +) / Double(durations.count)
        let bedtimes = nights.map { minutes(of: $0.start) }
        let medianBedtime = median(bedtimes)
        return InsightsSleep(
            isHealthConnected: true,
            nights: nights,
            averageDuration: average,
            previousAverageDuration: average.map { $0 - 14 * 60 },
            nightsOverSevenHours: InsightsRate(done: durations.filter { $0 >= 7 * 3_600 }.count, total: nights.count),
            bedtimeConsistency: InsightsRate(
                done: bedtimes.filter { abs($0 - (medianBedtime ?? $0)) <= 45 }.count,
                total: nights.count
            ),
            medianBedtimeMinutes: medianBedtime,
            medianWakeMinutes: median(nights.map { minutes(of: $0.end) }),
            habits: [
                InsightsHabitConsistency(
                    habitID: ID.sleepHabit,
                    name: "Lights out by 11",
                    icon: "bed.double.fill",
                    color: .teal,
                    rate: rate(22, 30, period)
                ),
            ]
        )
    }

    private static func movement(_ period: InsightsPeriod) -> InsightsMovement {
        let workouts = scaled(12, period)
        let fitness = scaled(11, period)
        return InsightsMovement(
            isHealthConnected: true,
            workoutCount: workouts,
            previousWorkoutCount: scaled(9, period),
            workoutTotal: Double(workouts) * 42 * 60,
            averageWorkout: 42 * 60,
            topWorkout: InsightsNamedCount(name: "Running", count: scaled(7, period)),
            fitnessTimesDone: fitness,
            previousFitnessTimesDone: scaled(8, period),
            fitnessTrackedTime: Double(fitness) * 35 * 60,
            averageFitnessTime: 35 * 60,
            habits: [
                InsightsHabitConsistency(
                    habitID: ID.runHabit,
                    name: "Run",
                    icon: "figure.run",
                    color: .orange,
                    rate: rate(10, 13, period)
                ),
            ]
        )
    }

    // MARK: Habits, tasks and goals

    private static func habits(_ period: InsightsPeriod) -> [InsightsHabitRow] {
        [
            InsightsHabitRow(
                habitID: ID.readHabit, name: "Read", icon: "book.fill", color: .purple,
                category: .study, type: .timer(targetSeconds: 20 * 60),
                rate: rate(25, 30, period), timesDone: scaled(26, period),
                amount: Double(scaled(26, period)) * 42 * 60,
                allTimeTimesDone: 312, allTimeAmount: 312 * 40 * 60,
                currentStreak: 12, bestStreak: 12, score: 0.84
            ),
            InsightsHabitRow(
                habitID: ID.meditateHabit, name: "Meditate", icon: "figure.mind.and.body", color: .mint,
                category: .mind, type: .binary,
                rate: rate(27, 30, period), timesDone: scaled(27, period),
                allTimeTimesDone: 371, currentStreak: 23, bestStreak: 41, score: 0.9
            ),
            InsightsHabitRow(
                habitID: ID.waterHabit, name: "Drink water", icon: "drop.fill", color: .blue,
                category: .health, type: .counter(target: 8),
                rate: rate(18, 30, period), timesDone: scaled(28, period),
                amount: Double(scaled(214, period)),
                allTimeTimesDone: 360, allTimeAmount: 2_610,
                currentStreak: 3, bestStreak: 11, score: 0.62
            ),
            InsightsHabitRow(
                habitID: ID.sleepHabit, name: "Lights out by 11", icon: "bed.double.fill", color: .teal,
                category: .sleep, type: .binary,
                rate: rate(22, 30, period), timesDone: scaled(22, period),
                allTimeTimesDone: 280, currentStreak: 4, bestStreak: 9, score: 0.71
            ),
            InsightsHabitRow(
                habitID: ID.runHabit, name: "Run", icon: "figure.run", color: .orange,
                category: .fitness, type: .timer(targetSeconds: 30 * 60),
                rate: rate(10, 13, period), timesDone: scaled(11, period),
                amount: Double(scaled(11, period)) * 35 * 60,
                allTimeTimesDone: 140, allTimeAmount: 140 * 33 * 60,
                currentStreak: 2, bestStreak: 6, score: 0.66
            ),
            InsightsHabitRow(
                habitID: ID.takeoutHabit, name: "No takeout", icon: "takeoutbag.and.cup.and.straw.fill", color: .green,
                category: .home, type: .negative,
                rate: rate(26, 30, period), timesDone: scaled(4, period),
                currentStreak: 9, bestStreak: 14, score: 0.8
            ),
        ]
    }

    private static func tasks(_ period: InsightsPeriod) -> InsightsTasks {
        switch period {
        case .week:
            InsightsTasks(
                done: 6, undone: 3, previousDone: 5, previousUndone: 3,
                onTime: InsightsRate(done: 4, total: 5),
                averageDaysToFinish: 1.2,
                undoneByCategory: [InsightsCategoryUndone(category: .errands, undone: 2, total: 3)],
                overdueOpen: 4
            )
        case .month:
            InsightsTasks(
                done: 25, undone: 14, previousDone: 24, previousUndone: 12,
                onTime: InsightsRate(done: 17, total: 21),
                averageDaysToFinish: 2.4,
                undoneByCategory: [
                    InsightsCategoryUndone(category: .errands, undone: 5, total: 9),
                    InsightsCategoryUndone(category: .work, undone: 4, total: 13),
                    InsightsCategoryUndone(category: .study, undone: 2, total: 8),
                ],
                overdueOpen: 4
            )
        case .year:
            InsightsTasks(
                done: 301, undone: 119,
                onTime: InsightsRate(done: 205, total: 260),
                averageDaysToFinish: 2.9,
                undoneByCategory: [
                    InsightsCategoryUndone(category: .errands, undone: 41, total: 88),
                    InsightsCategoryUndone(category: .work, undone: 37, total: 131),
                    InsightsCategoryUndone(category: .money, undone: 9, total: 26),
                ],
                overdueOpen: 4
            )
        }
    }

    private static func goals(_ period: InsightsPeriod) -> [InsightsGoalRow] {
        [
            InsightsGoalRow(
                goalID: ID.cambridgeGoal,
                name: "Get into Cambridge",
                category: .study,
                progress: 0.42,
                tasksDone: 6,
                tasksTotal: 14,
                tasksDoneInPeriod: scaled(3, period),
                habitConsistency: rate(25, 30, period),
                pace: .onTrack,
                daysLeft: 172
            ),
            InsightsGoalRow(
                goalID: ID.marathonGoal,
                name: "Run a half marathon",
                category: .fitness,
                progress: 0.68,
                tasksDone: 3,
                tasksTotal: 4,
                tasksDoneInPeriod: scaled(1, period),
                habitConsistency: rate(10, 13, period),
                pace: .ahead,
                daysLeft: 41
            ),
        ]
    }

    // MARK: Rhythm and all time

    private static func rhythm(_ period: InsightsPeriod) -> InsightsRhythm {
        let monthRates: [Weekday: (Int, Int)] = [
            .monday: (22, 25), .tuesday: (23, 24), .wednesday: (19, 25), .thursday: (21, 25),
            .friday: (17, 24), .saturday: (16, 24), .sunday: (20, 25),
        ]
        let weekdays = Weekday.week(startingOn: calendar.firstWeekday).map { weekday in
            let (done, total) = monthRates[weekday] ?? (0, 0)
            return InsightsWeekdayRate(weekday: weekday, rate: rate(done, total, period))
        }
        let total = focusBuckets(period).reduce(0) { $0 + $1.seconds }
        let shares: [InsightsPartOfDay: Double] = [.morning: 0.62, .afternoon: 0.20, .evening: 0.15, .night: 0.03]
        return InsightsRhythm(
            weekdays: weekdays,
            bestWeekday: period == .week ? nil : .tuesday,
            focusByPartOfDay: InsightsPartOfDay.allCases.map { part in
                InsightsPartOfDayFocus(part: part, seconds: (total * (shares[part] ?? 0) / 60).rounded() * 60)
            },
            peakPartOfDay: .morning
        )
    }

    private static let allTime = InsightsAllTime(
        firstDay: InsightsScope.step(today, by: -400, calendar: calendar),
        daysSinceStart: 401,
        habitTimesDone: 2_140,
        tasksDone: 386,
        focusSeconds: 212 * 3_600 + 40 * 60,
        bestStreak: InsightsNamedCount(name: "Meditate", count: 41)
    )

    // MARK: - Sparse

    private static func sparseReport() -> InsightsReport {
        let period = InsightsPeriod.month
        let periodDays = days(period)
        let recent = Array(periodDays.suffix(4))
        let recentFractions: [Double?] = [1, 0.5, 1, 1]
        var cells = leadingPadding(before: periodDays.first)
        for day in periodDays {
            let fraction = recent.firstIndex(of: day).flatMap { recentFractions[$0] }
            cells.append(InsightsActivityDay(date: day, habitFraction: fraction, tasksDone: day == recent.last ? 1 : 0))
        }
        let recentWeekdays = Set(recent.compactMap { Weekday(rawValue: calendar.component(.weekday, from: $0)) })
        return InsightsReport(
            period: period,
            days: periodDays,
            pulse: InsightsPulse(
                consistency: InsightsRate(done: 6, total: 8),
                followThrough: InsightsRate(done: 2, total: 2),
                activeDays: InsightsRate(done: 4, total: 4)
            ),
            activity: InsightsActivity(days: cells, perfectDays: 3, longestPerfectRun: 2),
            categories: [
                InsightsCategoryRow(category: .study, habitConsistency: InsightsRate(done: 3, total: 4), habitTimesDone: 3, tasksDone: 1),
                InsightsCategoryRow(category: .fitness, habitConsistency: InsightsRate(done: 3, total: 4), habitTimesDone: 3),
                InsightsCategoryRow(category: .errands, tasksDone: 1),
            ],
            movement: InsightsMovement(
                fitnessTimesDone: 3,
                habits: [
                    InsightsHabitConsistency(
                        habitID: ID.walkHabit,
                        name: "Walk",
                        icon: "figure.walk",
                        color: .orange,
                        rate: InsightsRate(done: 3, total: 4)
                    ),
                ]
            ),
            habits: [
                InsightsHabitRow(
                    habitID: ID.readHabit, name: "Read", icon: "book.fill", color: .purple,
                    category: .study, type: .binary,
                    rate: InsightsRate(done: 3, total: 4), timesDone: 3,
                    allTimeTimesDone: 3, currentStreak: 2, bestStreak: 2, score: 0.2
                ),
                InsightsHabitRow(
                    habitID: ID.walkHabit, name: "Walk", icon: "figure.walk", color: .orange,
                    category: .fitness, type: .binary,
                    rate: InsightsRate(done: 3, total: 4), timesDone: 3,
                    allTimeTimesDone: 3, currentStreak: 1, bestStreak: 2, score: 0.18
                ),
            ],
            tasks: InsightsTasks(done: 2, onTime: InsightsRate(done: 1, total: 1), averageDaysToFinish: 0.5),
            rhythm: InsightsRhythm(
                weekdays: Weekday.week(startingOn: calendar.firstWeekday).map { weekday in
                    InsightsWeekdayRate(
                        weekday: weekday,
                        rate: recentWeekdays.contains(weekday) ? InsightsRate(done: 1, total: 2) : .empty
                    )
                },
                focusByPartOfDay: InsightsPartOfDay.allCases.map { InsightsPartOfDayFocus(part: $0, seconds: 0) }
            ),
            allTime: InsightsAllTime(
                firstDay: recent.first,
                daysSinceStart: 4,
                habitTimesDone: 6,
                tasksDone: 2,
                bestStreak: InsightsNamedCount(name: "Read", count: 2)
            ),
            isEmpty: false
        )
    }

    // MARK: - Helpers

    /// The period's days, ending with the fixture's today.
    private static func days(_ period: InsightsPeriod) -> [Date] {
        InsightsScope.days(endingAt: today, count: period.dayCount, calendar: calendar)
    }

    /// How much a period holds against a month. Counts in the fixture
    /// are written for a month and scale with this.
    private static func scale(_ period: InsightsPeriod) -> Double {
        switch period {
        case .week: 7.0 / 30.0
        case .month: 1
        case .year: 365.0 / 30.0
        }
    }

    /// A month's count, scaled to the period. Never rounds a count
    /// above zero down to zero.
    private static func scaled(_ value: Int, _ period: InsightsPeriod) -> Int {
        guard value > 0 else { return 0 }
        return max(1, Int((Double(value) * scale(period)).rounded()))
    }

    /// A month's rate, scaled to the period.
    private static func rate(_ done: Int, _ total: Int, _ period: InsightsPeriod) -> InsightsRate {
        let scaledTotal = scaled(total, period)
        let scaledDone = min(scaledTotal, Int((Double(done) * scale(period)).rounded()))
        return InsightsRate(done: scaledDone, total: scaledTotal)
    }

    private static func minutes(of instant: Date) -> Int {
        calendar.component(.hour, from: instant) * 60 + calendar.component(.minute, from: instant)
    }

    private static func median(_ values: [Int]) -> Int? {
        guard !values.isEmpty else { return nil }
        return values.sorted()[values.count / 2]
    }
}
