import Foundation

/// What the on-device model is asked: the title being typed, the kind
/// of item, and the active goals' names and details. Nothing else from
/// the form goes into a request.
nonisolated struct ItemSuggestionRequest: Hashable, Sendable {
    /// A goal the model can choose, numbered "g1", "g2"… in the prompt
    /// by its position in `goals`.
    nonisolated struct Goal: Hashable, Sendable {
        let id: UUID
        let name: String
        let details: String
    }

    let title: String
    let kind: ItemSuggestionKind
    /// Active goals, most recently updated first, at most
    /// `maximumGoals`. Empty for a goal form, which links no goal.
    let goals: [Goal]

    static let maximumGoals = 20

    init(title: String, kind: ItemSuggestionKind, goals: [SuggestionGoal]) {
        self.title = title
        self.kind = kind
        guard kind != .goal else {
            self.goals = []
            return
        }
        self.goals = goals
            .filter(\.isActive)
            .sorted { $0.updatedAt > $1.updatedAt }
            .prefix(Self.maximumGoals)
            .map { Goal(id: $0.id, name: $0.name, details: $0.details) }
    }
}
