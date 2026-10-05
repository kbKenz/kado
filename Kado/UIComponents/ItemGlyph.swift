import KadoCore

/// The small icon beside a title: a task's or goal's category symbol in
/// the category's colour, or a habit's own icon in its colour (habits
/// keep their icon). A value, so rows, calendar blocks and the Now
/// screen can carry it without a record (issue #63).
nonisolated struct ItemGlyph: Hashable, Sendable {
    let symbolName: String
    /// Palette slot for the tint. `nil` draws in the secondary ink, as
    /// for `ItemCategory.other`.
    let color: HabitColor?
    /// The category name VoiceOver reads after the title. `nil` for a
    /// habit's own icon, which has no name to read.
    let categoryName: String?

    init(category: ItemCategory) {
        symbolName = category.symbolName
        color = category.color
        categoryName = category.localizedName
    }

    init(habitIcon: String, color: HabitColor) {
        symbolName = habitIcon
        self.color = color
        categoryName = nil
    }
}
