import Foundation
import KadoCore

/// What the on-device model proposes for a title, already checked
/// against the closed lists (`ItemSuggestionSchema.validate`): a real
/// category, one of the request's goals, a curated icon, or nothing.
nonisolated struct ModelItemSuggestion: Hashable, Sendable {
    var category: ItemCategory?
    var goalID: UUID?
    /// Habits only.
    var icon: String?

    init(category: ItemCategory? = nil, goalID: UUID? = nil, icon: String? = nil) {
        self.category = category
        self.goalID = goalID
        self.icon = icon
    }
}
