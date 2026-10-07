import Foundation
import UserNotifications

/// The monthly check-in reminder: one notification on the last day of
/// each of the next few months, in the evening. Its own identifier
/// prefix, so the habit reminders' reschedule never removes it.
nonisolated public struct ReflectionReminderScheduler: Sendable {
    public static let identifierPrefix = "kado.reflection."
    /// The key of the month, `yyyy-MM`, in the notification's user info.
    public static let monthUserInfoKey = "reflectionMonth"
    public static let monthsAhead = 3
    public static let hour = 19

    let center: any UserNotificationCenterProtocol
    let calendar: Calendar
    let now: @Sendable () -> Date

    public init(center: any UserNotificationCenterProtocol, calendar: Calendar = .current,
                now: @escaping @Sendable () -> Date = { Date() }) {
        self.center = center
        self.calendar = calendar
        self.now = now
    }

    /// Replaces every pending check-in reminder. Months already checked
    /// in get none; nothing is scheduled while `enabled` is false.
    public func reschedule(enabled: Bool, completedMonths: Set<ReflectionMonth>) async {
        let pending = await center.pendingNotificationRequests()
        let ours = pending.map(\.identifier).filter { $0.hasPrefix(Self.identifierPrefix) }
        if !ours.isEmpty { await center.removePendingNotificationRequests(withIdentifiers: ours) }
        guard enabled else { return }
        for request in requests(completedMonths: completedMonths) {
            try? await center.add(request)
        }
    }

    /// The requests `reschedule` adds, in date order.
    public func requests(completedMonths: Set<ReflectionMonth>) -> [UNNotificationRequest] {
        let start = ReflectionMonth(containing: now(), calendar: calendar)
        return (0..<Self.monthsAhead).compactMap { offset in
            let month = start.adding(months: offset)
            guard !completedMonths.contains(month),
                  let fireDate = fireDate(for: month), fireDate > now() else { return nil }
            return request(for: month, at: fireDate)
        }
    }

    /// The last day of `month` at `hour`.
    public func fireDate(for month: ReflectionMonth) -> Date? {
        calendar.date(bySettingHour: Self.hour, minute: 0, second: 0, of: month.lastDay(in: calendar))
    }

    public static func key(for month: ReflectionMonth) -> String { month.key }

    public static func month(fromKey key: String) -> ReflectionMonth? { ReflectionMonth(key: key) }

    private func request(for month: ReflectionMonth, at date: Date) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = String(localized: "Monthly check-in", comment: "Notification title: time for the monthly reflection.")
        let name = month.monthName(in: calendar)
        content.body = String(
            localized: "Take 15 minutes to look back at \(name).",
            comment: "Notification body for the monthly reflection. Argument: the month's name."
        )
        content.sound = .default
        content.userInfo = [Self.monthUserInfoKey: Self.key(for: month)]
        var components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        components.timeZone = calendar.timeZone
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        return UNNotificationRequest(identifier: Self.identifierPrefix + Self.key(for: month), content: content, trigger: trigger)
    }
}
