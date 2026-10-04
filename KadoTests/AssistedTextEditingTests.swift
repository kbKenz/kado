import Testing
@testable import Kado

/// Text rules behind `.assistedInput(_:)`: where dictated words go,
/// how a field's character limit applies, and what model output is
/// accepted as a cleanup result.
@Suite("AssistedTextEditing")
struct AssistedTextEditingTests {

    // MARK: - Appending a transcript

    @Test("Transcript into an empty field is the transcript alone")
    func appendToEmpty() {
        #expect(AssistedTextEditing.appending("read more", to: "") == "read more")
    }

    @Test("Transcript after text gets exactly one space")
    func appendAddsOneSpace() {
        #expect(AssistedTextEditing.appending("every day", to: "Read") == "Read every day")
    }

    @Test("No extra space when the text already ends in whitespace")
    func appendAfterWhitespace() {
        #expect(AssistedTextEditing.appending("every day", to: "Read ") == "Read every day")
        #expect(AssistedTextEditing.appending("every day", to: "Read\n") == "Read\nevery day")
    }

    @Test("An empty transcript leaves the text unchanged")
    func appendEmptyTranscript() {
        #expect(AssistedTextEditing.appending("", to: "Read") == "Read")
    }

    // MARK: - Character limit

    @Test("No limit returns the text unchanged")
    func noLimit() {
        #expect(AssistedTextEditing.limited("abcdef", to: nil) == "abcdef")
    }

    @Test("Text under or at the limit is unchanged")
    func underAndAtLimit() {
        #expect(AssistedTextEditing.limited("abc", to: 5) == "abc")
        #expect(AssistedTextEditing.limited("abcde", to: 5) == "abcde")
    }

    @Test("Text over the limit is truncated to it")
    func overLimit() {
        #expect(AssistedTextEditing.limited("abcdefg", to: 5) == "abcde")
    }

    @Test("The limit counts characters, not bytes or scalars")
    func limitCountsCharacters() {
        #expect(AssistedTextEditing.limited("é🏃‍♀️ab", to: 2) == "é🏃‍♀️")
    }

    // MARK: - Sanitizing cleanup output

    @Test("Plain output passes through unchanged")
    func sanitizePlain() {
        #expect(AssistedTextEditing.sanitizedCleanup("Read every day.") == "Read every day.")
    }

    @Test("Surrounding whitespace and newlines are trimmed")
    func sanitizeTrims() {
        #expect(AssistedTextEditing.sanitizedCleanup("\n  Read every day. \n") == "Read every day.")
    }

    @Test("One pair of wrapping quotes is removed", arguments: [
        "\"Read every day.\"",
        "“Read every day.”",
        "«Read every day.»",
        "« Read every day. »",
    ])
    func sanitizeStripsWrappingQuotes(output: String) {
        #expect(AssistedTextEditing.sanitizedCleanup(output) == "Read every day.")
    }

    @Test("Quotes inside the text are kept")
    func sanitizeKeepsInnerQuotes() {
        #expect(AssistedTextEditing.sanitizedCleanup("Read \"Dune\" every day.") == "Read \"Dune\" every day.")
    }

    @Test("Unbalanced quotes are kept")
    func sanitizeKeepsUnbalancedQuotes() {
        #expect(AssistedTextEditing.sanitizedCleanup("\"Read every day.") == "\"Read every day.")
    }

    @Test("Empty or whitespace-only output is rejected", arguments: ["", "   ", "\n", "\"\"", "“ ”"])
    func sanitizeRejectsEmpty(output: String) {
        #expect(AssistedTextEditing.sanitizedCleanup(output) == nil)
    }
}
