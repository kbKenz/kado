import Foundation

extension InsightsCalculator {
    /// Up to four facts, picked from the finished sections.
    /// Rules: see `InsightsHighlight` in InsightsReport.swift.
    static func highlights(_ report: InsightsReport, _ scope: InsightsScope) -> [InsightsHighlight] {
        let record = InsightsSharedB.streakRecord(report.habits)
        // The rules in order. The first four that apply are kept.
        let facts: [InsightsHighlight?] = [
            record,
            InsightsSharedB.consistencyChange(report.pulse),
            InsightsSharedB.mostUndoneCategory(report.tasks),
            InsightsSharedB.topFocusCategory(report.categories),
            report.activity.perfectDays >= 1 ? .perfectDays(count: report.activity.perfectDays) : nil,
            InsightsSharedB.peakFocusTime(report.rhythm),
            InsightsSharedB.bestWeekday(report.rhythm),
            InsightsSharedB.milestone(report.habits),
            // A record already names the longest streak worth telling.
            record == nil ? InsightsSharedB.longestStreak(report.habits) : nil,
            report.focus.total >= 3600 ? .focusTotal(seconds: report.focus.total) : nil,
        ]
        return Array(facts.compactMap { $0 }.prefix(4))
    }
}

private extension InsightsSharedB {
    /// Rule 1: the highest current streak of at least 3 that equals the
    /// habit's best. On a tie the first row stays.
    static func streakRecord(_ habits: [InsightsHabitRow]) -> InsightsHighlight? {
        var top: InsightsHabitRow?
        for row in habits where row.currentStreak >= 3 && row.currentStreak >= row.bestStreak {
            if row.currentStreak > (top?.currentStreak ?? 0) { top = row }
        }
        return top.map { .streakRecord(habitName: $0.name, days: $0.currentStreak) }
    }

    /// Rule 2: habit consistency moved by at least 5 points.
    static func consistencyChange(_ pulse: InsightsPulse) -> InsightsHighlight? {
        guard let current = pulse.consistency.fraction,
              let previous = pulse.previousConsistency.fraction else { return nil }
        let points = Int(((current - previous) * 100).rounded())
        return abs(points) >= 5 ? .consistencyChange(points: points) : nil
    }

    /// Rule 3: the first category with at least 3 tasks and at least 30%
    /// of them left undone.
    static func mostUndoneCategory(_ tasks: InsightsTasks) -> InsightsHighlight? {
        // `undone / total >= 0.3`, kept in whole numbers.
        let entry = tasks.undoneByCategory.first { $0.total >= 3 && $0.undone * 10 >= $0.total * 3 }
        return entry.map { .mostUndoneCategory($0.category, undone: $0.undone, total: $0.total) }
    }

    /// Rule 4: the category with the most focus time, at least 30
    /// minutes. On a tie the first row stays.
    static func topFocusCategory(_ categories: [InsightsCategoryRow]) -> InsightsHighlight? {
        var top: InsightsCategoryRow?
        for row in categories where row.focusSeconds > (top?.focusSeconds ?? 0) {
            top = row
        }
        guard let top, top.focusSeconds >= 1800 else { return nil }
        return .topFocusCategory(top.category, seconds: top.focusSeconds)
    }

    /// Rule 6: the peak part of the day, with at least 40% of the focus
    /// time.
    static func peakFocusTime(_ rhythm: InsightsRhythm) -> InsightsHighlight? {
        guard let peak = rhythm.peakPartOfDay else { return nil }
        let total = rhythm.focusByPartOfDay.reduce(0) { $0 + $1.seconds }
        guard total > 0 else { return nil }
        let seconds = rhythm.focusByPartOfDay.first { $0.part == peak }?.seconds ?? 0
        let share = seconds / total
        return share >= 0.4 ? .peakFocusTime(peak, share: share) : nil
    }

    /// Rule 7: the best weekday, done at least half the time.
    static func bestWeekday(_ rhythm: InsightsRhythm) -> InsightsHighlight? {
        guard let weekday = rhythm.bestWeekday,
              let fraction = rhythm.weekdays.first(where: { $0.weekday == weekday })?.rate.fraction,
              fraction >= 0.5 else { return nil }
        return .bestWeekday(weekday, fraction: fraction)
    }

    /// Rule 8: the largest mark a habit passed during the period. On a
    /// tie the first row stays. A negative habit counts slips, so it
    /// never has a milestone.
    static func milestone(_ habits: [InsightsHabitRow]) -> InsightsHighlight? {
        let marks = [10, 25, 50, 100, 250, 500, 1000]
        var top: (name: String, mark: Int)?
        for row in habits where !isNegative(row.type) {
            let before = row.allTimeTimesDone - row.timesDone
            guard let mark = marks.last(where: { row.allTimeTimesDone >= $0 && before < $0 }) else { continue }
            if mark > (top?.mark ?? 0) { top = (row.name, mark) }
        }
        return top.map { .milestone(habitName: $0.name, count: $0.mark) }
    }

    /// Rule 9: the highest current streak of at least 3. On a tie the
    /// first row stays.
    static func longestStreak(_ habits: [InsightsHabitRow]) -> InsightsHighlight? {
        var top: InsightsHabitRow?
        for row in habits where row.currentStreak >= 3 && row.currentStreak > (top?.currentStreak ?? 0) {
            top = row
        }
        return top.map { .longestStreak(habitName: $0.name, days: $0.currentStreak) }
    }
}
