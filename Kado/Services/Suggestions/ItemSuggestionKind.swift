/// What a form creates or edits. It decides which fields suggestions
/// fill: every kind gets a category, tasks and habits a goal, and habits
/// an icon and a colour.
nonisolated enum ItemSuggestionKind: String, Hashable, Sendable {
    case task
    case habit
    case goal
}
