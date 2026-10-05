import Foundation

/// On-device suggestions from a language model for the title being
/// typed: a category, a goal and, for habits, an icon, each from a
/// closed list. The word tier (`WordSuggestion`) works without it.
protocol ItemSuggesting: AnyObject {
    /// `false` when no on-device model can serve the current locale.
    /// Forms then never ask.
    var isAvailable: Bool { get }

    /// Answers with values from the closed lists only. Throws on any
    /// failure; the form keeps its word suggestions, silently.
    func suggest(_ request: ItemSuggestionRequest) async throws -> ModelItemSuggestion

    /// Loads the model before the first request, when a form opens.
    func prewarm()
}

extension ItemSuggesting {
    func prewarm() {}
}
