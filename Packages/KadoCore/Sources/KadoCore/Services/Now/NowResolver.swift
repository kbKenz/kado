import Foundation

/// Decides what the Now tab shows. Pure: callers pass workable blocks
/// (`NowInputBuilder` in the app).
nonisolated public struct NowResolver: Sendable {
    public let boundary: DayBoundary

    public init(boundary: DayBoundary) {
        self.boundary = boundary
    }

    /// Precedence: open session > current block > next block > empty.
    ///
    /// - `blocks` may span several days; only the logical day of `now`
    ///   is used. A block crossing the rollover belongs to the day it starts on.
    /// - An open session wins even without a block: a planned block
    ///   covering now is then hidden, because the session is what you
    ///   are working on. Its block is looked up in today's blocks only.
    /// - `upNext` is the first block starting after the shown block's
    ///   start (after `now` when it is later or nothing is shown), and is
    ///   nil when the main card is `suggestedNext`.
    public func resolve(now: Date, blocks: [NowBlock], openSession: OpenSession?) -> NowScreen {
        let today = blocks
            .filter { boundary.isDate($0.start, inSameDayAs: now) }
            .sorted {
                ($0.start, $0.createdAt, $0.id.uuidString) < ($1.start, $1.createdAt, $1.id.uuidString)
            }

        if let openSession {
            let block = openSession.blockID.flatMap { id in today.first { $0.id == id } }
            let range = block?.range
            let threshold = max(block?.start ?? now, now)
            let next = today.first { $0.start > threshold }
            let state: NowState = openSession.session.isPaused
                ? .paused(openSession, plannedRange: range)
                : .running(openSession, plannedRange: range)
            return NowScreen(state: state, upNext: next)
        }

        if let current = today.first(where: { $0.isCurrent(at: now) }) {
            return NowScreen(state: .suggestedCurrent(current), upNext: today.first { $0.start > current.start })
        }
        if let next = today.first(where: { $0.start > now }) {
            return NowScreen(state: .suggestedNext(next), upNext: nil)
        }
        return NowScreen(state: .empty, upNext: nil)
    }
}
