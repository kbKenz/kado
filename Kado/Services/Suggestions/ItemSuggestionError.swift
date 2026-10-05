/// Why the on-device model gave no suggestion. Forms never show it:
/// they keep the word suggestions.
nonisolated enum ItemSuggestionError: Error, Hashable, Sendable {
    /// No model for this device or language right now.
    case unavailable
    /// The model refused, failed or answered outside the lists.
    case failed
}
