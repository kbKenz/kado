import Foundation
import SwiftData

/// Converts a *complete* bounded Google snapshot into tasks and planned blocks.
/// Remote edits never change local completion or user archive state.
///
/// Nonisolated: it writes through a context of its own, so the app can
/// run it off the main actor and the UI context picks the save up.
public struct GoogleCalendarImporter: Sendable {
    private let calendar: Calendar

    public init(calendar: Calendar = .current) { self.calendar = calendar }

    @discardableResult
    public func apply(events: [GoogleCalendarEvent], accountID: String, calendarID: String,
                      window: DateInterval, to context: ModelContext) throws -> Int {
        try apply(events: events, accountID: accountID, calendarID: calendarID,
                  window: window, in: context.container)
    }

    /// Imports into `container` through a context created here, on the
    /// caller's thread — safe to call from a detached task.
    @discardableResult
    public func apply(events: [GoogleCalendarEvent], accountID: String, calendarID: String,
                      window: DateInterval, in container: ModelContainer) throws -> Int {
        // Validate before any writes. A malformed active event must not turn a partial response
        // into cancellations for the rest of the calendar. The schedule is kept so the
        // import below doesn't parse every timestamp a second time.
        var incoming: [String: (event: GoogleCalendarEvent, schedule: GoogleCalendarEvent.Schedule?)] = [:]
        for event in events {
            guard !event.id.isEmpty else { throw GoogleCalendarImportError.invalidEvent }
            let schedule = event.isCancelled ? nil : event.schedule(using: calendar)
            guard event.isCancelled || schedule != nil else {
                throw GoogleCalendarImportError.invalidEvent
            }
            incoming[event.id] = (event, schedule)
        }

        // A dedicated context keeps failed sync from rolling back an unrelated UI edit.
        let syncContext = ModelContext(container)
        syncContext.autosaveEnabled = false
        // Only this calendar's copies, with their plans in the same fetch: the loops below
        // read `scheduleBlocks` on most of them, one fault each otherwise. App-only code,
        // so the predicate's widget-extension trap doesn't apply.
        let account: String? = accountID
        let calendarKey: String? = calendarID
        var descriptor = FetchDescriptor<TaskRecord>(predicate: #Predicate {
            $0.externalAccountID == account && $0.externalCalendarID == calendarKey
        })
        descriptor.relationshipKeyPathsForPrefetching = [\.scheduleBlocks]
        let records = try syncContext.fetch(descriptor)
        var linked: [String: TaskRecord] = [:]
        for record in records {
            if let id = record.externalEventID, linked[id] == nil { linked[id] = record }
        }
        let now = Date.now
        var importedCount = 0
        do {
            for (event, schedule) in incoming.values {
                if event.isCancelled {
                    if let record = linked[event.id], record.externalCancelledAt == nil {
                        record.externalCancelledAt = now
                        record.updatedAt = now
                    }
                    continue
                }
                guard let schedule else { continue }
                let record: TaskRecord
                if let existing = linked[event.id] {
                    record = existing
                } else {
                    record = TaskRecord()
                    syncContext.insert(record)
                    linked[event.id] = record
                }
                let title = event.summary?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty ?? String(localized: "Untitled event")
                let notes = event.description ?? ""
                let dueDate = calendar.startOfDay(for: schedule.start)
                let externalUpdatedAt = event.updated.flatMap(GoogleCalendarEvent.parseTimestamp)
                if record.title != title || record.notes != notes || record.dueDate != dueDate
                    || record.externalAccountID != accountID || record.externalCalendarID != calendarID
                    || record.externalEventID != event.id || record.externalURL != event.htmlLink
                    || record.externalUpdatedAt != externalUpdatedAt || record.externalCancelledAt != nil {
                    record.title = title
                    record.notes = notes
                    record.dueDate = dueDate
                    record.externalAccountID = accountID
                    record.externalCalendarID = calendarID
                    record.externalEventID = event.id
                    record.externalURL = event.htmlLink
                    record.externalUpdatedAt = externalUpdatedAt
                    record.externalCancelledAt = nil
                    record.updatedAt = now
                }
                replaceBlocks(for: record, schedule: schedule, window: window, in: syncContext, now: now)
                importedCount += 1
            }

            // A missing event can be deleted, declined, or moved outside the window. Only reconcile
            // copies whose former plan overlaps this successful snapshot; older history stays intact.
            for (id, record) in linked where incoming[id] == nil {
                if record.externalCancelledAt == nil,
                   (record.scheduleBlocks ?? []).contains(where: { overlaps($0, window: window) }) {
                    record.externalCancelledAt = now
                    record.updatedAt = now
                }
            }
            if syncContext.hasChanges { try syncContext.save() }
        } catch {
            syncContext.rollback()
            throw error
        }
        return importedCount
    }

    private func replaceBlocks(for task: TaskRecord, schedule: GoogleCalendarEvent.Schedule,
                               window: DateInterval, in context: ModelContext, now: Date) {
        let old = (task.scheduleBlocks ?? []).sorted { $0.plannedDay < $1.plannedDay }
        if schedule.isAllDay {
            // The snapshot only requests a bounded interval. An
            // unchanged multi-day event may have already imported
            // plans outside that moving window; retain those while
            // removing days excluded by an actual remote date edit.
            var byDay: [Date: ScheduleBlockRecord] = [:]
            for block in old {
                let day = calendar.startOfDay(for: block.plannedDay)
                guard day >= schedule.start, day < schedule.end, byDay[day] == nil else {
                    context.delete(block)
                    continue
                }
                if block.plannedDay != day || block.startAt != nil || block.endAt != nil {
                    block.plannedDay = day
                    block.startAt = nil
                    block.endAt = nil
                    block.updatedAt = now
                }
                byDay[day] = block
            }
            var day = calendar.startOfDay(for: max(schedule.start, window.start))
            let end = min(schedule.end, window.end)
            while day < end {
                if byDay[day] == nil {
                    let block = ScheduleBlockRecord(
                        plannedDay: day, createdAt: now, updatedAt: now, task: task
                    )
                    context.insert(block)
                    byDay[day] = block
                }
                guard let next = calendar.date(byAdding: .day, value: 1, to: day), next > day else { break }
                day = calendar.startOfDay(for: next)
            }
            return
        }
        // Reuse identities rather than replacing every block on a refresh.
        let block: ScheduleBlockRecord
        if let existing = old.first {
            block = existing
        } else {
            block = ScheduleBlockRecord(createdAt: now, updatedAt: now, task: task)
            context.insert(block)
        }
        let plannedDay = calendar.startOfDay(for: schedule.start)
        if block.plannedDay != plannedDay || block.startAt != schedule.start || block.endAt != schedule.end {
            block.plannedDay = plannedDay
            block.startAt = schedule.start
            block.endAt = schedule.end
            block.updatedAt = now
        }
        for extra in old.dropFirst() { context.delete(extra) }
    }

    private func overlaps(_ block: ScheduleBlockRecord, window: DateInterval) -> Bool {
        let start = block.startAt ?? block.plannedDay
        let nextDay = calendar.date(byAdding: .day, value: 1, to: block.plannedDay)
            .map { calendar.startOfDay(for: $0) } ?? block.plannedDay
        let end = block.endAt ?? nextDay
        return start < window.end && end > window.start
    }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}

nonisolated public enum GoogleCalendarImportError: LocalizedError {
    case invalidEvent
    public var errorDescription: String? { String(localized: "A Google event has an invalid date. No calendar changes were imported.") }
}
