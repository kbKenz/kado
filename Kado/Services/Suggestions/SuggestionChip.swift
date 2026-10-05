import Foundation
import KadoCore

/// One chip of the suggestion strip: a value the app filled in
/// (applied, shown with a checkmark) or one the person can apply with a
/// tap (offered, shown with a plus). A field has one chip at most.
nonisolated struct SuggestionChip: Identifiable, Hashable, Sendable {
    nonisolated enum Field: String, Hashable, Sendable, CaseIterable {
        case category
        case goal
        case icon
        case color
    }

    nonisolated enum Value: Hashable, Sendable {
        case category(ItemCategory)
        case goal(UUID)
        case icon(String)
        case color(HabitColor)

        var field: Field {
            switch self {
            case .category: .category
            case .goal: .goal
            case .icon: .icon
            case .color: .color
            }
        }
    }

    let value: Value
    /// `true` when the app filled the field in; `false` for an offer.
    let isApplied: Bool

    var field: Field { value.field }
    var id: Field { field }
}

extension SuggestionChip {
    /// The goal a goal chip names.
    var goalID: UUID? {
        if case .goal(let id) = value { return id }
        return nil
    }

    /// The chip's visible text. `goalName` names a goal chip's goal.
    func title(goalName: String?) -> String {
        switch value {
        case .category(let category):
            return category.localizedName
        case .goal:
            return goalName ?? ""
        case .icon:
            return String(localized: "Icon", comment: "Suggestion chip: the habit icon the app picked from the name.")
        case .color:
            return String(localized: "Colour", comment: "Suggestion chip: the habit colour the app picked from the category.")
        }
    }

    /// What VoiceOver reads for a value the app filled in. Also the
    /// announcement when it is filled in.
    func appliedLabel(goalName: String?) -> String {
        switch value {
        case .category(let category):
            return String(localized: "Suggested category: \(category.localizedName)", comment: "VoiceOver: the app filled in this category from the title.")
        case .goal:
            return String(localized: "Suggested goal: \(goalName ?? "")", comment: "VoiceOver: the app linked this goal from the title.")
        case .icon:
            return String(localized: "Suggested icon", comment: "VoiceOver: the app picked the habit icon from the name.")
        case .color:
            return String(localized: "Suggested colour", comment: "VoiceOver: the app picked the habit colour from the category.")
        }
    }

    /// What VoiceOver reads for an offered chip: what a tap does.
    func offerLabel(goalName: String?) -> String {
        switch value {
        case .category(let category):
            return String(localized: "Set category to \(category.localizedName)", comment: "Suggestion chip button: sets the form's category.")
        case .goal:
            return String(localized: "Link to \(goalName ?? "")", comment: "Suggestion chip button: links the task or habit to this goal.")
        case .icon:
            return String(localized: "Use the suggested icon", comment: "Suggestion chip button: sets the habit icon the app picked.")
        case .color:
            return String(localized: "Use the suggested colour", comment: "Suggestion chip button: sets the habit colour the app picked.")
        }
    }
}
