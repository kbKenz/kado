import Foundation
import SwiftData
import Testing
@testable import Kado
import KadoCore

@Suite("Google calendar task import")
@MainActor
struct GoogleCalendarImporterTests {
    private let accountID = "google-account"
    private let calendarID = "primary"

    private func container() throws -> ModelContainer {
        let schema = Schema(versionedSchema: KadoSchemaV10.self)
        return try ModelContainer(
            for: schema,
            configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        )
    }

    private func window(_ calendar: Calendar = TestCalendar.utc) -> DateInterval {
        DateInterval(
            start: TestCalendar.instant(calendar, 2026, 4, 13),
            end: TestCalendar.instant(calendar, 2026, 4, 20)
        )
    }

    private func event(
        id: String = "meeting", title: String = "Meeting with Thomas",
        start: String = "2026-04-13T09:00:00Z", end: String = "2026-04-13T10:00:00Z"
    ) -> GoogleCalendarEvent {
        GoogleCalendarEvent(
            id: id, summary: title, description: "Review plans",
            htmlLink: "https://calendar.google.com/event/\(id)",
            updated: "2026-04-12T10:00:00.123Z",
            start: .init(dateTime: start), end: .init(dateTime: end)
        )
    }

    private func apply(
        _ events: [GoogleCalendarEvent], to store: ModelContainer,
        calendar: Calendar = TestCalendar.utc, window: DateInterval? = nil,
        account: String? = nil
    ) throws -> Int {
        try GoogleCalendarImporter(calendar: calendar).apply(
            events: events, accountID: account ?? accountID, calendarID: calendarID,
            window: window ?? self.window(calendar), to: store.mainContext
        )
    }

    /// The importer writes with a separate context. Assertions must
    /// fetch through a new context rather than retain stale UI objects.
    private struct ReadBlock {
        let id: UUID
        let plannedDay: Date
        let startAt: Date?
        let endAt: Date?
        let updatedAt: Date
    }

    private struct ReadTask {
        let id: UUID
        let title: String
        let dueDate: Date?
        let updatedAt: Date
        let completedAt: Date?
        let archivedAt: Date?
        let externalAccountID: String?
        let externalCalendarID: String?
        let externalEventID: String?
        let externalUpdatedAt: Date?
        let externalCancelledAt: Date?
        let scheduleBlocks: [ReadBlock]?
    }

    private func tasks(_ store: ModelContainer) throws -> [ReadTask] {
        let context = ModelContext(store)
        return try context.fetch(FetchDescriptor<TaskRecord>()).map { task in
            ReadTask(
                id: task.id, title: task.title, dueDate: task.dueDate, updatedAt: task.updatedAt,
                completedAt: task.completedAt, archivedAt: task.archivedAt,
                externalAccountID: task.externalAccountID, externalCalendarID: task.externalCalendarID,
                externalEventID: task.externalEventID, externalUpdatedAt: task.externalUpdatedAt,
                externalCancelledAt: task.externalCancelledAt,
                scheduleBlocks: task.scheduleBlocks.map { blocks in
                    blocks.map { ReadBlock(id: $0.id, plannedDay: $0.plannedDay, startAt: $0.startAt, endAt: $0.endAt, updatedAt: $0.updatedAt) }
                }
            )
        }
    }

    @Test("Repeated sync updates one task and reuses its planned block identity")
    func idempotentRefresh() throws {
        let store = try container()
        #expect(try apply([event()], to: store) == 1)
        let initial = try #require(tasks(store).first)
        let taskID = initial.id
        let blockID = try #require(initial.scheduleBlocks?.first?.id)

        #expect(try apply([event(title: "Updated meeting")], to: store) == 1)
        let records = try tasks(store)
        #expect(records.count == 1)
        let task = try #require(records.first)
        #expect(task.id == taskID)
        #expect(task.title == "Updated meeting")
        #expect(task.externalAccountID == accountID)
        #expect(task.externalCalendarID == calendarID)
        #expect(task.externalEventID == "meeting")
        #expect(task.externalUpdatedAt == GoogleCalendarEvent.parseTimestamp("2026-04-12T10:00:00.123Z"))
        #expect(task.scheduleBlocks?.count == 1)
        #expect(task.scheduleBlocks?.first?.id == blockID)
        #expect(task.scheduleBlocks?.first?.startAt == TestCalendar.instant(TestCalendar.utc, 2026, 4, 13, 9))
        #expect(task.scheduleBlocks?.first?.endAt == TestCalendar.instant(TestCalendar.utc, 2026, 4, 13, 10))
    }

