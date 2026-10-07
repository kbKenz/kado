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
    /// For a follow-up, the quoted answer's month (`yyyy-MM`); empty otherwise.
    public var sourceMonth: String
    public var createdAt: Date
    public var updatedAt: Date

    public init(id: UUID, questionID: String, prompt: String, text: String, rating: Double?,
                status: String, sourceMonth: String = "", createdAt: Date, updatedAt: Date) {
        self.id = id
        self.questionID = questionID
        self.prompt = prompt
        self.text = text
        self.rating = rating
        self.status = status
        self.sourceMonth = sourceMonth
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    private enum CodingKeys: String, CodingKey {
        case id, questionID, prompt, text, rating, status, sourceMonth, createdAt, updatedAt
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        questionID = try values.decode(String.self, forKey: .questionID)
        prompt = try values.decodeIfPresent(String.self, forKey: .prompt) ?? ""
        text = try values.decodeIfPresent(String.self, forKey: .text) ?? ""
        rating = try values.decodeIfPresent(Double.self, forKey: .rating)
        status = try values.decodeIfPresent(String.self, forKey: .status) ?? ""
        sourceMonth = try values.decodeIfPresent(String.self, forKey: .sourceMonth) ?? ""
        createdAt = try values.decode(Date.self, forKey: .createdAt)
        updatedAt = try values.decode(Date.self, forKey: .updatedAt)
    }
}
