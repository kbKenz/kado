import Foundation

/// Guesses the category of a task, habit or goal from its title, with
/// English and French keyword lists. Pure and on device.
///
/// The title is folded (case and accents removed) and split into whole
/// words. A word also matches a keyword when it is equal to it after
/// dropping a trailing "s" or "es" ("professors" matches "professor").
/// A keyword can be a phrase ("go to bed"), which matches consecutive
/// words.
///
/// A category's score is the number of title words its keywords cover:
/// words that match one of its words, and words inside one of its
/// phrases. A word counts once per category. The highest score wins; a
/// tie goes to the category that comes first in `priority`. With no
/// match the result is `nil`, never `.other`.
nonisolated public enum CategoryClassifier {
    /// The category for `title`, or `nil` when no keyword matches.
    public static func classify(_ title: String) -> ItemCategory? {
        let words = TitleWords(title, exactWords: vocabulary)
        guard !words.isEmpty else { return nil }
        var best: ItemCategory?
        var bestScore = 0
        for category in priority {
            guard let keywords = keywords[category] else { continue }
            let covered = keywords.phrases.reduce(into: words.positions(matching: keywords.words)) {
                $0.formUnion(words.positions(of: $1))
            }
            let score = covered.count
            if score > bestScore {
                best = category
                bestScore = score
            }
        }
        return best
    }

    /// The tie order: on equal scores, the earlier category wins.
    /// `.other` is not listed, so it is never returned.
    static let priority: [ItemCategory] = [
        .fitness, .sleep, .health, .mind, .study, .work,
        .money, .home, .errands, .social, .creative
    ]

    /// One category's keywords, folded: single words and phrases.
    struct Keywords: Sendable {
        var words: Set<String> = []
        var phrases: [[String]] = []
    }

    /// The English and French lists of each category, folded and
    /// merged. A keyword that is in both lists counts once.
    static let keywords: [ItemCategory: Keywords] = {
        var result: [ItemCategory: Keywords] = [:]
        for list in [english, french] {
            for (category, entries) in list {
                var keywords = result[category] ?? Keywords()
                for entry in entries.map(TitleKeyword.init) {
                    if entry.isPhrase {
                        if !keywords.phrases.contains(entry.words) { keywords.phrases.append(entry.words) }
                    } else if let word = entry.words.first {
                        keywords.words.insert(word)
                    }
                }
                result[category] = keywords
            }
        }
        return result
    }()

    /// Every single-word keyword. A title word in this set matches only
    /// as written (see `TitleWords`).
    static let vocabulary: Set<String> = keywords.values.reduce(into: []) { $0.formUnion($1.words) }
}
