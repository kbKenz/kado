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

    /// A block without an end lasts one hour (`ScheduleDefaults`).
    public var range: ClosedRange<Date> {
        start...max(start, end ?? start.addingTimeInterval(3600))
    }
}

/// The open session, if any, with what it is about.
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
    case running(OpenSession, plannedRange: ClosedRange<Date>?)
    case paused(OpenSession, plannedRange: ClosedRange<Date>?)
    case suggestedCurrent(NowBlock)
    case suggestedNext(NowBlock)
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
