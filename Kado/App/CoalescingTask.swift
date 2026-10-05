import Foundation

/// Runs the last of a burst of requests, one pass at a time.
///
/// Each `schedule` replaces any pass that hasn't started yet, so five
/// quick taps cost one pass, with the last tap's state. A pass already
/// running is left to finish and the next one waits for it: two passes
/// never overlap, and the latest request is always the last to run.
@MainActor
final class CoalescingTask {
    private var latest: Task<Void, Never>?

    func schedule(after delay: Duration, _ work: @escaping @MainActor () async -> Void) {
        let previous = latest
        previous?.cancel()
        latest = Task {
            if delay > .zero {
                // Throws when a newer request cancels this one; the
                // guard below then drops it.
                try? await Task.sleep(for: delay)
            }
            await previous?.value
            guard !Task.isCancelled else { return }
            await work()
        }
    }

    /// Drops the pass that hasn't started yet, if any. One already
    /// running finishes.
    func cancel() {
        latest?.cancel()
    }

    /// Waits until every scheduled pass has run or been dropped.
    func flush() async {
        while let task = latest {
            await task.value
            if task == latest { return }
        }
    }
}
