import Foundation
import SwiftData
import KadoCore

/// The app's "after a habit mutation" postamble: rebuild the App Group
/// snapshot the widget reads (which reloads the timelines itself, so
/// the change surfaces within a second or two) and reconcile the
/// pending reminders.
///
/// The widget extension can't safely open SwiftData (two
/// processes can't both attach CloudKit to the same store), so
/// the snapshot-through-file-system dance is the bridge between
/// app writes and widget reads.
///
/// Deferred and coalesced: the caller returns at once, and calls closer
/// together than `coalescingDelay` share one pass, which reads the
/// store as it stands when the pass runs. Only that read and today's
/// tally run on the main actor; the series build and the file write
/// run detached.
@MainActor
enum WidgetReloader {
    /// Long enough to fold a burst of +1 taps into one pass, short
    /// enough that the confetti still answers the tap that earned it.
    static let coalescingDelay: Duration = .milliseconds(300)

    private static let passes = CoalescingTask()

    static func reloadAll(using context: ModelContext) {
        // The pass below reschedules reminders from its own, later
        // read, so a reminders-only pass still waiting would only
        // repeat it.
        RemindersSync.cancelPending()
        // Held weakly: a store swapped out (dev mode) or torn down
        // before the pass runs has nothing left to report, and keeping
        // its context alive past its container traps in SwiftData.
        let container = context.container
        passes.schedule(after: coalescingDelay) { [weak context, weak container] in
            guard let context, container != nil else { return }
            await WidgetSnapshotBuilder.rebuildAndWriteInBackground(using: context) { source in
                // Reminders share the same "after a habit mutation"
                // cadence as widgets, and the store read the widget
                // just made covers every habit the scheduler acts on.
                RemindersSync.reschedule(habits: source.habits, completions: source.allCompletions)
            }
        }
    }

    /// Waits for the pending pass, and the reminders it started.
    static func flush() async {
        await passes.flush()
        await RemindersSync.flush()
    }
}
