import Foundation

/// Text handling shared by the keyword suggesters. A title is folded
/// (case and accents removed) and split into words, so
/// "Réviser l'ÉCOLE" reads as `["reviser", "l", "ecole"]`.
nonisolated enum TitleText {
    /// Removes case and accents: "Méditer" becomes "mediter".
    static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }

    /// The folded words of `text`. Every character that is not a letter
    /// separates two words, so digits and punctuation never count.
    static func words(_ text: String) -> [String] {
        fold(text).split(whereSeparator: { !$0.isLetter }).map(String.init)
    }

    /// `word` without a trailing "s", and without a trailing "es", when
    /// it ends that way. "classes" gives "classe" and "class".
    static func singularForms(of word: String) -> [String] {
        var forms: [String] = []
        if word.hasSuffix("s") { forms.append(String(word.dropLast())) }
        if word.hasSuffix("es") { forms.append(String(word.dropLast(2))) }
        return forms
    }
}

/// A keyword list entry: one word ("rent") or a phrase ("go to bed"),
/// stored folded.
nonisolated struct TitleKeyword: Sendable {
    let words: [String]

    init(_ text: String) {
        words = TitleText.words(text)
    }

    var isPhrase: Bool { words.count > 1 }
}

/// The words of one title, each with the forms it can match.
///
/// A word matches a keyword when it is equal to it, or equal to it
/// after dropping a trailing "s" or "es". A word that is itself one of
/// the `exactWords` matches only as written. So the French "courses"
/// (shopping) never also reads as "cours" or "course" (a class).
nonisolated struct TitleWords: Sendable {
    /// For each word of the title, in order, the forms it can match.
    let forms: [Set<String>]

    init(_ title: String, exactWords: Set<String>) {
        forms = TitleText.words(title).map { word in
            exactWords.contains(word) ? [word] : Set([word] + TitleText.singularForms(of: word))
        }
    }

    var isEmpty: Bool { forms.isEmpty }

    /// The positions of the words that match one of `words`.
    func positions(matching words: Set<String>) -> Set<Int> {
        Set(forms.indices.filter { !forms[$0].isDisjoint(with: words) })
    }

    /// The positions of the words covered by each place where `phrase`
    /// appears as consecutive words.
    func positions(of phrase: [String]) -> Set<Int> {
        guard !phrase.isEmpty, phrase.count <= forms.count else { return [] }
        var positions: Set<Int> = []
        for start in 0...(forms.count - phrase.count)
        where phrase.indices.allSatisfy({ forms[start + $0].contains(phrase[$0]) }) {
            positions.formUnion(start..<(start + phrase.count))
        }
        return positions
    }
}
