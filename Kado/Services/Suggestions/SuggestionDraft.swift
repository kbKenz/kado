import Foundation
import Observation
import KadoCore

/// The title suggestions of one form: the category, the goal (tasks and
/// habits), and the icon and colour (habits), each with who set it.
///
/// The rules:
/// - A suggestion fills only a field the person has not touched in
///   this sheet. Any change by the person sets `.user`, even back to
///   "None", "No goal" or the circle icon, and the field never changes
///   again.
/// - `applyWords` runs the word tier on each title change. A strong
///   goal match is applied; a weak one is offered as a chip. The
///   category comes from the keywords; a task follows its goal's own
///   category first. A habit's icon comes from its keywords, else from
///   its category, and its colour from its category.
/// - `applyModel` adds the on-device model's answer for the same title.
///   It fills only what the words left empty, and offers goals, never
///   applies them.
/// - A cleared title puts every field the title filled back to its
///   default. A task's category that follows the person's own goal
///   stays: it comes from their choice, not from the title.
/// - Edit forms (`isEditing`) never apply anything; they offer chips
///   for empty fields.
/// - `undo()` puts the applied fields back to their defaults and locks
///   them.
@MainActor
@Observable
final class SuggestionDraft {
    /// The colour a new habit starts with (`NewHabitFormModel`'s).
    nonisolated static let defaultColor: HabitColor = .blue
    nonisolated static let defaultIcon: String = HabitIcon.default

    let kind: ItemSuggestionKind
    let isEditing: Bool

    private(set) var category: ItemCategory?
    private(set) var categoryOrigin: SuggestionOrigin = .default
    private(set) var goalID: UUID?
    private(set) var goalOrigin: SuggestionOrigin = .default
    private(set) var icon: String = SuggestionDraft.defaultIcon
    private(set) var iconOrigin: SuggestionOrigin = .default
    private(set) var color: HabitColor = SuggestionDraft.defaultColor
    private(set) var colorOrigin: SuggestionOrigin = .default

    /// The strip's chips, in field order: at most one per field.
    private(set) var chips: [SuggestionChip] = []

    /// The trimmed title the suggestions were last computed for.
    private(set) var title = ""
    /// Every goal the form can link, active or not.
    private(set) var goals: [SuggestionGoal] = []
    /// Set while the form saves: nothing changes any more.
    private(set) var isFrozen = false

    @ObservationIgnored private var words: WordSuggestion?
    @ObservationIgnored private var model: (title: String, suggestion: ModelItemSuggestion)?
    @ObservationIgnored private var announcedValues: Set<SuggestionChip.Value> = []
    @ObservationIgnored private var pendingAnnouncement: String?

    init(kind: ItemSuggestionKind, isEditing: Bool = false) {
        self.kind = kind
        self.isEditing = isEditing
    }

    // MARK: - Setup

    /// Loads a saved item into an edit form. A value other than the
    /// field's default counts as the person's choice, and so does a
    /// colour.
    func load(category: ItemCategory?, goalID: UUID?, icon: String? = nil, color: HabitColor? = nil) {
        self.category = category
        categoryOrigin = category == nil ? .default : .user
        self.goalID = goalID
        goalOrigin = goalID == nil ? .default : .user
        if let icon {
            self.icon = icon
            iconOrigin = icon == Self.defaultIcon ? .default : .user
        }
        if let color {
            self.color = color
            colorOrigin = .user
        }
        recompute()
    }

    /// A form opened from a goal starts on that goal, as the person's
    /// choice: suggestions never change it.
    func presetGoal(_ id: UUID) {
        goalID = id
        goalOrigin = .user
        recompute()
    }

    // MARK: - The person's changes

    func userSetCategory(_ value: ItemCategory?) {
        category = value
        categoryOrigin = .user
        recompute()
    }

    func userSetGoal(_ id: UUID?) {
        goalID = id
        goalOrigin = .user
        recompute()
    }

    func userSetIcon(_ value: String) {
        icon = value
        iconOrigin = .user
        recompute()
    }

    func userSetColor(_ value: HabitColor) {
        color = value
        colorOrigin = .user
        recompute()
    }

    /// A tap on a chip: the person takes the offered value.
    func accept(_ chip: SuggestionChip) {
        switch chip.value {
        case .category(let value): userSetCategory(value)
        case .goal(let id): userSetGoal(id)
        case .icon(let value): userSetIcon(value)
        case .color(let value): userSetColor(value)
        }
    }

