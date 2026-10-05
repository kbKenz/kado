import Foundation

/// The category to show and count for an item, even when none is
/// stored. Pure: reading never writes the result back.
nonisolated public enum CategoryResolver {
    /// The stored category, else the linked goal's category, else the
    /// keyword guess from the title, else `.other`.
    public static func resolve(stored: ItemCategory?, goalCategory: ItemCategory?, title: String) -> ItemCategory {
        stored ?? goalCategory ?? CategoryClassifier.classify(title) ?? .other
    }
}
