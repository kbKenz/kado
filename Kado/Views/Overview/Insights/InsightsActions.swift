import Foundation
import KadoCore

/// What the Insights cards can ask for. The cards only render a report;
/// the screen that hosts them decides what each action does.
struct InsightsActions {
    /// Open a habit's detail screen.
    var openHabit: (UUID) -> Void
    /// Open a goal's detail screen.
    var openGoal: (UUID) -> Void
    /// Turn on Apple Health for the Sleep and Movement cards.
    var connectHealth: () -> Void
    /// Start a new habit from a one-tap template.
    var addHabitTemplate: (InsightsHabitTemplate) -> Void

    /// Does nothing. For previews.
    static let none = InsightsActions(
        openHabit: { _ in },
        openGoal: { _ in },
        connectHealth: {},
        addHabitTemplate: { _ in }
    )
}

/// A habit the Sleep and Movement cards offer to create with one tap,
/// when the user has none in that category yet.
enum InsightsHabitTemplate: String, Identifiable {
    case sleep
    case workout

    var id: String { rawValue }

    /// The name the New Habit form starts with.
    var name: String {
        switch self {
        case .sleep:
            String(localized: "Sleep 7+ hours", comment: "Name a new habit starts with when created from the Insights Sleep card.")
        case .workout:
            String(localized: "Work out", comment: "Name a new habit starts with when created from the Insights Movement card.")
        }
    }

    /// The icon the New Habit form starts with. Both are in
    /// `HabitIcon.curated`, so the picker shows them selected.
    var icon: String {
        switch self {
        case .sleep: "bed.double.fill"
        case .workout: "figure.run"
        }
    }

    /// The colour of the template's category, so the new habit matches
    /// the card it came from.
    var color: HabitColor {
        switch self {
        case .sleep: ItemCategory.sleep.color ?? .teal
        case .workout: ItemCategory.fitness.color ?? .orange
        }
    }
}
