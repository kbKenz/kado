/// Who set the current value of a form field that title suggestions can
/// fill: the category, the goal, and a habit's icon and colour.
nonisolated enum SuggestionOrigin: Hashable, Sendable {
    /// The field still holds its starting value.
    case `default`
    /// The app filled it in from the title.
    case suggested
    /// The person chose it. Suggestions never change it again in this
    /// sheet.
    case user
}
