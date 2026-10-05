import Foundation
import os

/// Keeps widget snapshot writes in the order their stores were read.
///
/// A rebuild takes a ticket when it reads the store (on the main actor,
/// so tickets follow the order of the reads) and presents it with the
/// series it built. A background build can finish after a newer one —
/// a long history, a synchronous intent write in between — and without
/// this the file would end on the older state until the next mutation.
public final class WidgetSnapshotWriteOrder: Sendable {
    public static let shared = WidgetSnapshotWriteOrder { WidgetSnapshotStore.write($0) }

    private struct State {
        var issued = 0
        var written = 0
    }

    private let state = OSAllocatedUnfairLock(initialState: State())
    private let sink: @Sendable (Data) -> Void

    /// `sink` receives the encoded series; tests pass their own instead
    /// of the App Group file.
    public init(sink: @escaping @Sendable (Data) -> Void) {
        self.sink = sink
    }

    /// The next ticket. Take it in the same turn as the store read it
    /// stands for.
    public func ticket() -> Int {
        state.withLock { state in
            state.issued += 1
            return state.issued
        }
    }

    /// Writes `series` unless a write from a later read has already
    /// landed. Returns whether it wrote.
    @discardableResult
    public func write(_ series: WidgetSnapshotSeries, ticket: Int) -> Bool {
        guard state.withLock({ ticket > $0.written }),
              let data = try? WidgetSnapshotStore.encode(series) else { return false }
        let sink = sink
        // The check is repeated under the lock that also covers the
        // write, so two writers can't both pass it and land out of order.
        return state.withLock { state in
            guard ticket > state.written else { return false }
            sink(data)
            state.written = ticket
            return true
        }
    }
}
