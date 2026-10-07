import Foundation

/// How a reflection question is answered.
nonisolated public enum ReflectionQuestionKind: Hashable, Sendable {
    /// A 1 to 10 scale, charted over the months.
    case rating
    /// Free text.
    case text
    /// A choice about an earlier answer, with an optional note.
    case followUp
}

/// One question of the monthly check-in. `id` is stable forever: it is
/// what makes October's answer comparable with March's, so a question
/// is reworded in place and never renumbered.
nonisolated public struct ReflectionQuestion: Hashable, Identifiable, Sendable {
    public let id: String
    public let kind: ReflectionQuestionKind
    public let prompt: String
    /// A short label for lists and charts ("Biggest problem").
    public let title: String
    /// Placeholder text under the prompt.
    public let hint: String

    public init(id: String, kind: ReflectionQuestionKind, prompt: String, title: String, hint: String = "") {
        self.id = id
        self.kind = kind
        self.prompt = prompt
        self.title = title
        self.hint = hint
    }
}

/// What a follow-up answer says about an earlier problem or intention.
nonisolated public enum ReflectionFollowUpStatus: String, CaseIterable, Hashable, Codable, Sendable {
    case solved, better, same, worse
    case done, partly, notDone

    public static let problemOptions: [ReflectionFollowUpStatus] = [.solved, .better, .same, .worse]
    public static let intentionOptions: [ReflectionFollowUpStatus] = [.done, .partly, .notDone]

    public var title: String {
        switch self {
        case .solved: String(localized: "Solved", comment: "Reflection follow-up: last month's problem is solved.")
        case .better: String(localized: "Better", comment: "Reflection follow-up: last month's problem got better.")
        case .same: String(localized: "Same", comment: "Reflection follow-up: last month's problem is the same.")
        case .worse: String(localized: "Worse", comment: "Reflection follow-up: last month's problem got worse.")
        case .done: String(localized: "Did it", comment: "Reflection follow-up: last month's intention was done.")
        case .partly: String(localized: "Partly", comment: "Reflection follow-up: last month's intention was partly done.")
        case .notDone: String(localized: "Didn't", comment: "Reflection follow-up: last month's intention was not done.")
        }
    }

    public var symbol: String {
        switch self {
        case .solved, .done: "checkmark.circle.fill"
        case .better, .partly: "arrow.up.right.circle.fill"
        case .same: "equal.circle.fill"
        case .worse, .notDone: "arrow.down.right.circle.fill"
        }
    }
}

