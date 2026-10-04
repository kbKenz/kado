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

    /// Least share of the answer's words that must come from the note.
    /// Tidying keeps most words and adds a few ("to", "the"); a refusal
    /// or an answer to the note shares almost none.
    static let minimumKeptWordShare = 0.5

    /// Whether a cleanup answer is still the user's note. Words are
    /// compared without case or accents, and a word counts as kept
    /// when it is close to a note word (a spelling fix). Without this
    /// check, "I cannot help you with that request." replaced a note.
    static func isPlausibleCleanup(_ output: String, of note: String) -> Bool {
        let outputWords = words(in: output)
        guard !outputWords.isEmpty else { return false }
        let noteWords = Set(words(in: note))
        let kept = outputWords.filter { word in
            noteWords.contains { isSpellingVariant($0, of: word) }
        }
        return Double(kept.count) / Double(outputWords.count) >= minimumKeptWordShare
    }

    private static func words(in text: String) -> [String] {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
    }

    /// Equal, or a few edits apart: one edit for every three letters
    /// of the shorter word, and at least one.
    private static func isSpellingVariant(_ a: String, of b: String) -> Bool {
        if a == b { return true }
        let allowed = max(1, min(a.count, b.count) / 3)
        return editDistance(Array(a), Array(b)) <= allowed
    }

    private static func editDistance(_ a: [Character], _ b: [Character]) -> Int {
        var previous = Array(0...b.count)
        for (i, ca) in a.enumerated() {
            var current = [i + 1]
            for (j, cb) in b.enumerated() {
                current.append(min(previous[j + 1] + 1, current[j] + 1, previous[j] + (ca == cb ? 0 : 1)))
            }
            previous = current
        }
        return previous[b.count]
    }
}
