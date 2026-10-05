import Foundation

/// Picks the suggestion model for this OS. The deployment target is
/// iOS 18; Foundation Models exists only from iOS 26.
enum ItemSuggesterFactory {
    static func make() -> any ItemSuggesting {
        if #available(iOS 26, *) {
            return FoundationModelsItemSuggester()
        }
        return UnavailableItemSuggester()
    }
}
