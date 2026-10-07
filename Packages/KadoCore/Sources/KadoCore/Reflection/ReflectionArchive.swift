import Foundation

/// Reading the reflections back: one question across the months, the
/// ratings as series, search, and the month a year ago. Pure.
nonisolated public enum ReflectionArchive {
    /// One month's answer to a question.
    public struct Item: Hashable, Identifiable, Sendable {
        public var month: ReflectionMonth
        public var answer: ReflectionAnswer
        /// For the biggest problem or the intention: what the next
        /// follow-up said about it, and in which month.
        public var outcome: ReflectionFollowUpStatus?
        public var outcomeMonth: ReflectionMonth?

        public var id: Int { month.id }
    }

    /// Every non-empty answer to `questionID`, newest month first.
    public static func history(of questionID: String, in entries: [ReflectionEntry]) -> [Item] {
        let followUpID: String? = switch questionID {
        case ReflectionCatalog.problemID: ReflectionCatalog.followUpProblemID
        case ReflectionCatalog.intentionID: ReflectionCatalog.followUpIntentionID
        default: nil
        }
        let sorted = entries.sorted { $0.month > $1.month }
        return sorted.compactMap { entry -> Item? in
            guard let answer = entry.answer(questionID), !answer.isEmpty else { return nil }
            var item = Item(month: entry.month, answer: answer)
            if let followUpID, let later = outcome(of: questionID, from: entry.month, followUpID: followUpID, in: entries) {
                item.outcome = later.status
                item.outcomeMonth = later.month
            }
            return item
        }
    }

    /// The follow-up that quoted the answer of `month`: the first later
    /// follow-up that names `month` as its source. A follow-up saved
    /// without a source counts when it is the first after `month` and no
    /// answer in between replaced the quoted one.
    private static func outcome(
        of questionID: String, from month: ReflectionMonth, followUpID: String, in entries: [ReflectionEntry]
    ) -> (month: ReflectionMonth, status: ReflectionFollowUpStatus)? {
        let later = entries.filter { $0.month > month }.sorted { $0.month < $1.month }
        for entry in later {
            if let followUp = entry.answer(followUpID), let status = followUp.status, followUp.sourceMonth == month {
                return (entry.month, status)
            }
        }
        for entry in later {
            if let followUp = entry.answer(followUpID), let status = followUp.status, followUp.sourceMonth == nil {
                guard ReflectionPlanner.latest(questionID, before: entry.month, in: entries)?.month == month else { return nil }
                return (entry.month, status)
            }
            if entry.text(questionID) != nil { return nil }
        }
        return nil
    }

    /// A rating over the months, oldest first.
    public static func series(of questionID: String, in entries: [ReflectionEntry]) -> [(month: ReflectionMonth, value: Double)] {
        entries
            .compactMap { entry in entry.answer(questionID)?.rating.map { (entry.month, $0) } }
            .sorted { $0.0 < $1.0 }
    }

    /// The same calendar month a year before, when it has answers.
    public static func yearAgo(of month: ReflectionMonth, in entries: [ReflectionEntry]) -> ReflectionEntry? {
        let target = month.adding(months: -12)
        return entries.first { $0.month == target && !$0.answers.isEmpty }
    }

    /// One match of a search.
    public struct Hit: Hashable, Identifiable, Sendable {
        public var month: ReflectionMonth
        public var questionID: String
        public var prompt: String
        public var text: String

        public var id: String { "\(month.id)-\(questionID)" }
    }

    /// Answers whose text contains `query`, ignoring case and accents,
    /// newest month first and in question order within a month.
    public static func search(_ query: String, in entries: [ReflectionEntry]) -> [Hit] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return [] }
        let order = Dictionary(ReflectionCatalog.all.enumerated().map { ($1.id, $0) }, uniquingKeysWith: { first, _ in first })
        return entries.sorted { $0.month > $1.month }.flatMap { entry in
            entry.answers.values
                .filter { $0.text.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
                .sorted { (order[$0.questionID] ?? .max, $0.questionID) < (order[$1.questionID] ?? .max, $1.questionID) }
                .map { Hit(month: entry.month, questionID: $0.questionID, prompt: $0.prompt, text: $0.text) }
        }
    }
}