    @Test("An unchanged snapshot keeps task and block update timestamps identical")
    func unchangedSnapshotDoesNotRewriteRecords() throws {
        let store = try container()
        let untimed = GoogleCalendarEvent(
            id: "day-event", start: .init(date: "2026-04-13"), end: .init(date: "2026-04-15")
        )
        let events = [event(), untimed]
        try apply(events, to: store)
        let initial = try tasks(store)
        let taskTimes = Dictionary(uniqueKeysWithValues: initial.map { ($0.id, $0.updatedAt) })
        let blockTimes = Dictionary(uniqueKeysWithValues: initial.flatMap { $0.scheduleBlocks ?? [] }.map { ($0.id, $0.updatedAt) })
        try apply(events, to: store)
        let refreshed = try tasks(store)
        #expect(refreshed.count == 2)
        #expect(refreshed.allSatisfy { taskTimes[$0.id] == $0.updatedAt })
        #expect(refreshed.flatMap { $0.scheduleBlocks ?? [] }.allSatisfy { blockTimes[$0.id] == $0.updatedAt })
    }

    @Test("Remote edits preserve canonical completion and the user's local archive")
    func localStateSurvivesRemoteEdit() throws {
        let store = try container()
        try apply([event()], to: store)
        let edits = ModelContext(store)
        let local = try #require(edits.fetch(FetchDescriptor<TaskRecord>()).first)
        let completed = TestCalendar.instant(TestCalendar.utc, 2026, 4, 13, 11)
        let archived = TestCalendar.instant(TestCalendar.utc, 2026, 4, 13, 12)
        local.completedAt = completed
        local.archivedAt = archived
        try edits.save()

        try apply([event(title: "Moved meeting", start: "2026-04-14T15:00:00Z", end: "2026-04-14T16:30:00Z")], to: store)
        let task = try #require(tasks(store).first)
        #expect(task.completedAt == completed)
        #expect(task.archivedAt == archived)
        #expect(task.title == "Moved meeting")
        #expect(task.dueDate == TestCalendar.instant(TestCalendar.utc, 2026, 4, 14))
        #expect(task.scheduleBlocks?.first?.plannedDay == task.dueDate)
    }

    @Test("Cancellation and restoration retain task identity, completion and planned history")
    func cancellationAndRestoration() throws {
        let store = try container()
        try apply([event()], to: store)
        let edits = ModelContext(store)
        let local = try #require(edits.fetch(FetchDescriptor<TaskRecord>()).first)
        let completed = TestCalendar.instant(TestCalendar.utc, 2026, 4, 13, 11)
        local.completedAt = completed
        let taskID = local.id
        let blockID = try #require(local.scheduleBlocks?.first?.id)
        try edits.save()

        #expect(try apply([GoogleCalendarEvent(id: "meeting", status: "cancelled")], to: store) == 0)
        let cancelled = try #require(tasks(store).first)
        #expect(cancelled.externalCancelledAt != nil)
        #expect(cancelled.archivedAt == nil)
        #expect(cancelled.completedAt == completed)
        #expect(cancelled.scheduleBlocks?.first?.id == blockID)

        try apply([event()], to: store)
        let restored = try #require(tasks(store).first)
        #expect(restored.id == taskID)
        #expect(restored.externalCancelledAt == nil)
        #expect(restored.completedAt == completed)
        #expect(restored.scheduleBlocks?.first?.id == blockID)
        try apply([GoogleCalendarEvent(id: "unknown", status: "cancelled")], to: store)
        #expect(try tasks(store).count == 1)
    }

    @Test("A complete empty snapshot cancels only this account's plans overlapping its window")
    func boundedMissingEvents() throws {
        let store = try container()
        let wide = DateInterval(
            start: TestCalendar.instant(TestCalendar.utc, 2026, 3, 1),
            end: TestCalendar.instant(TestCalendar.utc, 2026, 5, 1)
        )
        try apply([
            event(id: "current"),
            event(id: "history", start: "2026-03-02T09:00:00Z", end: "2026-03-02T10:00:00Z")
        ], to: store, window: wide)
        try apply([event(id: "other-account")], to: store, account: "another-account")
        try apply([], to: store)

        let records = try tasks(store)
        #expect(records.count == 3)
        #expect(records.first { $0.externalEventID == "current" }?.externalCancelledAt != nil)
        #expect(records.first { $0.externalEventID == "history" }?.externalCancelledAt == nil)
        #expect(records.first { $0.externalEventID == "other-account" }?.externalCancelledAt == nil)
        #expect(records.allSatisfy { $0.scheduleBlocks?.count == 1 })
    }

