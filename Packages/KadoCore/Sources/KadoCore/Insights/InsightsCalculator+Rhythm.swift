import Foundation

extension InsightsCalculator {
    /// Consistency by weekday and focus by part of the day.
    /// Rules: see `InsightsRhythm` in InsightsReport.swift.
    static func rhythm(_ scope: InsightsScope) -> InsightsRhythm {
        let calendar = scope.calendar
        var rates: [Weekday: InsightsRate] = [:]
        var dates: [Weekday: Int] = [:]
        for day in scope.days {
            guard let weekday = Weekday(rawValue: calendar.component(.weekday, from: day)) else { continue }
            dates[weekday, default: 0] += 1
            for habit in scope.input.habits {
                guard case .due(let done) = scope.outcome(of: habit, on: day) else { continue }
                rates[weekday, default: .empty].total += 1
                if done { rates[weekday, default: .empty].done += 1 }
            }
        }
        let weekdays = Weekday.week(startingOn: calendar.firstWeekday).map { weekday in
            InsightsWeekdayRate(weekday: weekday, rate: rates[weekday] ?? .empty)
        }

        let sessions = InsightsSharedB.trackedSessions(scope, on: scope.days)
        var seconds: [InsightsPartOfDay: TimeInterval] = [:]
        for session in sessions {
            let hour = calendar.component(.hour, from: session.source.session.startedAt)
            seconds[InsightsPartOfDay.of(hour: hour), default: 0] += session.seconds
        }
        let parts = InsightsPartOfDay.allCases.map { part in
            InsightsPartOfDayFocus(part: part, seconds: seconds[part] ?? 0)
        }

        return InsightsRhythm(
            weekdays: weekdays,
            bestWeekday: scope.context.period == .week ? nil : InsightsSharedB.strongestWeekday(weekdays, dates: dates),
            focusByPartOfDay: parts,
            peakPartOfDay: sessions.count >= 3 ? InsightsSharedB.peakPart(parts) : nil
        )
    }
}

private extension InsightsSharedB {
    /// The weekday with the highest share, among weekdays seen on at
    /// least 2 dates with at least 2 due habit-days. On a tie the
    /// weekday that comes first in `weekdays` stays.
    static func strongestWeekday(_ weekdays: [InsightsWeekdayRate], dates: [Weekday: Int]) -> Weekday? {
        var best: InsightsWeekdayRate?
        for entry in weekdays where (dates[entry.weekday] ?? 0) >= 2 && entry.rate.total >= 2 {
            if let kept = best {
                // Cross products keep equal shares exactly equal.
                guard entry.rate.done * kept.rate.total > kept.rate.done * entry.rate.total else { continue }
            }
            best = entry
        }
        return best?.weekday
    }

    /// The part with the most seconds. On a tie the earlier part stays.
    static func peakPart(_ parts: [InsightsPartOfDayFocus]) -> InsightsPartOfDay? {
        var peak: InsightsPartOfDayFocus?
        for part in parts where part.seconds > (peak?.seconds ?? 0) {
            peak = part
        }
        return peak?.part
    }
}
