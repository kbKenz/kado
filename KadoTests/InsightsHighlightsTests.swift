import Foundation
import Testing
@testable import KadoCore

/// Highlights read the finished report, so every test here builds the
/// report by hand instead of running the other sections.
@Suite("Insights highlights")
struct InsightsHighlightsTests {
    typealias T = InsightsTestSupport

    private func highlights(_ report: InsightsReport) -> [InsightsHighlight] {
        InsightsCalculator.highlights(report, T.scope(.empty, T.context(period: .month)))
    }

    private func report(
        pulse: InsightsPulse = .empty,
        activity: InsightsActivity = .empty,
        focus: InsightsFocus = .empty,
        categories: [InsightsCategoryRow] = [],
        habits: [InsightsHabitRow] = [],
        tasks: InsightsTasks = .empty,
        rhythm: InsightsRhythm = .empty
    ) -> InsightsReport {
        InsightsReport(
            period: .month,
            days: [],
            pulse: pulse,
            activity: activity,
            focus: focus,
            categories: categories,
            habits: habits,
            tasks: tasks,
            rhythm: rhythm,
            isEmpty: false
        )
    }

    private func habit(
        _ name: String,
        type: HabitType = .binary,
        current: Int = 0,
        best: Int = 0,
        timesDone: Int = 0,
        allTime: Int = 0
    ) -> InsightsHabitRow {
        InsightsHabitRow(
            habitID: UUID(),
            name: name,
            icon: "circle",
            color: .blue,
            category: .other,
            type: type,
            timesDone: timesDone,
            allTimeTimesDone: allTime,
            currentStreak: current,
            bestStreak: best
        )
    }

    private func pulse(_ current: InsightsRate, _ previous: InsightsRate) -> InsightsPulse {
        InsightsPulse(consistency: current, previousConsistency: previous)
    }

    /// `parts` are the focus seconds in `InsightsPartOfDay.allCases`
    /// order. Only `best` gets `rate`.
    private func rhythm(
        best: Weekday? = nil,
        rate: InsightsRate = .empty,
        parts: [TimeInterval] = [0, 0, 0, 0],
        peak: InsightsPartOfDay? = nil
    ) -> InsightsRhythm {
        InsightsRhythm(
            weekdays: Weekday.week(startingOn: 1).map {
                InsightsWeekdayRate(weekday: $0, rate: $0 == best ? rate : .empty)
            },
            bestWeekday: best,
            focusByPartOfDay: zip(InsightsPartOfDay.allCases, parts).map {
                InsightsPartOfDayFocus(part: $0, seconds: $1)
            },
            peakPartOfDay: peak
        )
    }

    @Test("An empty report has nothing to say")
    func empty() {
        #expect(highlights(InsightsReport(period: .week, days: [])).isEmpty)
    }

    // MARK: - One rule at a time

    @Test("Streak record: the highest current streak that equals its best, at least 3")
    func streakRecord() {
        let rows = [
            habit("Read", current: 5, best: 5),
            habit("Run", current: 7, best: 9), // the longest, but not a record
            habit("Walk", current: 6, best: 6),
        ]
        // Rule 1 fired, so the longest streak (Run) is not added.
        #expect(highlights(report(habits: rows)) == [.streakRecord(habitName: "Walk", days: 6)])
    }

    @Test("Streak record: ties go to the first row; 2 days is not enough")
    func streakRecordEdges() {
        let tie = [habit("Read", current: 4, best: 4), habit("Walk", current: 4, best: 4)]
        #expect(highlights(report(habits: tie)) == [.streakRecord(habitName: "Read", days: 4)])
        #expect(highlights(report(habits: [habit("Read", current: 2, best: 2)])).isEmpty)
    }