    @Test("Malformed active events leave the imported store and pending UI edits untouched")
    func malformedSnapshotIsAtomic() throws {
        let store = try container()
        try apply([event()], to: store)
        let ui = store.mainContext
        let pending = TaskRecord(title: "Pending UI task", notes: "Do not roll this back")
        ui.insert(pending)
        let malformed = GoogleCalendarEvent(
            id: "bad", summary: "Bad event",
            start: .init(dateTime: "not-a-date"), end: .init(dateTime: "2026-04-13T10:00:00Z")
        )
        #expect(throws: GoogleCalendarImportError.self) {
            try apply([event(id: "new"), malformed], to: store)
        }
        #expect(ui.hasChanges)
        #expect(pending.notes == "Do not roll this back")
        let persisted = try tasks(store)
        #expect(persisted.count == 1)
        #expect(persisted.first?.externalEventID == "meeting")
        #expect(persisted.first?.externalCancelledAt == nil)
        #expect(persisted.first?.title == "Meeting with Thomas")
    }

    @Test("All-day multi-day events create one untimed plan per day with an exclusive end")
    func allDayMultiDay() throws {
        let store = try container()
        let holiday = GoogleCalendarEvent(
            id: "holiday", summary: "Time away",
            start: .init(date: "2026-04-13"), end: .init(date: "2026-04-16")
        )
        try apply([holiday], to: store)
        let task = try #require(tasks(store).first)
        let blocks = (task.scheduleBlocks ?? []).sorted { $0.plannedDay < $1.plannedDay }
        #expect(blocks.map(\.plannedDay) == [13, 14, 15].map { TestCalendar.instant(TestCalendar.utc, 2026, 4, $0) })
        #expect(blocks.allSatisfy { $0.startAt == nil && $0.endAt == nil })
        #expect(task.dueDate == TestCalendar.instant(TestCalendar.utc, 2026, 4, 13))
    }

    @Test("Google all-day ISO dates retain Gregorian years under a Buddhist device calendar")
    func allDayDateUnderBuddhistCalendar() throws {
        var calendar = Calendar(identifier: .buddhist)
        calendar.timeZone = TestCalendar.utc.timeZone
        let store = try container()
        let event = GoogleCalendarEvent(
            id: "iso-day", start: .init(date: "2026-04-13"), end: .init(date: "2026-04-14")
        )
        try apply([event], to: store, calendar: calendar, window: window())
        let task = try #require(tasks(store).first)
        #expect(task.dueDate == TestCalendar.instant(TestCalendar.utc, 2026, 4, 13))
        #expect(task.scheduleBlocks?.first?.plannedDay == task.dueDate)
        #expect(task.scheduleBlocks?.count == 1)
    }

    @Test("A moving all-day sync window preserves already imported days and block identities")
    func movingAllDayWindowPreservesHistory() throws {
        let store = try container()
        let event = GoogleCalendarEvent(
            id: "trip", start: .init(date: "2026-04-13"), end: .init(date: "2026-04-20")
        )
        let firstWindow = DateInterval(
            start: TestCalendar.instant(TestCalendar.utc, 2026, 4, 13),
            end: TestCalendar.instant(TestCalendar.utc, 2026, 4, 15)
        )
        try apply([event], to: store, window: firstWindow)
        let initial = try #require(tasks(store).first)
        let initialIDs = Dictionary(uniqueKeysWithValues: (initial.scheduleBlocks ?? []).map { ($0.plannedDay, $0.id) })
        #expect(initialIDs.count == 2)

        let secondWindow = DateInterval(
            start: TestCalendar.instant(TestCalendar.utc, 2026, 4, 15),
            end: TestCalendar.instant(TestCalendar.utc, 2026, 4, 17)
        )
        try apply([event], to: store, window: secondWindow)
        let refreshed = try #require(tasks(store).first)
        let refreshedIDs = Dictionary(uniqueKeysWithValues: (refreshed.scheduleBlocks ?? []).map { ($0.plannedDay, $0.id) })
        #expect(refreshedIDs.count == 4)
        #expect(initialIDs.allSatisfy { refreshedIDs[$0.key] == $0.value })
        #expect(refreshedIDs[TestCalendar.instant(TestCalendar.utc, 2026, 4, 19)] == nil)

        // A genuine remote change removes days excluded by its new
        // range, including previously imported history outside this
        // snapshot, while retaining matching day identities.
        let shortened = GoogleCalendarEvent(
            id: "trip", start: .init(date: "2026-04-14"), end: .init(date: "2026-04-16")
        )
        try apply([shortened], to: store, window: secondWindow)
        let changed = try #require(tasks(store).first)
        let changedIDs = Dictionary(uniqueKeysWithValues: (changed.scheduleBlocks ?? []).map { ($0.plannedDay, $0.id) })
        #expect(changedIDs.count == 2)
        #expect(changedIDs[TestCalendar.instant(TestCalendar.utc, 2026, 4, 13)] == nil)
        #expect(changedIDs[TestCalendar.instant(TestCalendar.utc, 2026, 4, 14)] == initialIDs[TestCalendar.instant(TestCalendar.utc, 2026, 4, 14)])
        #expect(changedIDs[TestCalendar.instant(TestCalendar.utc, 2026, 4, 15)] == refreshedIDs[TestCalendar.instant(TestCalendar.utc, 2026, 4, 15)])
    }

    @Test("All-day plans stay at each civil day's start across midnight DST changes")
    func midnightDST() throws {
        let calendar = TestCalendar.havana
        let store = try container()
        let bounds = DateInterval(
            start: calendar.startOfDay(for: TestCalendar.instant(calendar, 2026, 3, 7, 12)),
            end: calendar.startOfDay(for: TestCalendar.instant(calendar, 2026, 3, 11, 12))
        )
        let event = GoogleCalendarEvent(
            id: "dst-trip", start: .init(date: "2026-03-07"), end: .init(date: "2026-03-10")
        )
        try apply([event], to: store, calendar: calendar, window: bounds)
        let task = try #require(tasks(store).first)
        let blocks = (task.scheduleBlocks ?? []).sorted { $0.plannedDay < $1.plannedDay }
        let expected = [7, 8, 9].map { calendar.startOfDay(for: TestCalendar.instant(calendar, 2026, 3, $0, 12)) }
        #expect(blocks.map(\.plannedDay) == expected)
        #expect(calendar.component(.hour, from: expected[1]) == 1)
        #expect(calendar.component(.hour, from: expected[2]) == 0)
    }

    @Test("A missing previous all-day event stays historical across midnight DST")
    func midnightDSTHistoryDoesNotOverlapNextDay() throws {
        let calendar = TestCalendar.havana
        let store = try container()
        let start = calendar.startOfDay(for: TestCalendar.instant(calendar, 2026, 3, 8, 12))
        let next = calendar.startOfDay(for: TestCalendar.instant(calendar, 2026, 3, 9, 12))
        let end = calendar.startOfDay(for: TestCalendar.instant(calendar, 2026, 3, 10, 12))
        let event = GoogleCalendarEvent(
            id: "dst-day", start: .init(date: "2026-03-08"), end: .init(date: "2026-03-09")
        )
        try apply([event], to: store, calendar: calendar, window: DateInterval(start: start, end: next))
        try apply([], to: store, calendar: calendar, window: DateInterval(start: next, end: end))
        let task = try #require(tasks(store).first)
        #expect(task.externalCancelledAt == nil)
        #expect(task.scheduleBlocks?.count == 1)
        #expect(task.scheduleBlocks?.first?.plannedDay == start)
    }

    @Test("Timed DST events retain offset-resolved instants and the local planning day")
    func timedDST() throws {
        let calendar = TestCalendar.paris
        let store = try container()
        let bounds = DateInterval(
            start: TestCalendar.instant(calendar, 2026, 3, 28),
            end: TestCalendar.instant(calendar, 2026, 3, 31)
        )
        let event = event(start: "2026-03-29T01:30:00+01:00", end: "2026-03-29T03:30:00+02:00")
        try apply([event], to: store, calendar: calendar, window: bounds)
        let task = try #require(tasks(store).first)
        let block = try #require(task.scheduleBlocks?.first)
        let start = try #require(block.startAt)
        let end = try #require(block.endAt)
        #expect(end.timeIntervalSince(start) == 3_600)
        #expect(block.plannedDay == TestCalendar.instant(calendar, 2026, 3, 29))
        #expect(calendar.component(.hour, from: start) == 1)
        #expect(calendar.component(.hour, from: end) == 3)
    }
}
