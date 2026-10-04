import Foundation
import SwiftData
import KadoCore

/// Every write to tracked time. Views call these with records they
/// resolved by UUID from their own `@Query`, then forget them.
@MainActor
struct WorkSessionTracker {
    enum TrackerError: Error, Equatable {
        case sessionAlreadyOpen
        case noOpenSession
    }

    let boundary: DayBoundary
    let now: () -> Date

    init(boundary: DayBoundary, now: @escaping () -> Date = { .now }) {
        self.boundary = boundary
        self.now = now
    }

    /// The open session, earliest first if sync brought in two.
    static func openSession(in context: ModelContext) throws -> WorkSessionRecord? {
        var descriptor = FetchDescriptor<WorkSessionRecord>(
            predicate: #Predicate { $0.endedAt == nil },
            sortBy: [SortDescriptor(\.startedAt)]
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    func start(task: TaskRecord, block: ScheduleBlockRecord?, in context: ModelContext) throws {
        let now = now()
        try requireNoOpenSession(in: context)
        context.insert(WorkSessionRecord(startedAt: now, task: task, scheduleBlock: block))
        try commit(context)
    }

    func start(habit: HabitRecord, block: ScheduleBlockRecord?, in context: ModelContext) throws {
        let now = now()
        try requireNoOpenSession(in: context)
        context.insert(WorkSessionRecord(startedAt: now, habit: habit, scheduleBlock: block))
        try commit(context)
    }

    func pause(in context: ModelContext) throws {
        let now = now()
        let session = try requireOpen(in: context)
        guard session.pausedAt == nil else { return }
        session.pausedAt = now
        session.updatedAt = now
        try commit(context)
    }

    func resume(in context: ModelContext) throws {
        let now = now()
        let session = try requireOpen(in: context)
        closePause(session, at: now)
        try commit(context)
    }

    /// Ends the open session. A task is done when it is finished; a habit
    /// is logged on the day the session started.
    func finish(markDone: Bool, in context: ModelContext) throws {
        let now = now()
        let session = try requireOpen(in: context)
        closePause(session, at: now)
        session.endedAt = now
        session.updatedAt = now
        if markDone {
            if let task = session.task {
                if task.completedAt == nil {
                    task.completedAt = now
                    task.updatedAt = now
                }
            } else if let habit = session.habit {
                log(habit, workedSeconds: session.snapshot.elapsed(at: now), startedAt: session.startedAt, now: now, in: context)
            }
        }
        try commit(context)
    }

    func cancel(in context: ModelContext) throws {
        context.delete(try requireOpen(in: context))
        try commit(context)
    }

    // MARK: - Private

    /// Checked before the record is built: assigning a persisted `task`
    /// or `habit` to a new record inserts it into the context, where the
    /// fetch would then find the record this call is about to create.
    private func requireNoOpenSession(in context: ModelContext) throws {
        guard try Self.openSession(in: context) == nil else { throw TrackerError.sessionAlreadyOpen }
    }

    private func requireOpen(in context: ModelContext) throws -> WorkSessionRecord {
        guard let session = try Self.openSession(in: context) else { throw TrackerError.noOpenSession }
        return session
    }

    private func closePause(_ session: WorkSessionRecord, at now: Date) {
        guard let pausedAt = session.pausedAt else { return }
        session.pausedSeconds += max(0, now.timeIntervalSince(pausedAt))
        session.pausedAt = nil
        session.updatedAt = now
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

    private func log(_ habit: HabitRecord, workedSeconds: TimeInterval, startedAt: Date, now: Date, in context: ModelContext) {
        let logicalDay = boundary.startOfDay(for: startedAt)
        let instant = boundary.loggingInstant(for: now, on: logicalDay)
        // Completions are stamped with an instant whose civil day is the
        // logical day, so match by civil day, not by `boundary.isDate`.
        let existing = habit.completions?.first {
            boundary.calendar.isDate($0.date, inSameDayAs: logicalDay)
        }
        switch habit.type {
        case .timer:
            guard workedSeconds > 0 else { return }
            if let existing { existing.value += workedSeconds } else {
                context.insert(CompletionRecord(date: instant, value: workedSeconds, habit: habit))
            }
        case .counter:
            if let existing { existing.value += 1 } else {
                context.insert(CompletionRecord(date: instant, value: 1, habit: habit))
            }
        case .binary:
            if let existing { existing.value = max(existing.value, 1) } else {
                context.insert(CompletionRecord(date: instant, value: 1, habit: habit))
            }
        case .negative:
            // Now never offers negative habits; nothing to log.
            return
        }
    }
}
