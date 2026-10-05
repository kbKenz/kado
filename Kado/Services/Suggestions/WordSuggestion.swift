import Foundation
import KadoCore

/// The word tier: what the keyword lists and the goal matcher make of a
/// title. Pure and quick, so it runs on every title change, on every
/// device.
nonisolated struct WordSuggestion: Hashable, Sendable {
    /// From `CategoryClassifier`.
    var category: ItemCategory?
    /// From `GoalMatcher`, over active goals only. Tasks and habits.
    var goal: GoalMatch?
    /// A keyword icon from `HabitIconSuggester` (habits only). Never the
    /// category's fallback icon, which `SuggestionDraft` adds itself.
    var icon: String?

    init(category: ItemCategory? = nil, goal: GoalMatch? = nil, icon: String? = nil) {
        self.category = category
        self.goal = goal
        self.icon = icon
    }

    init(title: String, goals: [SuggestionGoal], kind: ItemSuggestionKind) {
        category = CategoryClassifier.classify(title)
        goal = kind == .goal
            ? nil
            : GoalMatcher.match(title, among: goals.filter(\.isActive).map(\.candidate))
        icon = kind == .habit ? HabitIconSuggester.icon(for: title, category: nil) : nil
    }
}
