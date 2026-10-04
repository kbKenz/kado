import Foundation

/// Picks the cleanup engine for this OS. The deployment target is
/// iOS 18; Foundation Models exists only from iOS 26.
enum TextCleanerFactory {
    static func make() -> any TextCleaning {
        if #available(iOS 26, *) {
            return FoundationModelsTextCleaner()
        }
        return UnavailableTextCleaner()
    }
}
