import Foundation
import KadoCore

/// A goal as title suggestions see it. A value snapshot, never the
/// record, so a form keeps no `@Model` object in its state (issue #63).
nonisolated struct SuggestionGoal: Identifiable, Hashable, Sendable {
    let id: UUID
    let name: String
    let details: String
    /// The goal's own category. A task follows it.
    let category: ItemCategory?
    /// Active and not archived. Only these goals can be suggested.
    let isActive: Bool
    let updatedAt: Date

    init(
        id: UUID = UUID(), name: String, details: String = "", category: ItemCategory? = nil,
        isActive: Bool = true, updatedAt: Date = .distantPast
    ) {
        self.id = id
        self.name = name
        self.details = details
        self.category = category
        self.isActive = isActive
        self.updatedAt = updatedAt
    }

    /// What `GoalMatcher` reads.
    var candidate: GoalCandidate {
        GoalCandidate(id: id, name: name, details: details)
    }
}

extension SuggestionGoal {
    /// A snapshot of a live record.
    @MainActor
    init(_ record: GoalRecord) {
        self.init(
            id: record.id,
            name: record.name,
            details: record.details,
            category: record.category,
            isActive: record.status == .active && record.archivedAt == nil,
            updatedAt: record.updatedAt
        )
    }
}
