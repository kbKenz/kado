import Foundation
import SwiftData
import KadoCore

/// Four months of reflections ending last month, for previews of the
/// Reflect screens. Stored `static let`s: the ids must stay put.
@MainActor
enum ReflectionPreviewData {
    static let entries: [ReflectionEntry] = {
        let calendar = Calendar.current
        let last = ReflectionMonth(containing: .now, calendar: calendar).previous
        let months = (0..<4).map { last.adding(months: -$0) }
        let words = ["Steady", "Restless", "Hopeful", "Lost"]
        let problems = [
            "Not enough sleep before the IELTS mock tests.",
            "I keep postponing the professor emails.",
            "Money is tight and I worry about rent.",
            "I don't know what I want to study.",
        ]
        let dreams = [
            "Study in Cambridge and build something of my own.",
            "Get a 7.5 in IELTS and move abroad.",
            "Feel calm about the future.",
            "Find work that matters to me.",
        ]
        return months.enumerated().map { index, month in
            var answers: [String: ReflectionAnswer] = [:]
            func add(_ id: String, text: String = "", rating: Double? = nil, status: ReflectionFollowUpStatus? = nil) {
                let prompt = ReflectionCatalog.question(id: id)?.prompt ?? ""
                answers[id] = ReflectionAnswer(questionID: id, prompt: prompt, text: text, rating: rating, status: status, updatedAt: .now)
            }
            add(ReflectionCatalog.overallID, rating: Double([7, 5, 6, 3][index]))
            add("rating.energy", rating: Double([6, 4, 6, 4][index]))
            add("rating.work", rating: Double([8, 6, 5, 3][index]))
            add("rating.relationships", rating: Double([7, 7, 8, 6][index]))
            add("rating.peace", rating: Double([6, 4, 5, 2][index]))
            add(ReflectionCatalog.wordID, text: words[index])
            add(ReflectionCatalog.problemID, text: problems[index])
            add("core.dreams", text: dreams[index])
            add("core.proud", text: index == 0 ? "I studied 4 hours a day for three weeks." : "I kept going.")
            add(ReflectionCatalog.intentionID, text: index == 0 ? "Sleep before midnight." : "Send two emails a week.")
            if index < 3 {
                add(ReflectionCatalog.followUpProblemID, status: [.better, .same, .worse][index])
            }
            return ReflectionEntry(month: month, createdAt: .now, updatedAt: .now, completedAt: .now, answers: answers)
        }
    }()

    static let container: ModelContainer = {
        do {
            let container = try ModelContainer(
                for: HabitRecord.self, CompletionRecord.self, TaskRecord.self, ScheduleBlockRecord.self, GoalRecord.self,
                ReflectionRecord.self, ReflectionAnswerRecord.self,
                configurations: ModelConfiguration(isStoredInMemoryOnly: true)
            )
            insert(entries, into: container.mainContext)
            return container
        } catch {
            fatalError("Failed to construct reflection preview container: \(error)")
        }
    }()

    static func insert(_ entries: [ReflectionEntry], into context: ModelContext) {
        for entry in entries {
            let record = ReflectionRecord(
                year: entry.month.year, month: entry.month.month,
                createdAt: entry.createdAt, updatedAt: entry.updatedAt, completedAt: entry.completedAt
            )
            context.insert(record)
            for answer in entry.answers.values {
                let answerRecord = ReflectionAnswerRecord(
                    questionID: answer.questionID, prompt: answer.prompt, text: answer.text,
                    rating: answer.rating, statusRaw: answer.status?.rawValue ?? ""
                )
                context.insert(answerRecord)
                answerRecord.reflection = record
            }
        }
        try? context.save()
    }
}
