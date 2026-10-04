import Foundation

/// Text rules behind `.assistedInput(_:)`, kept free of UI and system
/// calls so every rule is unit-tested: where dictated words go, how a
/// field's character limit applies, and which model output counts as
/// a cleanup result.
nonisolated enum AssistedTextEditing {

    /// Quote pairs a language model may wrap its whole answer in.
    private static let wrappingQuotePairs: [(open: Character, close: Character)] = [
        ("\"", "\""),
        ("“", "”"),
        ("«", "»"),
    ]

    /// Appends a dictated transcript after the existing text, with one
    /// space between them unless `base` is empty or already ends in
    /// whitespace.
    static func appending(_ transcript: String, to base: String) -> String {
        guard !transcript.isEmpty else { return base }
        guard let last = base.last, !last.isWhitespace else { return base + transcript }
        return base + " " + transcript
    }

    /// Truncates `text` to `limit` characters. `nil` means no limit.
    static func limited(_ text: String, to limit: Int?) -> String {
        guard let limit, text.count > limit else { return text }
        return String(text.prefix(limit))
    }

    /// Normalizes a cleanup result: trims whitespace and newlines and
    /// removes one pair of quotes wrapping the whole answer. Returns
    /// `nil` when nothing is left, so an empty answer never replaces
    /// the user's text.
    static func sanitizedCleanup(_ output: String) -> String? {
        var text = output.trimmingCharacters(in: .whitespacesAndNewlines)
        if let first = text.first, let last = text.last, text.count >= 2,
           wrappingQuotePairs.contains(where: { $0.open == first && $0.close == last }) {
            text = String(text.dropFirst().dropLast())
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return text.isEmpty ? nil : text
    }
}
