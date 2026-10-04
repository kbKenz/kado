import Foundation

/// On-device "clean up" for `.assistedInput(_:)`: fixes grammar,
/// punctuation, filler words and repeats, and keeps the user's words,
/// meaning and language.
protocol TextCleaning: AnyObject {
    /// `false` when no on-device model can serve the current locale.
    /// The cleanup button hides.
    var isAvailable: Bool { get }

    /// Returns the tidied text, already passed through
    /// `AssistedTextEditing.sanitizedCleanup`. Throws an
    /// `AssistedInputError` instead of returning empty text.
    func clean(_ text: String) async throws -> String
}
