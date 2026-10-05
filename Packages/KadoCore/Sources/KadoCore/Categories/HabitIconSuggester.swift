import Foundation

/// Suggests a starting icon for a new habit from its title. Pure and on
/// device; every icon it returns is in `HabitIcon.curated`.
///
/// Titles are folded and split into whole words like in
/// `CategoryClassifier`, with the same plural rule. When several rules
/// match, the first one in `rules` wins: specific activities come
/// before generic verbs, so "Drink coffee" gets the cup, not the drop.
nonisolated public enum HabitIconSuggester {
    /// The icon for `title`: a keyword match first, else the category's
    /// default habit icon, else `nil`.
    public static func icon(for title: String, category: ItemCategory?) -> String? {
        let words = TitleWords(title, exactWords: vocabulary)
        let accentedWords = Set(title.lowercased().split(whereSeparator: { !$0.isLetter }).map(String.init))
        let match = rules.first { rule in
            !words.positions(matching: rule.words).isEmpty || !rule.accentedWords.isDisjoint(with: accentedWords)
        }
        return match?.icon ?? category?.defaultHabitIcon
    }

    /// One icon and the English and French words that suggest it.
    struct Rule: Sendable {
        let icon: String
        /// The folded keywords.
        let words: Set<String>
        /// Keywords matched with their accents, before folding.
        let accentedWords: Set<String>

        init(_ icon: String, _ keywords: [String]) {
            self.icon = icon
            words = Set(keywords.filter { !accentSensitive.contains($0) }.map(TitleText.fold))
            accentedWords = Set(keywords.filter { accentSensitive.contains($0) })
        }
    }

    /// "thé" folds to "the", the English article, so it matches only
    /// when typed with its accent.
    static let accentSensitive: Set<String> = ["thé"]

    /// In priority order: the first rule with a matching word wins.
    static let rules: [Rule] = [
        Rule("book.fill", ["read", "reading", "book", "lire", "lecture", "livre"]),
        Rule("figure.mind.and.body", [
            "meditate", "meditation", "breathe", "breathing", "méditer", "respirer", "respiration"
        ]),
        Rule("figure.yoga", ["yoga", "pilates", "stretch", "stretching", "étirement"]),
        Rule("figure.pool.swim", ["swim", "swimming", "pool", "nager", "natation", "piscine"]),
        Rule("bicycle", ["bike", "biking", "cycle", "cycling", "vélo"]),
        Rule("figure.run", ["run", "running", "jog", "jogging", "courir", "footing"]),
        Rule("figure.walk", ["walk", "walking", "marche", "marcher", "promenade", "balade"]),
        Rule("dumbbell.fill", ["gym", "lift", "lifting", "weights", "workout", "muscu", "musculation"]),
        Rule("music.note", [
            "music", "guitar", "piano", "violin", "sing", "musique", "guitare", "violon", "chanter"
        ]),
        Rule("paintbrush.fill", [
            "draw", "drawing", "paint", "painting", "dessiner", "dessin", "peindre", "peinture"
        ]),
        Rule("camera.fill", ["photo", "photography", "photographie"]),
        Rule("pencil", ["write", "writing", "journal", "journaling", "écrire", "écriture"]),
        Rule("laptopcomputer", ["code", "coding", "laptop", "computer", "ordinateur"]),
        Rule("pills.fill", ["pill", "vitamin", "medicine", "medication", "médicament", "vitamine", "pilule"]),
        Rule("cup.and.saucer.fill", ["coffee", "tea", "café", "thé", "tisane"]),
        Rule("carrot.fill", ["vegetable", "veggie", "fruit", "légume"]),
        Rule("fork.knife", [
            "cook", "cooking", "eat", "meal", "breakfast", "lunch", "dinner",
            "manger", "cuisiner", "repas", "dîner", "déjeuner"
        ]),
        Rule("drop.fill", ["water", "drink", "hydrate", "eau", "boire", "hydrater"]),
        Rule("bed.double.fill", ["sleep", "bed", "bedtime", "nap", "dormir", "coucher", "sieste", "sommeil"]),
        Rule("phone.fill", ["call", "phone", "appeler", "téléphone"]),
        Rule("house.fill", ["clean", "cleaning", "tidy", "ménage", "ranger", "nettoyer"])
    ]

    /// Every folded keyword. A title word in this set matches only as
    /// written (see `TitleWords`).
    static let vocabulary: Set<String> = rules.reduce(into: []) { $0.formUnion($1.words) }
}
