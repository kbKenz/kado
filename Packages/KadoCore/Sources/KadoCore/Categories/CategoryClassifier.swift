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
/// A title word that matches no keyword as written can still match a
/// long keyword (8 letters or more) with a typo: same first letter, and
/// at most a third of the shorter word's letters apart (see
/// `isTypo(_:of:)`). So "proffesors" still reads as "professor". There is
/// no prefix matching: "cours" (class) never matches "courses".
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
        let typos = typoPositions(in: words)
        var best: ItemCategory?
        var bestScore = 0
        for category in priority {
            guard let keywords = keywords[category] else { continue }
            var covered = keywords.phrases.reduce(into: words.positions(matching: keywords.words)) {
                $0.formUnion(words.positions(of: $1))
            }
            covered.formUnion(typos[category] ?? [])
            let score = covered.count
            if score > bestScore {
                best = category
                bestScore = score
            }
        }
        return best
    }

    /// For each category, the positions of the title words that are a
    /// typo of one of its long keywords. A word that matches any keyword
    /// as written is never read as a typo. When a word is a typo of
    /// several keywords, only the closest ones count: "meditaton" is one
    /// edit from "meditation" and two from "medication".
    static func typoPositions(in words: TitleWords) -> [ItemCategory: Set<Int>] {
        var result: [ItemCategory: Set<Int>] = [:]
        for (position, forms) in words.forms.enumerated() where forms.isDisjoint(with: vocabulary) {
            let candidates = longKeywords.compactMap { keyword -> (category: ItemCategory, distance: Int)? in
                let distances = forms.compactMap { typoDistance($0, from: keyword.word) }
                return distances.min().map { (keyword.category, $0) }
            }
            guard let closest = candidates.map(\.distance).min() else { continue }
            for candidate in candidates where candidate.distance == closest {
                result[candidate.category, default: []].insert(position)
            }
        }
        return result
    }

    /// Whether `word` is a typo of `keyword`: same first letter, and at
    /// most `n / 3` edits apart, where `n` is the shorter word's length.
    static func isTypo(_ word: String, of keyword: String) -> Bool {
        typoDistance(word, from: keyword) != nil
    }

    /// The edits between `word` and `keyword` when `word` is a typo of
    /// it (see `isTypo(_:of:)`), else `nil`.
    static func typoDistance(_ word: String, from keyword: String) -> Int? {
        guard word != keyword, word.first == keyword.first else { return nil }
        let allowance = min(word.count, keyword.count) / 3
        guard allowance > 0, abs(word.count - keyword.count) <= allowance else { return nil }
        let distance = TitleText.editDistance(word, keyword)
        return distance <= allowance ? distance : nil
    }

    /// Keywords long enough to be matched with a typo.
    static let minimumTypoLength = 8

    /// The single-word keywords of `minimumTypoLength` letters or more,
    /// with their category.
    static let longKeywords: [(word: String, category: ItemCategory)] = priority.flatMap { category in
        (keywords[category]?.words ?? [])
            .filter { $0.count >= minimumTypoLength }
            .sorted()
            .map { (word: $0, category: category) }
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
