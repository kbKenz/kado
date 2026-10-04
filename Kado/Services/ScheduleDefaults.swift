import Foundation

/// What the schedule rows fill in when the user taps "Add start time",
/// "Add end time", Today or Tomorrow. A task's time is stored as hour
/// and minute on its planned day (`TaskScheduleDraft`), so no default
/// may cross midnight.
nonisolated enum ScheduleDefaults {
    static let defaultStartHour = 9
    static let latestStartHour = 23

    /// Today: the next full hour (at most 23:00). Any other day: 09:00.
    static func startTime(on day: Date, now: Date, calendar: Calendar) -> Date {
        let dayStart = calendar.startOfDay(for: day)
        var hour = defaultStartHour
        if calendar.isDate(day, inSameDayAs: now) {
            hour = min(calendar.component(.hour, from: now) + 1, latestStartHour)
        }
        return calendar.date(bySettingHour: hour, minute: 0, second: 0, of: dayStart) ?? dayStart
    }

    /// `now` rounded to the nearest quarter hour (14:07 → 14:00,
    /// 14:08 → 14:15), for work that starts now. Capped at 23:45 so it
    /// stays on `now`'s day.
    static func nearestQuarterHour(to now: Date, calendar: Calendar) -> Date {
        let dayStart = calendar.startOfDay(for: now)
        let parts = calendar.dateComponents([.hour, .minute], from: now)
        let minutes = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        let rounded = min(Int((Double(minutes) / 15).rounded()) * 15, 23 * 60 + 45)
        return calendar.date(bySettingHour: rounded / 60, minute: rounded % 60, second: 0, of: dayStart) ?? now
    }

    /// One hour after `start` (or after the default start), capped at
    /// 23:59 on the same day.
    static func endTime(on day: Date, start: Date?, now: Date, calendar: Calendar) -> Date {
        let base = start ?? startTime(on: day, now: now, calendar: calendar)
        let dayStart = calendar.startOfDay(for: base)
        let lastMinute = calendar.date(bySettingHour: 23, minute: 59, second: 0, of: dayStart) ?? base
        guard let oneHourLater = calendar.date(byAdding: .hour, value: 1, to: base),
              calendar.isDate(oneHourLater, inSameDayAs: base)
        else { return lastMinute }
        return min(oneHourLater, lastMinute)
    }

    static func quickDays(today: Date, calendar: Calendar) -> (today: Date, tomorrow: Date) {
        let start = calendar.startOfDay(for: today)
        let next = calendar.date(byAdding: .day, value: 1, to: start) ?? start
        return (start, calendar.startOfDay(for: next))
    }
}
