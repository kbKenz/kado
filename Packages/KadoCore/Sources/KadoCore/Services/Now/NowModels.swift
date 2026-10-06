import Foundation

/// What a block or session is about, as a value. Views address records
/// by these UUIDs and never hold a `@Model` (issue #63).
nonisolated public enum NowItem: Hashable, Identifiable, Sendable {
    case task(id: UUID, title: String)
    case habit(id: UUID, name: String)

    public var id: UUID {
        switch self {
        case .task(let id, _): return id
        case .habit(let id, _): return id
        }
    }

    public var title: String {
        switch self {
        case .task(_, let title): return title
        case .habit(_, let name): return name
        }
    }
}

/// A planned block already filtered to things that can be worked on.
/// `start` is required: untimed blocks are filtered out before this type.
nonisolated public struct NowBlock: Hashable, Sendable {
    public var id: UUID
    public var item: NowItem
    public var start: Date
    public var end: Date?
    public var createdAt: Date

    public init(id: UUID, item: NowItem, start: Date, end: Date?, createdAt: Date) {
        self.id = id
        self.item = item
        self.start = start
        self.end = end
        self.createdAt = createdAt
    }

    /// A block with a start and no end lasts one hour, the same default
    /// the app's schedule rows use. Not capped at the day's end.
    public static let defaultDuration: TimeInterval = 3600

    /// Planned range, for display.
    public var range: ClosedRange<Date> {
        start...max(start, end ?? start.addingTimeInterval(Self.defaultDuration))
    }

    /// Half-open: a block is current from its start up to, not including,
    /// its end, so back-to-back blocks never both match.
    public func isCurrent(at now: Date) -> Bool {
        start <= now && now < range.upperBound
    }
}

/// One item's tracked time on a logical day: what the running card
/// adds its clock to, and what a row of the paused list shows.
///
/// Every start-to-pause stretch is its own `WorkSessionRecord`, so
/// `runs` is the automatic log of when work started and stopped.
nonisolated public struct NowProgress: Hashable, Identifiable, Sendable {
    public var item: NowItem
    /// Finished runs that started on the day, oldest first.
    public var runs: [DateInterval]
    /// Time already counted for the day, without a running session: a
    /// timer habit's logged value (manual logs included), else the
    /// worked time of `runs`.
    public var countedSeconds: TimeInterval
    /// A timer habit's daily target; nil for tasks and other habits.
    public var targetSeconds: TimeInterval?
    /// False for timer habits: they are done when the time is reached.
    public var canMarkDone: Bool

    public var id: UUID { item.id }

    public init(item: NowItem, runs: [DateInterval], countedSeconds: TimeInterval,
                targetSeconds: TimeInterval? = nil, canMarkDone: Bool = true) {
        self.item = item
        self.runs = runs
        self.countedSeconds = countedSeconds
        self.targetSeconds = targetSeconds
        self.canMarkDone = canMarkDone
    }

    /// When the last run stopped, for ordering and display.
    public var lastStoppedAt: Date? { runs.last?.end }
}

/// The running session, if any, with what it is about.
nonisolated public struct OpenSession: Hashable, Sendable {
    public var id: UUID
    public var item: NowItem
    public var session: WorkSession
    public var blockID: UUID?

    public init(id: UUID, item: NowItem, session: WorkSession, blockID: UUID?) {
        self.id = id
        self.item = item
        self.session = session
        self.blockID = blockID
    }
}

nonisolated public enum NowState: Equatable, Sendable {
    /// A session is running. `plannedRange` is its block's range, nil without a block today.
    case running(OpenSession, plannedRange: ClosedRange<Date>?)
    /// No session; this block's range holds now.
    case suggestedCurrent(NowBlock)
    /// No session and nothing current; this is the next block later today.
    case suggestedNext(NowBlock)
    /// Nothing running, current or left today.
    case empty
}

/// Everything the Now tab shows.
nonisolated public struct NowScreen: Equatable, Sendable {
    public var state: NowState
    public var upNext: NowBlock?

    public init(state: NowState, upNext: NowBlock?) {
        self.state = state
        self.upNext = upNext
    }
}
