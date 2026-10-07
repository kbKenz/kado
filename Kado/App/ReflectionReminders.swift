import Foundation
import SwiftData
import KadoCore

/// Keeps the monthly check-in reminders in step with the setting and
/// with which months are done. Called at launch, on foreground, after a
/// check-in and when the setting changes.
@MainActor
enum ReflectionReminders {
    static func sync(using context: ModelContext) {
        let enabled = ReflectionDefaults.remindersEnabled
        let done = Set(((try? ReflectionStore(context: context).entries()) ?? []).filter(\.isComplete).map(\.month))
        let scheduler = ReflectionReminderScheduler(center: LiveUserNotificationCenter())
        Task { await scheduler.reschedule(enabled: enabled, completedMonths: done) }
    }
}