    @Test("Consistency change: at least 5 points up or down, rounded")
    func consistencyChange() {
        let up = pulse(InsightsRate(done: 8, total: 10), InsightsRate(done: 7, total: 10))
        #expect(highlights(report(pulse: up)) == [.consistencyChange(points: 10)])
        let down = pulse(InsightsRate(done: 3, total: 5), InsightsRate(done: 4, total: 5))
        #expect(highlights(report(pulse: down)) == [.consistencyChange(points: -20)])
        // 80% against 75%: exactly 5 points.
        let five = pulse(InsightsRate(done: 4, total: 5), InsightsRate(done: 3, total: 4))
        #expect(highlights(report(pulse: five)) == [.consistencyChange(points: 5)])
        // 80% against 76%: 4 points.
        let four = pulse(InsightsRate(done: 4, total: 5), InsightsRate(done: 19, total: 25))
        #expect(highlights(report(pulse: four)).isEmpty)
    }

    @Test("Consistency change needs both periods")
    func consistencyChangeNeedsBothPeriods() {
        let noPrevious = pulse(InsightsRate(done: 9, total: 10), .empty)
        #expect(highlights(report(pulse: noPrevious)).isEmpty)
    }

    @Test("Most undone category: the first with at least 3 tasks and 30% left undone")
    func mostUndoneCategory() {
        let tasks = InsightsTasks(undoneByCategory: [
            InsightsCategoryUndone(category: .errands, undone: 2, total: 2), // fewer than 3 tasks
            InsightsCategoryUndone(category: .home, undone: 1, total: 4),    // 25%
            InsightsCategoryUndone(category: .work, undone: 3, total: 10),   // exactly 30%
        ])
        #expect(highlights(report(tasks: tasks)) == [.mostUndoneCategory(.work, undone: 3, total: 10)])
    }

    @Test("Top focus category: the most focus time, at least 30 minutes; ties go to the first row")
    func topFocusCategory() {
        let rows = [
            InsightsCategoryRow(category: .study, focusSeconds: 3600),
            InsightsCategoryRow(category: .work, focusSeconds: 5400),
            InsightsCategoryRow(category: .fitness, focusSeconds: 5400),
        ]
        #expect(highlights(report(categories: rows)) == [.topFocusCategory(.work, seconds: 5400)])
        let short = [InsightsCategoryRow(category: .study, focusSeconds: 1799)]
        #expect(highlights(report(categories: short)).isEmpty)
    }

    @Test("Perfect days: at least one")
    func perfectDays() {
        #expect(highlights(report(activity: InsightsActivity(perfectDays: 3))) == [.perfectDays(count: 3)])
        #expect(highlights(report(activity: InsightsActivity(perfectDays: 0))).isEmpty)
    }

    @Test("Peak focus time: the peak part with at least 40% of the focus time")
    func peakFocusTime() {
        let strong = rhythm(parts: [3000, 1000, 1000, 0], peak: .morning)
        #expect(highlights(report(rhythm: strong)) == [.peakFocusTime(.morning, share: 0.6)])
        let edge = rhythm(parts: [1500, 2000, 1500, 0], peak: .afternoon)
        #expect(highlights(report(rhythm: edge)) == [.peakFocusTime(.afternoon, share: 0.4)])
        let flat = rhythm(parts: [1500, 1400, 1300, 800], peak: .morning)
        #expect(highlights(report(rhythm: flat)).isEmpty)
        let noPeak = rhythm(parts: [3000, 0, 0, 0])
        #expect(highlights(report(rhythm: noPeak)).isEmpty)
    }

    @Test("Best weekday: at least 50%")
    func bestWeekday() {
        let good = rhythm(best: .tuesday, rate: InsightsRate(done: 3, total: 4))
        #expect(highlights(report(rhythm: good)) == [.bestWeekday(.tuesday, fraction: 0.75)])
        let half = rhythm(best: .friday, rate: InsightsRate(done: 2, total: 4))
        #expect(highlights(report(rhythm: half)) == [.bestWeekday(.friday, fraction: 0.5)])
        let low = rhythm(best: .tuesday, rate: InsightsRate(done: 1, total: 4))
        #expect(highlights(report(rhythm: low)).isEmpty)
    }

