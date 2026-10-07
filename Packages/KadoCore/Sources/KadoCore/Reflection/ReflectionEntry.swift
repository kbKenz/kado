import Foundation

/// One answer, as a value.
nonisolated public struct ReflectionAnswer: Hashable, Sendable {
    public var questionID: String
    /// The words as asked; for a follow-up, with the quoted earlier answer.
    public var prompt: String
    public var text: String
    public var rating: Double?
    public var status: ReflectionFollowUpStatus?
    /// For a follow-up, the month of the answer it quoted.
    public var sourceMonth: ReflectionMonth?
    public var updatedAt: Date

    public init(questionID: String, prompt: String = "", text: String = "", rating: Double? = nil,
                status: ReflectionFollowUpStatus? = nil, sourceMonth: ReflectionMonth? = nil,
                updatedAt: Date = .distantPast) {
        self.questionID = questionID
        self.prompt = prompt
        self.text = text
        self.rating = rating
        self.status = status
        self.sourceMonth = sourceMonth
        self.updatedAt = updatedAt
    }

    public var trimmedText: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// Nothing written, rated or chosen.
    public var isEmpty: Bool { trimmedText.isEmpty && rating == nil && status == nil }
}

/// A month's reflection, as a value. Views and the archive work on
/// these and never hold a record.
nonisolated public struct ReflectionEntry: Hashable, Identifiable, Sendable {
    public var id: UUID
    public var month: ReflectionMonth
    public var createdAt: Date
    public var updatedAt: Date
    public var completedAt: Date?
    /// By question id; empty answers are left out.
    public var answers: [String: ReflectionAnswer]

    public init(id: UUID = UUID(), month: ReflectionMonth, createdAt: Date = .distantPast, updatedAt: Date = .distantPast,
                completedAt: Date? = nil, answers: [String: ReflectionAnswer] = [:]) {
        self.id = id
        self.month = month
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.completedAt = completedAt
        self.answers = answers.filter { !$0.value.isEmpty }
    }

    public var isComplete: Bool { completedAt != nil }

    public func answer(_ questionID: String) -> ReflectionAnswer? { answers[questionID] }

    public func text(_ questionID: String) -> String? {
        guard let text = answers[questionID]?.trimmedText, !text.isEmpty else { return nil }
        return text
    }

    public var word: String? { text(ReflectionCatalog.wordID) }
    public var overall: Double? { answers[ReflectionCatalog.overallID]?.rating }
}

/// A screen of the check-in.
nonisolated public enum ReflectionStep: Hashable, Identifiable, Sendable {
    /// The month in numbers from Kado, and what was written a year ago.
    case intro
    /// All rating questions on one screen.
    case ratings([ReflectionQuestion])
    /// A follow-up on an earlier answer, quoted, from `sourceMonth`.
    case followUp(ReflectionQuestion, quoted: String, sourceMonth: ReflectionMonth, options: [ReflectionFollowUpStatus])
    case question(ReflectionQuestion)
    case finish

    public var id: String {
        switch self {
        case .intro: "intro"
        case .ratings: "ratings"
        case .followUp(let question, _, _, _): question.id
        case .question(let question): question.id
        case .finish: "finish"
        }
    }
}
