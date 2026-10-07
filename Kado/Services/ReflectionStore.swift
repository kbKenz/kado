import Foundation
import SwiftData
import KadoCore

/// Every write to reflections. Views address a month by its value and
/// an answer by its question id; records are resolved here, at the
/// moment of the write.
@MainActor
struct ReflectionStore {
    let context: ModelContext
    var now: () -> Date = { .now }

    /// Every month's entry, newest first, duplicates from sync merged.
    func entries() throws -> [ReflectionEntry] {
        try context.fetch(FetchDescriptor<ReflectionRecord>()).mergedEntries
    }

    func entry(for month: ReflectionMonth) throws -> ReflectionEntry? {
        try records(for: month).mergedEntries.first
    }

    /// Writes one answer. An empty answer removes the stored one.
    func save(_ answer: ReflectionAnswer, for month: ReflectionMonth) throws {
        let now = now()
        let existing = try records(for: month)
            .flatMap { $0.answers ?? [] }
            .filter { $0.questionID == answer.questionID }
        if answer.isEmpty {
            guard !existing.isEmpty else { return }
            existing.forEach(context.delete)
            try touch(month, at: now)
            return
        }
        let record = try reflection(for: month, at: now)
        // Sync can bring in two copies of one answer: keep one.
        let target: ReflectionAnswerRecord
        if let first = existing.first {
            target = first
            existing.dropFirst().forEach(context.delete)
        } else {
            target = ReflectionAnswerRecord(questionID: answer.questionID, createdAt: now)
            context.insert(target)
            target.reflection = record
        }
        guard target.prompt != answer.prompt || target.text != answer.text || target.rating != answer.rating
                || target.statusRaw != (answer.status?.rawValue ?? "") else { return }
        target.prompt = answer.prompt
        target.text = answer.text
        target.rating = answer.rating
        target.statusRaw = answer.status?.rawValue ?? ""
        target.updatedAt = now
        record.updatedAt = now
        try commit()
    }

    /// Marks the month's check-in done; the first finish keeps its date.
    func complete(_ month: ReflectionMonth) throws {
        let now = now()
        let record = try reflection(for: month, at: now)
        if record.completedAt == nil { record.completedAt = now }
        record.updatedAt = now
        try commit()
    }

    /// Removes the month's reflection and every answer in it.
    func delete(_ month: ReflectionMonth) throws {
        try records(for: month).forEach(context.delete)
        try commit()
    }

    // MARK: - Private

    private func records(for month: ReflectionMonth) throws -> [ReflectionRecord] {
        let year = month.year
        let number = month.month
        return try context.fetch(FetchDescriptor<ReflectionRecord>(
            predicate: #Predicate { $0.year == year && $0.month == number },
            sortBy: [SortDescriptor(\.createdAt)]
        ))
    }

    /// The month's earliest record, created when there is none.
    private func reflection(for month: ReflectionMonth, at now: Date) throws -> ReflectionRecord {
        if let record = try records(for: month).first { return record }
        let record = ReflectionRecord(year: month.year, month: month.month, createdAt: now, updatedAt: now)
        context.insert(record)
        return record
    }

    private func touch(_ month: ReflectionMonth, at now: Date) throws {
        try records(for: month).first?.updatedAt = now
        try commit()
    }

    /// Saves, and undoes the pending changes when the save fails so the
    /// shared context is never left dirty.
    private func commit() throws {
        do {
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
    }
}
