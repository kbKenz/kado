import Foundation
import SwiftData
import KadoCore

/// Every write to tracked time. Views call these with records they
/// resolved by UUID from their own `@Query`, then forget them.
///
/// A session is one run: it starts when work starts and ends when it
/// pauses. Pausing and continuing during the day leaves one record per
/// run, which is the automatic log of when work started and stopped.
/// Only one session runs at a time; starting another item pauses the
/// running one.
@MainActor
struct WorkSessionTracker {
    enum TrackerError: Error, Equatable {
        case noOpenSession
    }

    let boundary: DayBoundary
    let now: () -> Date

    init(boundary: DayBoundary, now: @escaping () -> Date = { .now }) {
        self.boundary = boundary
        self.now = now
    }

    /// The open session, earliest first if sync brought in two. A
    /// session paused by an earlier version is still open, with `pausedAt` set.
    static func openSession(in context: ModelContext) throws -> WorkSessionRecord? {
        var descriptor = FetchDescriptor<WorkSessionRecord>(
            predicate: #Predicate { $0.endedAt == nil },
            sortBy: [SortDescriptor(\.startedAt)]
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    /// Starts or continues `task`. A different running session is paused
    /// first, in the same save. Does nothing when `task` already runs.
    func start(task: TaskRecord, block: ScheduleBlockRecord?, in context: ModelContext) throws {
        let now = now()
        if try isRunning(in: context, where: { $0.task?.id == task.id }) { return }
        try endOpenSessions(at: now, in: context)
        context.insert(WorkSessionRecord(startedAt: now, task: task, scheduleBlock: block))
        try commit(context)
    }

    /// Starts or continues `habit`, as `start(task:)` does.
    func start(habit: HabitRecord, block: ScheduleBlockRecord?, in context: ModelContext) throws {
        let now = now()
        if try isRunning(in: context, where: { $0.task == nil && $0.habit?.id == habit.id }) { return }
        try endOpenSessions(at: now, in: context)
        context.insert(WorkSessionRecord(startedAt: now, habit: habit, scheduleBlock: block))
        try commit(context)
    }

    /// Stops the clock. The run is logged; the item stays open for later.
    func pause(in context: ModelContext) throws {
        guard try Self.openSession(in: context) != nil else { throw TrackerError.noOpenSession }
        try endOpenSessions(at: now(), in: context)
        try commit(context)
    }

    /// Marks `task` done, and ends its run when it is the running one.
    func complete(task: TaskRecord, in context: ModelContext) throws {
        let now = now()
        try endOpenSessions(at: now, in: context, only: { $0.task?.id == task.id })
        if task.completedAt == nil {
            task.completedAt = now
            task.updatedAt = now
        }
        try commit(context)
    }

    /// Marks `habit` done for the day its run started (today when it is
    /// not running). A timer habit only ends its run: its time is what counts.
    func complete(habit: HabitRecord, in context: ModelContext) throws {
        let now = now()
        let run = try Self.openSession(in: context).flatMap { $0.task == nil && $0.habit?.id == habit.id ? $0 : nil }
        let startedAt = run?.startedAt ?? now
        try endOpenSessions(at: now, in: context, only: { $0.task == nil && $0.habit?.id == habit.id })
        logDone(habit, startedAt: startedAt, now: now, in: context)
        try commit(context)
    }

    /// Deletes the open session, for a run started by mistake.
    func cancel(in context: ModelContext) throws {
        guard let session = try Self.openSession(in: context) else { throw TrackerError.noOpenSession }
        context.delete(session)
        try commit(context)
    }

    // MARK: - Private

    private func isRunning(in context: ModelContext, where matches: (WorkSessionRecord) -> Bool) throws -> Bool {
        guard let open = try Self.openSession(in: context) else { return false }
        return open.pausedAt == nil && matches(open)
    }

    /// Ends every open session (sync can bring in two), or only those
    /// `only` accepts. Runs before a new record is built: assigning a
    /// persisted `task` or `habit` to a new record inserts it into the
    /// context, where this fetch would then find it.
    private func endOpenSessions(
        at now: Date,
        in context: ModelContext,
        only include: (WorkSessionRecord) -> Bool = { _ in true }
    ) throws {
        let open = try context.fetch(FetchDescriptor<WorkSessionRecord>(predicate: #Predicate { $0.endedAt == nil }))
        for session in open where include(session) {
            end(session, at: now, in: context)
        }
    }

    /// A session paused by an earlier version ends where it was paused,
    /// so its run shows the time work really stopped.
    private func end(_ session: WorkSessionRecord, at now: Date, in context: ModelContext) {
        let end = min(session.pausedAt ?? now, now)
        session.pausedAt = nil
        session.endedAt = max(end, session.startedAt)
        session.updatedAt = now
        if session.task == nil, let habit = session.habit, case .timer = habit.type {
            addTime(session.snapshot.elapsed(at: now), to: habit, startedAt: session.startedAt, now: now, in: context)
        }
    }

    /// Saves, and undoes the pending changes when the save fails so the
    /// shared context is never left dirty.
    private func commit(_ context: ModelContext) throws {
        do {
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
    }

    /// The completion on the logical day of `startedAt`, if any.
    /// Completions are stamped with an instant whose civil day is the
    /// logical day, so match by civil day, not by `boundary.isDate`.
    private func completion(of habit: HabitRecord, startedAt: Date) -> (day: Date, record: CompletionRecord?) {
        let logicalDay = boundary.startOfDay(for: startedAt)
        let existing = habit.completions?.first {
            boundary.calendar.isDate($0.date, inSameDayAs: logicalDay)
        }
        return (logicalDay, existing)
    }

    private func addTime(_ seconds: TimeInterval, to habit: HabitRecord, startedAt: Date, now: Date, in context: ModelContext) {
        guard seconds > 0 else { return }
        let (day, existing) = completion(of: habit, startedAt: startedAt)
        if let existing {
            existing.value += seconds
        } else {
            context.insert(CompletionRecord(date: boundary.loggingInstant(for: now, on: day), value: seconds, habit: habit))
        }
    }

    private func logDone(_ habit: HabitRecord, startedAt: Date, now: Date, in context: ModelContext) {
        let (day, existing) = completion(of: habit, startedAt: startedAt)
        let instant = boundary.loggingInstant(for: now, on: day)
        switch habit.type {
        case .counter:
            if let existing { existing.value += 1 } else {
                context.insert(CompletionRecord(date: instant, value: 1, habit: habit))
            }
        case .binary:
            if let existing { existing.value = max(existing.value, 1) } else {
                context.insert(CompletionRecord(date: instant, value: 1, habit: habit))
            }
        case .timer, .negative:
            // A timer's runs already logged its time; Now never offers negative habits.
            return
        }
    }
}
