import Foundation

/// A goal the matcher can pick: its identity, its name and its details.
nonisolated public struct GoalCandidate: Hashable, Sendable {
    public var id: UUID
    public var name: String
    /// The goal's "why this matters" text. Its words count half as much
    /// as the name's.
    public var details: String

    public init(id: UUID, name: String, details: String = "") {
        self.id = id
        self.name = name
        self.details = details
    }
}

/// The goal a title points to, and how sure the matcher is.
nonisolated public struct GoalMatch: Hashable, Sendable {
    public var goalID: UUID
    /// `true` when at least one word of the goal's name matched. Only a
    /// strong match may be applied without a tap; a weak one (details
    /// words only) is offered.
    public var isStrong: Bool

    public init(goalID: UUID, isStrong: Bool) {
        self.goalID = goalID
        self.isStrong = isStrong
    }
}

/// Picks the goal a new task or habit most likely serves, from the
/// words its title shares with each goal. Pure and on device.
///
/// Texts are folded and split into words like in `CategoryClassifier`.
/// Common English and French words and words of fewer than 4 letters
/// are dropped. A goal's words are its name's (weight 2) and its
/// details' (weight 1). A word counts only when no other goal has a
/// matching word, so a word that two goals share never decides.
///
/// Two words match when they are equal, when one is a prefix of the
/// other and the shorter has 5 letters or more, or when they start with
/// the same letter and are a few edits apart (see `matches`). Typos
/// such as "cambrrdgige" still find "Cambridge".
///
/// A goal's score is the sum of the weights of its matched words, each
/// word once. The best goal wins only when its score is strictly higher
/// than the second's.
nonisolated public enum GoalMatcher {
    static let nameWeight = 2
    static let detailsWeight = 1

    /// The goal `title` points to, or `nil` when no goal scores, or two
    /// goals tie for the best score.
    public static func match(_ title: String, among goals: [GoalCandidate]) -> GoalMatch? {
        let titleWords = Set(significantWords(title))
        guard !titleWords.isEmpty, !goals.isEmpty else { return nil }
        let vocabularies = goals.map(vocabulary(of:))
        var best: (match: GoalMatch, score: Int)?
        var isTied = false
        for (index, goal) in goals.enumerated() {
            var score = 0
            var isStrong = false
            for (word, weight) in vocabularies[index] {
                guard titleWords.contains(where: { matches($0, word) }) else { continue }
                // A word another goal also has never decides.
                let isShared = vocabularies.indices.contains { other in
                    other != index && vocabularies[other].keys.contains { matches($0, word) }
                }
                guard !isShared else { continue }
                score += weight
                if weight == nameWeight { isStrong = true }
            }
            guard score > 0 else { continue }
            if let current = best, score <= current.score {
                if score == current.score { isTied = true }
                continue
            }
            best = (GoalMatch(goalID: goal.id, isStrong: isStrong), score)
            isTied = false
        }
        return isTied ? nil : best?.match
    }

    /// The goal with a strong match for `title`, else `nil`.
    public static func bestGoal(for title: String, among goals: [GoalCandidate]) -> UUID? {
        guard let match = match(title, among: goals), match.isStrong else { return nil }
        return match.goalID
    }

    /// Whether two folded words count as the same word: equal, one a
    /// prefix of the other with 5 letters or more, or the same first
    /// letter and few enough edits apart. The edits allowed depend on
    /// the shorter word's length `n`: none under 5 letters, 1 for 5 to
    /// 7, and `n / 3` (rounded down) from 8.
    static func matches(_ lhs: String, _ rhs: String) -> Bool {
        if lhs == rhs { return true }
        let (shorter, longer) = lhs.count <= rhs.count ? (lhs, rhs) : (rhs, lhs)
        if shorter.count >= 5, longer.hasPrefix(shorter) { return true }
        guard lhs.first == rhs.first else { return false }
        let allowance = typoAllowance(forLength: shorter.count)
        guard allowance > 0, longer.count - shorter.count <= allowance else { return false }
        return TitleText.editDistance(lhs, rhs) <= allowance
    }

    /// Edits allowed between two words whose shorter one has `length`
    /// letters.
    static func typoAllowance(forLength length: Int) -> Int {
        switch length {
        case ..<5: 0
        case 5...7: 1
        default: length / 3
        }
    }

    /// A goal's significant words and their weight. A word in both the
    /// name and the details keeps the name's weight.
    static func vocabulary(of goal: GoalCandidate) -> [String: Int] {
        var result: [String: Int] = [:]
        for word in significantWords(goal.details) { result[word] = detailsWeight }
        for word in significantWords(goal.name) { result[word] = nameWeight }
        return result
    }

    /// The folded words of `text` that can link a title to a goal.
    static func significantWords(_ text: String) -> [String] {
        TitleText.words(text).filter { $0.count >= 4 && !stopWords.contains($0) }
    }

    /// Words too common to link a title to a goal, folded. Words of
    /// fewer than 4 letters are dropped anyway; the short ones are
    /// listed to document the intent. "these" is left out on purpose:
    /// the French "thèse" (thesis) folds to it.
    static let stopWords: Set<String> = Set([
        // English
        "the", "a", "an", "to", "at", "of", "for", "in", "on", "with", "and", "or", "my",
        "get", "into", "make", "do", "from", "about", "this", "that", "those",
        "your", "our", "their", "some", "more", "less", "most", "much", "many", "very",
        "just", "also", "then", "than", "them", "they", "will", "have", "been", "were",
        "what", "when", "where", "which", "while", "would", "could", "should", "there",
        "here", "other", "after", "before", "over", "under", "again", "once", "only",
        "each", "every", "next", "last", "first", "start", "finish", "done", "take",
        "keep", "going", "goal", "plan", "need", "want", "better", "good", "great",
        "today", "tomorrow", "week", "month", "year", "daily", "weekly", "monthly",
        // French
        "de", "la", "le", "les", "des", "du", "un", "une", "à", "au", "aux", "pour",
        "avec", "et", "ou", "mon", "ma", "mes", "ton", "ta", "tes", "son", "sa", "ses",
        "notre", "votre", "leur", "leurs", "nos", "vos", "sur", "dans", "en", "par",
        "sans", "sous", "vers", "chez", "entre", "mais", "donc", "plus", "moins", "tout",
        "tous", "toute", "toutes", "cette", "ces", "faire", "être", "avoir", "aller",
        "aussi", "très", "bien", "jour", "jours", "semaine", "mois", "année", "demain",
        "aujourd'hui", "chaque", "objectif", "commencer", "finir", "terminer", "prendre",
        "quotidien", "quotidienne", "hebdomadaire", "mensuel", "avant", "après", "encore"
    ].flatMap(TitleText.words))
}
