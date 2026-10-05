import Foundation
import SwiftData
import KadoCore

/// Rebuilds the local UN pending-request set from SwiftData. Paired
/// with `WidgetReloader` — any mutation that reloads widgets should
/// also resync reminders so a just-completed day stops firing.
///
/// Safe to call even when `ActiveScheduler.shared` hasn't been
/// primed yet (early init); it's a no-op in that case.
///
/// Passes run one at a time and the latest request wins: a reschedule
/// clears every pending request before adding its own, so two running
/// at once could interleave, and an older one finishing last would
/// leave a stale streak line or a day that is already done.
@MainActor
enum RemindersSync {
    /// Folds the launch and foreground calls, which arrive together,
    /// into one pass.
    static let coalescingDelay: Duration = .milliseconds(300)

    private static let passes = CoalescingTask()

    /// Reads the store when the pass runs, not now.
    static func rescheduleAll(using context: ModelContext) {
        guard let scheduler = ActiveScheduler.shared.get() else { return }
        // Held weakly, as in `WidgetReloader`: a store gone before the
        // pass runs is skipped. Read off the main actor through a
        // context of its own, never the caller's.
        let container = context.container
        passes.schedule(after: coalescingDelay) { [weak container] in
            guard let container else { return }
            let read = await Task.detached(priority: .utility) {
                inputs(from: ModelContext(container))
            }.value
            await run(scheduler, habits: read.habits, completions: read.completions)
        }
    }

    /// Reschedules from a store read the caller already made.
    static func reschedule(habits: [Habit], completions: [Completion]) {
        guard let scheduler = ActiveScheduler.shared.get() else { return }
        passes.schedule(after: .zero) {
            await run(scheduler, habits: habits, completions: completions)
        }
    }

    /// Drops a pass that hasn't started, for a caller about to schedule
    /// a fresher one.
    static func cancelPending() {
        passes.cancel()
    }

    static func flush() async {
        await passes.flush()
    }

    /// What the scheduler acts on and nothing more: active habits with
    /// reminders on, and their own completions. The scheduler skips
    /// every other habit and matches completions by habit, so the
    /// pending set is the same as from the whole store. Reads on the
    /// caller's thread, so `context` must belong to it.
    nonisolated static func inputs(from context: ModelContext) -> (habits: [Habit], completions: [Completion]) {
        let records = ((try? context.fetch(FetchDescriptor<HabitRecord>())) ?? [])
            .filter { $0.remindersEnabled && $0.archivedAt == nil }
        return (
            records.map(\.snapshot),
            records.flatMap { ($0.completions ?? []).compactMap(\.snapshot) }
        )
    }

    private static func run(
        _ scheduler: any NotificationScheduling,
        habits: [Habit],
        completions: [Completion]
    ) async {
        await Task.detached(priority: .utility) {
            await scheduler.rescheduleAll(habits: habits, completions: completions)
        }.value
    }
}
