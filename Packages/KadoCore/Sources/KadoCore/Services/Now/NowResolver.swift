import Foundation

/// Decides what the Now tab shows. Pure: callers pass today's blocks
/// already filtered to workable items (`NowInputBuilder` in the app).
nonisolated public struct NowResolver: Sendable {
    public let boundary: DayBoundary

    public init(boundary: DayBoundary) {
        self.boundary = boundary
    }

    public func resolve(now: Date, blocks: [NowBlock], openSession: OpenSession?) -> NowScreen {
        let today = blocks
            .filter { boundary.isDate($0.start, inSameDayAs: now) }
            .sorted { ($0.start, $0.createdAt) < ($1.start, $1.createdAt) }

        if let openSession {
            let range = openSession.blockID.flatMap { id in blocks.first { $0.id == id }?.range }
            let anchor = range?.lowerBound ?? now
            let next = today.first { $0.start > anchor && $0.id != openSession.blockID }
            let state: NowState = openSession.session.isPaused
                ? .paused(openSession, plannedRange: range)
                : .running(openSession, plannedRange: range)
            return NowScreen(state: state, upNext: next)
        }

        if let current = today.first(where: { $0.range.contains(now) }) {
            return NowScreen(state: .suggestedCurrent(current), upNext: today.first { $0.start > current.start })
        }
        if let next = today.first(where: { $0.start > now }) {
            return NowScreen(state: .suggestedNext(next), upNext: nil)
        }
        return NowScreen(state: .empty, upNext: nil)
    }
}
