import Foundation

/// A month's reflection with its answers, in the backup file.
public struct ReflectionBackup: Hashable, Codable, Sendable {
    public var id: UUID
    public var year: Int
    public var month: Int
    public var createdAt: Date
    public var updatedAt: Date
    public var completedAt: Date?
    public var answers: [ReflectionAnswerBackup]

    public init(id: UUID, year: Int, month: Int, createdAt: Date, updatedAt: Date,
                completedAt: Date?, answers: [ReflectionAnswerBackup]) {
        self.id = id
        self.year = year
        self.month = month
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.completedAt = completedAt
        self.answers = answers
    }
}

public struct ReflectionAnswerBackup: Hashable, Codable, Sendable {
    public var id: UUID
    public var questionID: String
    public var prompt: String
    public var text: String
    public var rating: Double?
    /// A `ReflectionFollowUpStatus` raw value, empty when there is none.
    public var status: String
    public var createdAt: Date
    public var updatedAt: Date

    public init(id: UUID, questionID: String, prompt: String, text: String, rating: Double?,
                status: String, createdAt: Date, updatedAt: Date) {
        self.id = id
        self.questionID = questionID
        self.prompt = prompt
        self.text = text
        self.rating = rating
        self.status = status
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
