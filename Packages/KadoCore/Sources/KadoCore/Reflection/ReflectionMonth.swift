import Foundation

/// A calendar month, named by its numbers. Reflections are about a
/// month as the user lived it, so October stays October in every time
/// zone; only `interval(in:)` turns it into instants.
nonisolated public struct ReflectionMonth: Hashable, Comparable, Codable, Identifiable, Sendable {
    public let year: Int
    /// 1 to 12.
    public let month: Int

    /// Normalizes an out-of-range month: (2026, 13) is January 2027.
    public init(year: Int, month: Int) {
        let zeroBased = month - 1
        let carry = zeroBased >= 0 ? zeroBased / 12 : (zeroBased - 11) / 12
        self.year = year + carry
        self.month = zeroBased - carry * 12 + 1
    }

    public init(containing date: Date, calendar: Calendar) {
        let parts = calendar.dateComponents([.year, .month], from: date)
        self.init(year: parts.year ?? 1970, month: parts.month ?? 1)
    }

    /// 202610 for October 2026: sorts like the month does.
    public var id: Int { year * 100 + month }

    public var previous: ReflectionMonth { adding(months: -1) }
    public var next: ReflectionMonth { adding(months: 1) }

    public func adding(months: Int) -> ReflectionMonth {
        ReflectionMonth(year: year, month: month + months)
    }

    /// From the first instant of the month to the first instant of the next.
    public func interval(in calendar: Calendar) -> DateInterval {
        let start = firstDay(in: calendar)
        let end = next.firstDay(in: calendar)
        return DateInterval(start: start, end: max(start, end))
    }

    public func contains(_ date: Date, calendar: Calendar) -> Bool {
        ReflectionMonth(containing: date, calendar: calendar) == self
    }

    /// The month's first day at its start (not always midnight: some
    /// zones skip it on a DST day).
    public func firstDay(in calendar: Calendar) -> Date {
        let noon = calendar.date(from: DateComponents(year: year, month: month, day: 1, hour: 12)) ?? .distantPast
        return calendar.startOfDay(for: noon)
    }

    /// The month's last day at its start.
    public func lastDay(in calendar: Calendar) -> Date {
        let first = next.firstDay(in: calendar)
        let lastNoon = calendar.date(byAdding: .hour, value: -12, to: first) ?? first
        return calendar.startOfDay(for: lastNoon)
    }

    /// "October 2026" in the calendar's locale.
    public func title(in calendar: Calendar) -> String {
        firstDay(in: calendar).formatted(.dateTime.month(.wide).year().locale(calendar.locale ?? .current))
    }

    /// "October" in the calendar's locale.
    public func monthName(in calendar: Calendar) -> String {
        firstDay(in: calendar).formatted(.dateTime.month(.wide).locale(calendar.locale ?? .current))
    }

    public static func < (lhs: ReflectionMonth, rhs: ReflectionMonth) -> Bool { lhs.id < rhs.id }
}