/// Every question the check-in asks, in order. The ratings and core
/// questions are the same every month so months compare; one deep
/// question rotates with the calendar month, so it comes back each
/// year and compares across years.
nonisolated public enum ReflectionCatalog {
    public static let followUpProblemID = "followup.problem"
    public static let followUpIntentionID = "followup.intention"
    public static let wordID = "core.word"
    public static let problemID = "core.problem"
    public static let intentionID = "core.intention"
    public static let overallID = "rating.overall"

    public static var ratings: [ReflectionQuestion] {
        [
            ReflectionQuestion(
                id: overallID, kind: .rating,
                prompt: String(localized: "Overall, how was this month?", comment: "Reflection rating question."),
                title: String(localized: "Overall", comment: "Reflection rating label.")
            ),
            ReflectionQuestion(
                id: "rating.energy", kind: .rating,
                prompt: String(localized: "Energy and health", comment: "Reflection rating question."),
                title: String(localized: "Energy", comment: "Reflection rating label.")
            ),
            ReflectionQuestion(
                id: "rating.work", kind: .rating,
                prompt: String(localized: "Work or study", comment: "Reflection rating question."),
                title: String(localized: "Work", comment: "Reflection rating label.")
            ),
            ReflectionQuestion(
                id: "rating.relationships", kind: .rating,
                prompt: String(localized: "Relationships", comment: "Reflection rating question and label."),
                title: String(localized: "Relationships", comment: "Reflection rating question and label.")
            ),
            ReflectionQuestion(
                id: "rating.peace", kind: .rating,
                prompt: String(localized: "Peace of mind", comment: "Reflection rating question."),
                title: String(localized: "Peace", comment: "Reflection rating label.")
            ),
        ]
    }

    public static var core: [ReflectionQuestion] {
        [
            ReflectionQuestion(
                id: wordID, kind: .text,
                prompt: String(localized: "Describe this month in one word.", comment: "Reflection question."),
                title: String(localized: "Word of the month", comment: "Reflection question label."),
                hint: String(localized: "One word", comment: "Reflection answer placeholder.")
            ),
            ReflectionQuestion(
                id: problemID, kind: .text,
                prompt: String(localized: "What is my biggest problem right now?", comment: "Reflection question."),
                title: String(localized: "Biggest problem", comment: "Reflection question label.")
            ),
            ReflectionQuestion(
                id: "core.thoughts", kind: .text,
                prompt: String(localized: "What do I think about most these days?", comment: "Reflection question."),
                title: String(localized: "On my mind", comment: "Reflection question label.")
            ),
            ReflectionQuestion(
                id: "core.fears", kind: .text,
                prompt: String(localized: "What am I afraid of or worried about?", comment: "Reflection question."),
                title: String(localized: "Fears and worries", comment: "Reflection question label.")
            ),
            ReflectionQuestion(
                id: "core.dreams", kind: .text,
                prompt: String(localized: "What do I dream about or want most?", comment: "Reflection question."),
                title: String(localized: "Dreams", comment: "Reflection question label.")
            ),
            ReflectionQuestion(
                id: "core.feelings", kind: .text,
                prompt: String(localized: "How do I feel, honestly?", comment: "Reflection question."),
                title: String(localized: "How I feel", comment: "Reflection question label.")
            ),
            ReflectionQuestion(
                id: "core.proud", kind: .text,
                prompt: String(localized: "What am I proud of this month?", comment: "Reflection question."),
                title: String(localized: "Proud of", comment: "Reflection question label.")
            ),
            ReflectionQuestion(
                id: "core.avoided", kind: .text,
                prompt: String(localized: "What did I avoid or keep postponing?", comment: "Reflection question."),
                title: String(localized: "Avoided", comment: "Reflection question label.")
            ),
            ReflectionQuestion(
                id: "core.learned", kind: .text,
                prompt: String(localized: "What did I learn or change my mind about?", comment: "Reflection question."),
                title: String(localized: "Learned", comment: "Reflection question label.")
            ),
            ReflectionQuestion(
                id: "core.people", kind: .text,
                prompt: String(localized: "Who mattered most this month?", comment: "Reflection question."),
                title: String(localized: "People", comment: "Reflection question label.")
            ),
            ReflectionQuestion(
                id: intentionID, kind: .text,
                prompt: String(localized: "One intention for next month.", comment: "Reflection question."),
                title: String(localized: "Intention", comment: "Reflection question label.")
            ),
        ]
    }

    /// Twelve deep questions, one per calendar month: January asks the
    /// first every year.
    public static var deep: [ReflectionQuestion] {
        let prompts: [(String, String)] = [
            (String(localized: "Who do I want to become in five years?", comment: "Reflection deep question."),
             String(localized: "Who I want to become", comment: "Reflection deep question label.")),
            (String(localized: "What gives me energy, and what drains it?", comment: "Reflection deep question."),
             String(localized: "Energy and drain", comment: "Reflection deep question label.")),
            (String(localized: "What belief about myself holds me back?", comment: "Reflection deep question."),
             String(localized: "Limiting belief", comment: "Reflection deep question label.")),
            (String(localized: "What would I do if I knew I could not fail?", comment: "Reflection deep question."),
             String(localized: "If I could not fail", comment: "Reflection deep question label.")),
            (String(localized: "What am I putting up with that I should not?", comment: "Reflection deep question."),
             String(localized: "Putting up with", comment: "Reflection deep question label.")),
            (String(localized: "What does a perfect ordinary day look like?", comment: "Reflection deep question."),
             String(localized: "Perfect ordinary day", comment: "Reflection deep question label.")),
            (String(localized: "What would I do with one free year?", comment: "Reflection deep question."),
             String(localized: "One free year", comment: "Reflection deep question label.")),
            (String(localized: "What am I pretending not to know?", comment: "Reflection deep question."),
             String(localized: "Pretending not to know", comment: "Reflection deep question label.")),
            (String(localized: "Which relationship needs my attention?", comment: "Reflection deep question."),
             String(localized: "Relationship to tend", comment: "Reflection deep question label.")),
            (String(localized: "What would I stop doing if nobody judged me?", comment: "Reflection deep question."),
             String(localized: "Without judgment", comment: "Reflection deep question label.")),
            (String(localized: "What would 80-year-old me tell me now?", comment: "Reflection deep question."),
             String(localized: "Advice from 80-year-old me", comment: "Reflection deep question label.")),
            (String(localized: "What made me truly happy this year?", comment: "Reflection deep question."),
             String(localized: "Truly happy", comment: "Reflection deep question label.")),
        ]
        return prompts.enumerated().map { index, pair in
            ReflectionQuestion(id: String(format: "deep.%02d", index + 1), kind: .text, prompt: pair.0, title: pair.1)
        }
    }

    public static func deepQuestion(for month: ReflectionMonth) -> ReflectionQuestion {
        deep[(month.month - 1) % deep.count]
    }

    public static var followUps: [ReflectionQuestion] {
        [
            ReflectionQuestion(
                id: followUpProblemID, kind: .followUp,
                prompt: String(localized: "That problem is now…", comment: "Reflection follow-up about last month's biggest problem."),
                title: String(localized: "Problem follow-up", comment: "Reflection question label.")
            ),
            ReflectionQuestion(
                id: followUpIntentionID, kind: .followUp,
                prompt: String(localized: "Did you do it?", comment: "Reflection follow-up about last month's intention."),
                title: String(localized: "Intention follow-up", comment: "Reflection question label.")
            ),
        ]
    }

    /// Every question, for lookups and the per-question archive.
    public static var all: [ReflectionQuestion] { ratings + core + deep + followUps }

    public static func question(id: String) -> ReflectionQuestion? {
        all.first { $0.id == id }
    }
}
