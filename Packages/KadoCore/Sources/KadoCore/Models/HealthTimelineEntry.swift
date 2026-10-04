import Foundation

/// One Health interval shown on the Calendar timeline. Display-only:
/// never persisted to SwiftData, synced, exported, or used to
/// complete a habit or task.
nonisolated public struct HealthTimelineEntry: Hashable, Sendable, Identifiable {
    public enum Kind: Hashable, Sendable {
        case sleep
        /// `name` is already localized for display.
        case workout(name: String)
    }

    public let id: UUID
    public let kind: Kind
    public let interval: DateInterval

    public init(id: UUID, kind: Kind, interval: DateInterval) {
        self.id = id
        self.kind = kind
        self.interval = interval
    }
}