    // MARK: - Suggestions

    /// The word tier, for the title as it is now. Synchronous.
    func applyWords(title: String, goals: [SuggestionGoal]) {
        guard !isFrozen else { return }
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        self.title = trimmed
        self.goals = goals
        words = trimmed.isEmpty ? nil : WordSuggestion(title: trimmed, goals: goals, kind: kind)
        recompute()
    }

    /// The model's answer. Dropped when the title has changed since the
    /// request.
    func applyModel(_ suggestion: ModelItemSuggestion, for title: String) {
        guard !isFrozen else { return }
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed == self.title else { return }
        model = (trimmed, suggestion)
        recompute()
    }

    /// Whether the words left a field empty that the model could fill
    /// or offer, so a request is worth making.
    var wantsModel: Bool {
        guard !isFrozen, Self.hasLongWord(title) else { return false }
        let openCategory = categoryOrigin != .user && category == nil
        let openGoal = kind != .goal && goalOrigin != .user && goalID == nil
            && goals.contains(where: \.isActive)
        let openIcon = kind == .habit && iconOrigin != .user && words?.icon == nil
        return openCategory || openGoal || openIcon
    }

    // MARK: - Undo

    /// Whether any field holds a value the app filled in.
    var canUndo: Bool {
        [categoryOrigin, goalOrigin, iconOrigin, colorOrigin].contains(.suggested)
    }

    /// Puts every applied field back to its default and locks it for
    /// this sheet.
    func undo() {
        if categoryOrigin == .suggested {
            category = nil
            categoryOrigin = .user
        }
        if goalOrigin == .suggested {
            goalID = nil
            goalOrigin = .user
        }
        if iconOrigin == .suggested {
            icon = Self.defaultIcon
            iconOrigin = .user
        }
        if colorOrigin == .suggested {
            color = Self.defaultColor
            colorOrigin = .user
        }
        recompute()
    }

    // MARK: - Saving

    /// Stops every change from suggestions while the form saves.
    func freeze() {
        isFrozen = true
    }

    /// Lets suggestions run again after a save that failed.
    func thaw() {
        isFrozen = false
    }

    // MARK: - VoiceOver

    /// The sentence to announce for a newly applied set of values, once.
    func takeAnnouncement() -> String? {
        defer { pendingAnnouncement = nil }
        return pendingAnnouncement
    }

    /// The name of one of the form's goals.
    func goalName(for id: UUID) -> String? {
        goals.first { $0.id == id }?.name
    }

    // MARK: - Rules

    private func recompute() {
        guard !isFrozen else { return }
        let hasTitle = !title.isEmpty
        let modelSuggestion = model.flatMap { $0.title == title ? $0.suggestion : nil }

        if !isEditing {
            applyGoal()
            applyCategory(hasTitle: hasTitle, model: modelSuggestion)
            if kind == .habit {
                applyIcon(hasTitle: hasTitle, model: modelSuggestion)
                applyColor()
            }
        }
        chips = makeChips(hasTitle: hasTitle, model: modelSuggestion)
        noteNewlyApplied()
    }

    /// Only a strong word match is applied. No match, or a weak one,
    /// puts a suggested goal back to "No goal".
    private func applyGoal() {
        guard kind != .goal, goalOrigin != .user else { return }
        if let match = words?.goal, match.isStrong, goals.contains(where: { $0.id == match.goalID }) {
            goalID = match.goalID
            goalOrigin = .suggested
        } else if goalOrigin == .suggested {
            goalID = nil
            goalOrigin = .default
        }
    }

    /// A task follows its goal's own category; then the keywords, then
    /// the model.
    private func applyCategory(hasTitle: Bool, model: ModelItemSuggestion?) {
        guard categoryOrigin != .user else { return }
        let titleCategory = hasTitle ? (words?.category ?? model?.category) : nil
        if let wanted = followedGoalCategory ?? titleCategory {
            category = wanted
            categoryOrigin = .suggested
        } else if categoryOrigin == .suggested {
            category = nil
            categoryOrigin = .default
        }
    }

    /// Keywords first, then the model, then the category's own icon.
    private func applyIcon(hasTitle: Bool, model: ModelItemSuggestion?) {
        guard iconOrigin != .user else { return }
        let titleIcon = hasTitle ? (words?.icon ?? model?.icon) : nil
        if let wanted = titleIcon ?? category?.defaultHabitIcon {
            icon = wanted
            iconOrigin = .suggested
        } else if iconOrigin == .suggested {
            icon = Self.defaultIcon
            iconOrigin = .default
        }
    }

