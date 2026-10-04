import Foundation

/// Validates a local one-off task's optional civil-day schedule before
/// persistence. Clock values can come from any DatePicker date; only
/// their hour and minute are applied to the selected day.
nonisolated public struct TaskScheduleDraft: Sendable {
    public let title: String
    public let day: Date?
    public let startTime: Date?
    public let endTime: Date?

    public init(title: String, day: Date? = nil, startTime: Date? = nil, endTime: Date? = nil) {
        self.title = title
        self.day = day
        self.startTime = startTime
        self.endTime = endTime
    }

    public func normalized(using calendar: Calendar = .current) throws -> NormalizedTaskSchedule {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { throw ValidationError.emptyTitle }
        guard let day else {
            guard startTime == nil && endTime == nil else { throw ValidationError.dayRequired }
            return NormalizedTaskSchedule(title: title, plannedDay: nil, startAt: nil, endAt: nil)
        }
        let plannedDay = calendar.startOfDay(for: day)
        let start = try clockTime(startTime, on: plannedDay, calendar: calendar)
        let end = try clockTime(endTime, on: plannedDay, calendar: calendar)
        if let start, let end, end <= start { throw ValidationError.endMustFollowStart }
        return NormalizedTaskSchedule(title: title, plannedDay: plannedDay, startAt: start, endAt: end)
    }

    private func clockTime(_ date: Date?, on day: Date, calendar: Calendar) throws -> Date? {
        guard let date else { return nil }
        let components = calendar.dateComponents([.hour, .minute], from: date)
        let hour = components.hour ?? 0
        let minute = components.minute ?? 0
        guard let result = calendar.date(
            bySettingHour: hour, minute: minute, second: 0, of: day,
            matchingPolicy: .strict, repeatedTimePolicy: .first, direction: .forward
        ), calendar.isDate(result, inSameDayAs: day),
            calendar.component(.hour, from: result) == hour,
            calendar.component(.minute, from: result) == minute
        else { throw ValidationError.timeUnavailableOnDay }
        return result
    }

    public enum ValidationError: Error, Equatable, Sendable {
        case emptyTitle
        case dayRequired
        case endMustFollowStart
        case timeUnavailableOnDay
    }
}

nonisolated public struct NormalizedTaskSchedule: Equatable, Sendable {
    public let title: String
    public let plannedDay: Date?
    public let startAt: Date?
    public let endAt: Date?
}
