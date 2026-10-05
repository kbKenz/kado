import Foundation

/// A goal the matcher can pick: its identity and its name.
nonisolated public struct GoalCandidate: Hashable, Sendable {
    public var id: UUID
    public var name: String

    public init(id: UUID, name: String) {
        self.id = id
        self.name = name
    }
}

/// Picks the goal a new task or habit most likely serves, from the
/// words its title shares with each goal's name. Pure and on device.
///
/// Both texts are folded and split into words like in
/// `CategoryClassifier`. Common English and French words and words of
/// fewer than 4 letters are dropped. Two words are shared when they are
/// equal, or when one is the other plus "s" or "es". A goal scores one
/// point per title word it shares.
nonisolated public enum GoalMatcher {
    /// The goal with the most shared words, when it shares at least one
    /// and no other goal has as many. `nil` otherwise.
    public static func bestGoal(for title: String, among goals: [GoalCandidate]) -> UUID? {
        let titleWords = Set(significantWords(title))
        guard !titleWords.isEmpty else { return nil }
        var best: UUID?
        var bestScore = 0
        var isTied = false
        for goal in goals {
            let goalWords = significantWords(goal.name)
            let score = titleWords.filter { word in goalWords.contains { sameWord(word, $0) } }.count
            if score > bestScore {
                best = goal.id
                bestScore = score
                isTied = false
            } else if score == bestScore, score > 0 {
                isTied = true
            }
        }
        return isTied ? nil : best
    }

    /// The folded words of `text` that can link a title to a goal.
    static func significantWords(_ text: String) -> [String] {
        TitleText.words(text).filter { $0.count >= 4 && !stopWords.contains($0) }
    }

    /// Whether two folded words are the same, allowing a plural "s" or
    /// "es" on either side.
    static func sameWord(_ lhs: String, _ rhs: String) -> Bool {
        lhs == rhs
            || TitleText.singularForms(of: lhs).contains(rhs)
            || TitleText.singularForms(of: rhs).contains(lhs)
    }

    /// Words too common to link a title to a goal, folded. Words of
    /// fewer than 4 letters are dropped anyway; the short ones are
    /// listed to document the intent.
    static let stopWords: Set<String> = Set([
        // English
        "the", "a", "an", "to", "at", "of", "for", "in", "on", "with", "and", "or", "my",
        "get", "into", "make", "do", "from", "about", "this", "that", "these", "those",
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