    /// The category's palette slot.
    private func applyColor() {
        guard colorOrigin != .user else { return }
        if let wanted = category?.color {
            color = wanted
            colorOrigin = .suggested
        } else if colorOrigin == .suggested {
            color = Self.defaultColor
            colorOrigin = .default
        }
    }

    /// The category of the task's current goal, when it has one.
    private var followedGoalCategory: ItemCategory? {
        guard kind == .task, let goalID else { return nil }
        return goals.first { $0.id == goalID }?.category
    }

    private func makeChips(hasTitle: Bool, model: ModelItemSuggestion?) -> [SuggestionChip] {
        var chips: [SuggestionChip] = []
        if categoryOrigin == .suggested, let category {
            chips.append(SuggestionChip(value: .category(category), isApplied: true))
        } else if categoryOrigin == .default, category == nil,
                  let offer = categoryOffer(hasTitle: hasTitle, model: model) {
            chips.append(SuggestionChip(value: .category(offer), isApplied: false))
        }
        if kind != .goal {
            if goalOrigin == .suggested, let goalID {
                chips.append(SuggestionChip(value: .goal(goalID), isApplied: true))
            } else if goalOrigin == .default, goalID == nil, let offer = goalOffer(model: model) {
                chips.append(SuggestionChip(value: .goal(offer), isApplied: false))
            }
        }
        if kind == .habit {
            if iconOrigin == .suggested {
                chips.append(SuggestionChip(value: .icon(icon), isApplied: true))
            } else if isEditing, iconOrigin == .default, icon == Self.defaultIcon,
                      let offer = iconOffer(hasTitle: hasTitle, model: model) {
                chips.append(SuggestionChip(value: .icon(offer), isApplied: false))
            }
            if colorOrigin == .suggested {
                chips.append(SuggestionChip(value: .color(color), isApplied: true))
            }
        }
        return chips
    }

    /// Edit forms only: the item's resolved category (its goal's, else
    /// the keywords'), else the model's. Never Other.
    private func categoryOffer(hasTitle: Bool, model: ModelItemSuggestion?) -> ItemCategory? {
        guard isEditing else { return nil }
        let goalCategory = goalID.flatMap { id in goals.first { $0.id == id }?.category }
        let resolved = CategoryResolver.resolve(stored: nil, goalCategory: goalCategory, title: title)
        if resolved != .other { return resolved }
        return hasTitle ? model?.category : nil
    }

    /// A word match that was not applied (weak, or any match in an edit
    /// form), else the model's goal.
    private func goalOffer(model: ModelItemSuggestion?) -> UUID? {
        let activeIDs = Set(goals.filter(\.isActive).map(\.id))
        if let match = words?.goal, isEditing || !match.isStrong, activeIDs.contains(match.goalID) {
            return match.goalID
        }
        if let id = model?.goalID, activeIDs.contains(id) {
            return id
        }
        return nil
    }

    /// Edit forms only, for a habit still on the circle icon.
    private func iconOffer(hasTitle: Bool, model: ModelItemSuggestion?) -> String? {
        let titleIcon = hasTitle ? (words?.icon ?? model?.icon) : nil
        return titleIcon ?? category?.defaultHabitIcon
    }

    /// Queues one announcement when the set of applied values gains a
    /// value it did not have.
    private func noteNewlyApplied() {
        let applied = chips.filter(\.isApplied)
        let appliedValues = Set(applied.map(\.value))
        defer { announcedValues = appliedValues }
        guard !appliedValues.isEmpty, !appliedValues.isSubset(of: announcedValues) else { return }
        let values = applied.map { $0.appliedLabel(goalName: $0.goalID.flatMap(goalName(for:))) }
        let undo = String(localized: "Undo is available.", comment: "VoiceOver, after the app filled in form fields from the title.")
        pendingAnnouncement = values.joined(separator: ". ") + ". " + undo
    }

    /// Whether `text` has a word of 4 letters or more, the least the
    /// model is asked about.
    nonisolated static func hasLongWord(_ text: String) -> Bool {
        text.split(whereSeparator: { !$0.isLetter }).contains { $0.count >= 4 }
    }
}
