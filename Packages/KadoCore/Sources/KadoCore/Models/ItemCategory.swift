import Foundation

/// The area of life a task, habit or goal belongs to.
///
/// A category gives tasks and goals their icon, gives a new habit its
/// starting icon, and groups the per-category Insights. Records store
/// it as a raw string (`categoryRaw`); an empty string means "not set",
/// and readers fall back to `CategoryResolver`.
nonisolated public enum ItemCategory: String, Codable, Hashable, Sendable, CaseIterable, Identifiable {
    case work
    case study
    case fitness
    case health
    case sleep
    case mind
    case social
    case home
    case money
    case creative
    case errands
    case other

    public var id: String { rawValue }

    /// Reads a stored raw value. An empty or unknown value is `nil`.
    public init?(storedRaw raw: String) {
        guard !raw.isEmpty else { return nil }
        self.init(rawValue: raw)
    }

    /// SF Symbol for rows, chips and chart legends.
    public var symbolName: String {
        switch self {
        case .work: "briefcase.fill"
        case .study: "graduationcap.fill"
        case .fitness: "figure.run"
        case .health: "heart.fill"
        case .sleep: "bed.double.fill"
        case .mind: "figure.mind.and.body"
        case .social: "person.2.fill"
        case .home: "house.fill"
        case .money: "creditcard.fill"
        case .creative: "paintbrush.fill"
        case .errands: "cart.fill"
        case .other: "square.grid.2x2.fill"
        }
    }

    /// Habit-palette slot that tints the category's icon and chart
    /// marks. `nil` for `.other`, which uses the neutral ink.
    public var color: HabitColor? {
        switch self {
        case .work: .blue
        case .study: .purple
        case .fitness: .orange
        case .health: .red
        case .sleep: .teal
        case .mind: .mint
        case .social: .yellow
        case .home: .green
        case .money: .green
        case .creative: .purple
        case .errands: .yellow
        case .other: nil
        }
    }

    /// The icon from `HabitIcon.curated` that a new habit in this
    /// category starts with. `nil` for `.other`.
    public var defaultHabitIcon: String? {
        switch self {
        case .work: "briefcase.fill"
        case .study: "graduationcap.fill"
        case .fitness: "figure.run"
        case .health: "heart.fill"
        case .sleep: "bed.double.fill"
        case .mind: "figure.mind.and.body"
        case .social: "person.2.fill"
        case .home: "house.fill"
        case .money: "creditcard.fill"
        case .creative: "paintbrush.fill"
        case .errands: "cart.fill"
        case .other: nil
        }
    }

    /// The name shown in pickers, rows and Insights.
    public var localizedName: String {
        switch self {
        case .work: String(localized: "Work", comment: "Category name: jobs, meetings, projects.")
        case .study: String(localized: "Study", comment: "Category name: school, university, courses, reading for class.")
        case .fitness: String(localized: "Fitness", comment: "Category name: workouts, running, sport.")
        case .health: String(localized: "Health", comment: "Calendar timeline caption: this entry comes from Apple Health.")
        case .sleep: String(localized: "Sleep", comment: "Calendar timeline: a sleep session read from Health.")
        case .mind: String(localized: "Mind", comment: "Category name: meditation, journaling, mental health.")
        case .social: String(localized: "People", comment: "Category name: family, friends, calls, messages.")
        case .home: String(localized: "Home", comment: "Category name: chores, cleaning, cooking.")
        case .money: String(localized: "Money", comment: "Category name: budget, bills, savings.")
        case .creative: String(localized: "Creative", comment: "Category name: music, art, writing, photos.")
        case .errands: String(localized: "Errands", comment: "Category name: shopping, appointments, paperwork.")
        case .other: String(localized: "Other", comment: "Category name: anything that fits no other category.")
        }
    }
}
