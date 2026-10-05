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

    /// The number of edits that turn `lhs` into `rhs`: inserting,
    /// deleting or replacing one letter, or swapping two letters next
    /// to each other (optimal string alignment). A letter takes part in
    /// one swap at most, so "ca" to "abc" is 3, not 2.
    static func editDistance(_ lhs: String, _ rhs: String) -> Int {
        let a = Array(lhs)
        let b = Array(rhs)
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }
        // Three rows of the classic table: two rows back, one row
        // back, and the current one.
        var twoBack = [Int](repeating: 0, count: b.count + 1)
        var oneBack = Array(0...b.count)
        var current = [Int](repeating: 0, count: b.count + 1)
        for i in 1...a.count {
            current[0] = i
            for j in 1...b.count {
                let cost = a[i - 1] == b[j - 1] ? 0 : 1
                var value = min(
                    oneBack[j] + 1,        // delete
                    current[j - 1] + 1,    // insert
                    oneBack[j - 1] + cost  // replace
                )
                if i > 1, j > 1, a[i - 1] == b[j - 2], a[i - 2] == b[j - 1] {
                    value = min(value, twoBack[j - 2] + 1)  // swap
                }
                current[j] = value
            }
            (twoBack, oneBack, current) = (oneBack, current, twoBack)
        }
        return oneBack[b.count]
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