    @Test("Milestone: the largest mark a habit passed during the period")
    func milestone() {
        let rows = [
            habit("Water", timesDone: 4, allTime: 12),  // passed 10
            habit("Read", timesDone: 5, allTime: 27),   // passed 25
            habit("Walk", timesDone: 2, allTime: 60),   // passed 50 before the period
        ]
        #expect(highlights(report(habits: rows)) == [.milestone(habitName: "Read", count: 25)])
        // From 9 to 30 in the period passes both 10 and 25: the larger one wins.
        let jump = [habit("Stretch", timesDone: 21, allTime: 30)]
        #expect(highlights(report(habits: jump)) == [.milestone(habitName: "Stretch", count: 25)])
    }

    @Test("Milestone: ties go to the first row, and slips are never a milestone")
    func milestoneEdges() {
        let tie = [habit("Water", timesDone: 3, allTime: 11), habit("Read", timesDone: 1, allTime: 10)]
        #expect(highlights(report(habits: tie)) == [.milestone(habitName: "Water", count: 10)])
        let slips = [habit("Smoking", type: .negative, timesDone: 4, allTime: 12)]
        #expect(highlights(report(habits: slips)).isEmpty)
    }

    @Test("Longest streak: the highest current streak of at least 3, when no streak is a record")
    func longestStreak() {
        let rows = [
            habit("Read", current: 5, best: 8),
            habit("Run", current: 6, best: 9),
            habit("Walk", current: 6, best: 7),
        ]
        #expect(highlights(report(habits: rows)) == [.longestStreak(habitName: "Run", days: 6)])
        #expect(highlights(report(habits: [habit("Read", current: 2, best: 5)])).isEmpty)
    }

    @Test("Focus total: at least one hour")
    func focusTotal() {
        #expect(highlights(report(focus: InsightsFocus(total: 3600))) == [.focusTotal(seconds: 3600)])
        #expect(highlights(report(focus: InsightsFocus(total: 3599))).isEmpty)
    }

    // MARK: - Order and limit

    @Test("When every rule applies, the first four rules win, in order")
    func firstFourRules() {
        let busy = report(
            pulse: pulse(InsightsRate(done: 8, total: 10), InsightsRate(done: 7, total: 10)),
            activity: InsightsActivity(perfectDays: 2),
            focus: InsightsFocus(total: 7200),
            categories: [InsightsCategoryRow(category: .study, focusSeconds: 3600)],
            habits: [habit("Read", current: 4, best: 4, timesDone: 6, allTime: 12)],
            tasks: InsightsTasks(undoneByCategory: [InsightsCategoryUndone(category: .errands, undone: 2, total: 4)]),
            rhythm: rhythm(best: .tuesday, rate: InsightsRate(done: 3, total: 4), parts: [3000, 1000, 1000, 0], peak: .morning)
        )
        #expect(highlights(busy) == [
            .streakRecord(habitName: "Read", days: 4),
            .consistencyChange(points: 10),
            .mostUndoneCategory(.errands, undone: 2, total: 4),
            .topFocusCategory(.study, seconds: 3600),
        ])
    }

    @Test("Later rules fill the four places when the first ones do not apply")
    func laterRules() {
        let quiet = report(
            activity: InsightsActivity(perfectDays: 2),
            focus: InsightsFocus(total: 7200),
            habits: [habit("Read", current: 5, best: 8, timesDone: 6, allTime: 12)],
            rhythm: rhythm(best: .tuesday, rate: InsightsRate(done: 3, total: 4), parts: [3000, 1000, 1000, 0], peak: .morning)
        )
        #expect(highlights(quiet) == [
            .perfectDays(count: 2),
            .peakFocusTime(.morning, share: 0.6),
            .bestWeekday(.tuesday, fraction: 0.75),
            .milestone(habitName: "Read", count: 10),
        ])
        let lastTwo = report(
            focus: InsightsFocus(total: 7200),
            habits: [habit("Read", current: 5, best: 8)]
        )
        #expect(highlights(lastTwo) == [
            .longestStreak(habitName: "Read", days: 5),
            .focusTotal(seconds: 7200),
        ])
    }
}
