import Foundation
import SwiftData
import KadoCore

/// Keeps the monthly check-in reminders in step with the setting and
/// with which months are done. Called on foreground, after a check-in
/// and when the setting changes.
///
/// Passes run one at a time and read the store when they run, not when
/// they are asked for: two at once could interleave their remove and
/// add, and an older pass finishing last would put back the reminder
/// of a month just finished.
@MainActor
enum ReflectionReminders {
    private static var last: Task<Void, Never>?

    static func sync(using context: ModelContext) {
        let previous = last
        last = Task { @MainActor in
            await previous?.value
            let enabled = ReflectionDefaults.remindersEnabled
            let done = Set(((try? ReflectionStore(context: context).entries()) ?? []).filter(\.isComplete).map(\.month))
            let scheduler = ReflectionReminderScheduler(center: LiveUserNotificationCenter())
            await scheduler.reschedule(enabled: enabled, completedMonths: done)
        }
    }
}
