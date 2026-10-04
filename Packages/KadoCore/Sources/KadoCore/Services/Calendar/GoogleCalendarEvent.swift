import Foundation

/// A Google event (or expanded recurring occurrence), separate from local task completion.
nonisolated public struct GoogleCalendarEvent: Decodable, Sendable, Equatable {
    public let id: String
    public let status: String?
    public let summary: String?
    public let description: String?
    public let htmlLink: String?
    public let updated: String?
    public let start: EventDate?
    public let end: EventDate?
    public let recurringEventId: String?

    public var isCancelled: Bool { status == "cancelled" }

    public init(id: String, status: String? = nil, summary: String? = nil,
                description: String? = nil, htmlLink: String? = nil, updated: String? = nil,
                start: EventDate? = nil, end: EventDate? = nil, recurringEventId: String? = nil) {
        self.id = id
        self.status = status
        self.summary = summary
        self.description = description
        self.htmlLink = htmlLink
        self.updated = updated
        self.start = start
        self.end = end
        self.recurringEventId = recurringEventId
    }

    nonisolated public struct EventDate: Decodable, Sendable, Equatable {
        public let date: String?
        public let dateTime: String?
        public let timeZone: String?

        public init(date: String? = nil, dateTime: String? = nil, timeZone: String? = nil) {
            self.date = date
            self.dateTime = dateTime
            self.timeZone = timeZone
        }

        public func resolved(using calendar: Calendar) -> Date? {
            if let dateTime { return GoogleCalendarEvent.parseTimestamp(dateTime) }
            guard let date else { return nil }
            let parts = date.split(separator: "-").compactMap { Int($0) }
            guard parts.count == 3 else { return nil }
            var components = DateComponents()
            components.year = parts[0]
            components.month = parts[1]
            components.day = parts[2]
            // Google's date-only wire format is Gregorian even when the device uses
            // a Buddhist, Islamic, or other presentation calendar.
            var gregorian = Calendar(identifier: .gregorian)
            gregorian.timeZone = calendar.timeZone
            guard let resolved = gregorian.date(from: components) else { return nil }
            let actual = gregorian.dateComponents([.year, .month, .day], from: resolved)
            guard actual.year == parts[0], actual.month == parts[1], actual.day == parts[2] else { return nil }
            return calendar.startOfDay(for: resolved)
        }
    }

    public static func parseTimestamp(_ raw: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let value = formatter.date(from: raw) { return value }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: raw)
    }

    /// All-day end dates are exclusive in Google's API.
    public func schedule(using calendar: Calendar) -> Schedule? {
        guard let start, let end,
              let startDate = start.resolved(using: calendar),
              let endDate = end.resolved(using: calendar), endDate > startDate else { return nil }
        let isAllDay = start.date != nil && end.date != nil
        guard isAllDay || (start.dateTime != nil && end.dateTime != nil) else { return nil }
        return Schedule(start: startDate, end: endDate, isAllDay: isAllDay)
    }

    nonisolated public struct Schedule: Sendable, Equatable {
        public let start: Date
        public let end: Date
        public let isAllDay: Bool
    }
}
