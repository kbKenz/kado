import Foundation

public extension ReflectionRecord {
    var reflectionMonth: ReflectionMonth { ReflectionMonth(year: year, month: month) }

    /// The value view. When sync brings in two answers to one question,
    /// the later edit wins.
    var snapshot: ReflectionEntry {
        var answers: [String: ReflectionAnswer] = [:]
        for record in self.answers ?? [] {
            let answer = record.snapshot
            if let existing = answers[answer.questionID], existing.updatedAt > answer.updatedAt { continue }
            answers[answer.questionID] = answer
        }
        return ReflectionEntry(
            id: id, month: reflectionMonth, createdAt: createdAt, updatedAt: updatedAt,
            completedAt: completedAt, answers: answers
        )
    }
}

public extension ReflectionAnswerRecord {
    var snapshot: ReflectionAnswer {
        ReflectionAnswer(
            questionID: questionID, prompt: prompt, text: text, rating: rating,
            status: ReflectionFollowUpStatus(rawValue: statusRaw), updatedAt: updatedAt
        )
    }
}

public extension Array where Element == ReflectionRecord {
    /// One entry per month: when sync brings in two records for a
    /// month, their answers merge, the later edit winning.
    var mergedEntries: [ReflectionEntry] {
        var byMonth: [ReflectionMonth: ReflectionEntry] = [:]
        for record in self {
            let entry = record.snapshot
            guard var existing = byMonth[entry.month] else {
                byMonth[entry.month] = entry
                continue
            }
            for (id, answer) in entry.answers where (existing.answers[id]?.updatedAt ?? .distantPast) < answer.updatedAt {
                existing.answers[id] = answer
            }
            existing.completedAt = [existing.completedAt, entry.completedAt].compactMap { $0 }.min()
            existing.updatedAt = Swift.max(existing.updatedAt, entry.updatedAt)
            if entry.createdAt < existing.createdAt {
                existing.id = entry.id
                existing.createdAt = entry.createdAt
            }
            byMonth[entry.month] = existing
        }
        return byMonth.values.sorted { $0.month > $1.month }
    }
}
