import Foundation
import UserNotifications
import Testing
@testable import Kado
import KadoCore

@Suite("ReflectionMonth")
struct ReflectionMonthTests {
    private let calendar = TestCalendar.utc

    @Test("Months normalize across year edges")
    func normalizes() {
        #expect(ReflectionMonth(year: 2026, month: 13) == ReflectionMonth(year: 2027, month: 1))
        #expect(ReflectionMonth(year: 2026, month: 0) == ReflectionMonth(year: 2025, month: 12))
        #expect(ReflectionMonth(year: 2026, month: 1).previous == ReflectionMonth(year: 2025, month: 12))
        #expect(ReflectionMonth(year: 2026, month: 12).next == ReflectionMonth(year: 2027, month: 1))
        #expect(ReflectionMonth(year: 2026, month: 3).adding(months: -27) == ReflectionMonth(year: 2023, month: 12))
    }

    @Test("Order follows the calendar")
    func order() {
        #expect(ReflectionMonth(year: 2025, month: 12) < ReflectionMonth(year: 2026, month: 1))
        #expect(ReflectionMonth(year: 2026, month: 2) < ReflectionMonth(year: 2026, month: 10))
    }

    @Test("First and last day are real day starts, also where midnight is skipped")
    func dayEdges() {
        let march = ReflectionMonth(year: 2026, month: 3)
        #expect(march.firstDay(in: calendar) == TestCalendar.instant(calendar, 2026, 3, 1))
        #expect(march.lastDay(in: calendar) == TestCalendar.instant(calendar, 2026, 3, 31))
        #expect(ReflectionMonth(year: 2028, month: 2).lastDay(in: calendar) == TestCalendar.instant(calendar, 2028, 2, 29))
        // Havana skips 00:00 on 2026-03-08; the month still starts and ends on day starts.
        let havana = TestCalendar.havana
        let interval = march.interval(in: havana)
        #expect(havana.component(.day, from: interval.start) == 1)
        #expect(havana.component(.month, from: interval.end) == 4)
        #expect(havana.component(.day, from: march.lastDay(in: havana)) == 31)
    }

    @Test("A date maps to its month in the calendar's zone")
    func containing() {
        let instant = TestCalendar.instant(calendar, 2026, 10, 31, 23, 30)
        #expect(ReflectionMonth(containing: instant, calendar: calendar) == ReflectionMonth(year: 2026, month: 10))
        #expect(ReflectionMonth(year: 2026, month: 10).contains(instant, calendar: calendar))
    }
}

@Suite("ReflectionPlanner")
struct ReflectionPlannerTests {
    private let calendar = TestCalendar.utc
    private var planner: ReflectionPlanner { ReflectionPlanner(calendar: calendar) }
    private let october = ReflectionMonth(year: 2026, month: 10)

    private func entry(_ month: ReflectionMonth, complete: Bool = true, _ answers: [String: String] = [:]) -> ReflectionEntry {
        ReflectionEntry(
            month: month, completedAt: complete ? .distantPast : nil,
            answers: answers.mapValues { ReflectionAnswer(questionID: "", text: $0) }
                .reduce(into: [:]) { result, pair in
                    var answer = pair.value
                    answer.questionID = pair.key
                    result[pair.key] = answer
                }
        )
    }

    @Test("Mid-month the check-in is for the current month and not due")
    func midMonth() {
        let now = TestCalendar.instant(calendar, 2026, 10, 15, 12)
        #expect(planner.checkInMonth(now: now, entries: []) == october)
        #expect(!planner.isDue(now: now, entries: []))
    }

    @Test("The last three days of the month open the check-in")
    func endOfMonth() {
        #expect(!planner.isDue(now: TestCalendar.instant(calendar, 2026, 10, 28, 23), entries: []))
        #expect(planner.isDue(now: TestCalendar.instant(calendar, 2026, 10, 29, 9), entries: []))
        #expect(planner.isDue(now: TestCalendar.instant(calendar, 2026, 10, 31, 22), entries: []))
        #expect(!planner.isDue(now: TestCalendar.instant(calendar, 2026, 10, 31, 22), entries: [entry(october)]))
    }

    @Test("In the first week the open month before is offered until done")
    func graceDays() {
        let now = TestCalendar.instant(calendar, 2026, 11, 3, 9)
        #expect(planner.checkInMonth(now: now, entries: []) == october)
        #expect(planner.isDue(now: now, entries: [entry(october, complete: false)]))
        #expect(planner.checkInMonth(now: now, entries: [entry(october)]) == october.next)
        #expect(!planner.isDue(now: now, entries: [entry(october)]))
        let later = TestCalendar.instant(calendar, 2026, 11, 8, 9)
        #expect(planner.checkInMonth(now: later, entries: []) == october.next)
    }

    @Test("Steps: intro, ratings, core questions, the month's deep question, finish")
    func stepsWithoutHistory() {
        let steps = planner.steps(for: october, entries: [])
        #expect(steps.first == .intro)
        #expect(steps[1] == .ratings(ReflectionCatalog.ratings))
        #expect(steps.last == .finish)
        let questions = steps.compactMap { step -> String? in
            if case .question(let question) = step { return question.id }
            return nil
        }
        #expect(questions == ReflectionCatalog.core.map(\.id) + ["deep.10"])
        #expect(!steps.contains { if case .followUp = $0 { true } else { false } })
    }

    @Test("Follow-ups quote the latest earlier problem and intention, even across a skipped month")
    func followUps() {
        let july = entry(ReflectionMonth(year: 2026, month: 7), [ReflectionCatalog.problemID: "Sleep"])
        let august = entry(ReflectionMonth(year: 2026, month: 8), [
            ReflectionCatalog.problemID: "  Money  ", ReflectionCatalog.intentionID: "Run twice a week",
        ])
        let steps = planner.steps(for: october, entries: [july, august])
        let followUps = steps.compactMap { step -> (String, String, ReflectionMonth)? in
            if case .followUp(let question, let quoted, let month, _) = step { return (question.id, quoted, month) }
            return nil
        }
        #expect(followUps.map(\.0) == [ReflectionCatalog.followUpProblemID, ReflectionCatalog.followUpIntentionID])
        #expect(followUps.map(\.1) == ["Money", "Run twice a week"])
        #expect(followUps.allSatisfy { $0.2 == ReflectionMonth(year: 2026, month: 8) })
    }

    @Test("Each calendar month asks its own deep question, the same every year")
    func deepRotation() {
        let deep = (1...12).map { ReflectionCatalog.deepQuestion(for: ReflectionMonth(year: 2026, month: $0)).id }
        #expect(Set(deep).count == 12)
        #expect(ReflectionCatalog.deepQuestion(for: ReflectionMonth(year: 2027, month: 4)).id == deep[3])
    }

    @Test("Question ids are unique")
    func uniqueIDs() {
        let ids = ReflectionCatalog.all.map(\.id)
        #expect(Set(ids).count == ids.count)
    }
}

@Suite("ReflectionArchive")
struct ReflectionArchiveTests {
    private func month(_ number: Int, year: Int = 2026) -> ReflectionMonth { ReflectionMonth(year: year, month: number) }

    private func entry(_ month: ReflectionMonth, _ answers: [ReflectionAnswer]) -> ReflectionEntry {
        ReflectionEntry(month: month, completedAt: .distantPast,
                        answers: Dictionary(answers.map { ($0.questionID, $0) }, uniquingKeysWith: { first, _ in first }))
    }

    private func text(_ id: String, _ text: String) -> ReflectionAnswer { ReflectionAnswer(questionID: id, text: text) }
    private func status(_ id: String, _ status: ReflectionFollowUpStatus) -> ReflectionAnswer {
        ReflectionAnswer(questionID: id, status: status)
    }

    @Test("A question's history is newest first and skips empty answers")
    func history() {
        let entries = [
            entry(month(7), [text(ReflectionCatalog.wordID, "Tired")]),
            entry(month(8), [text(ReflectionCatalog.wordID, "   ")]),
            entry(month(9), [text(ReflectionCatalog.wordID, "Calm")]),
        ]
        let items = ReflectionArchive.history(of: ReflectionCatalog.wordID, in: entries)
        #expect(items.map(\.month) == [month(9), month(7)])
        #expect(items.map(\.answer.text) == ["Calm", "Tired"])
    }

    @Test("A problem shows what the next follow-up said about it")
    func problemOutcome() {
        let problem = ReflectionCatalog.problemID
        let followUp = ReflectionCatalog.followUpProblemID
        let entries = [
            entry(month(7), [text(problem, "Sleep")]),
            // August answers the follow-up about July and names a new problem.
            entry(month(8), [status(followUp, .better), text(problem, "Money")]),
            // September has no follow-up; October's is about August's problem.
            entry(month(9), []),
            entry(month(10), [status(followUp, .solved)]),
        ]
        let items = ReflectionArchive.history(of: problem, in: entries)
        #expect(items.map(\.answer.text) == ["Money", "Sleep"])
        #expect(items.map(\.outcome) == [.solved, .better])
        #expect(items.map(\.outcomeMonth) == [month(10), month(8)])
    }

    @Test("A stored source keeps the outcome on the quoted month when an older month is filled in later")
    func storedSource() {
        let problem = ReflectionCatalog.problemID
        var followUp = status(ReflectionCatalog.followUpProblemID, .solved)
        followUp.sourceMonth = month(8)
        let entries = [
            entry(month(8), [text(problem, "Money")]),
            // September's problem was written after October's follow-up.
            entry(month(9), [text(problem, "Sleep")]),
            entry(month(10), [followUp]),
        ]
        let items = ReflectionArchive.history(of: problem, in: entries)
        #expect(items.map(\.answer.text) == ["Sleep", "Money"])
        #expect(items.map(\.outcome) == [nil, .solved])
    }

    @Test("Ratings form a series, oldest first")
    func series() {
        let entries = [
            entry(month(9), [ReflectionAnswer(questionID: ReflectionCatalog.overallID, rating: 7)]),
            entry(month(7), [ReflectionAnswer(questionID: ReflectionCatalog.overallID, rating: 4)]),
            entry(month(8), []),
        ]
        let series = ReflectionArchive.series(of: ReflectionCatalog.overallID, in: entries)
        #expect(series.map(\.month) == [month(7), month(9)])
        #expect(series.map(\.value) == [4.0, 7.0])
    }

    @Test("A year ago is the same calendar month, when it has answers")
    func yearAgo() {
        let last = entry(month(10, year: 2025), [text(ReflectionCatalog.wordID, "Lost")])
        #expect(ReflectionArchive.yearAgo(of: month(10), in: [last])?.word == "Lost")
        #expect(ReflectionArchive.yearAgo(of: month(11), in: [last]) == nil)
    }

    @Test("Search ignores case and accents, newest month first")
    func search() {
        let entries = [
            entry(month(7), [text("core.fears", "Échouer à l'IELTS")]),
            entry(month(9), [text("core.dreams", "Study in Cambridge"), text("core.proud", "ielts score")]),
        ]
        let hits = ReflectionArchive.search("ielts", in: entries)
        #expect(hits.map(\.month) == [month(9), month(7)])
        #expect(ReflectionArchive.search("echouer", in: entries).count == 1)
        #expect(ReflectionArchive.search("  ", in: entries).isEmpty)
    }
}

@Suite("ReflectionReminderScheduler")
struct ReflectionReminderSchedulerTests {
    private let calendar = TestCalendar.utc

    private func scheduler(_ center: FakeUserNotificationCenter, now: Date) -> ReflectionReminderScheduler {
        ReflectionReminderScheduler(center: center, calendar: calendar, now: { now })
    }

    @Test("One reminder on the last day of each of the next months, in the evening")
    func schedules() async {
        let center = FakeUserNotificationCenter()
        let now = TestCalendar.instant(calendar, 2026, 10, 15, 9)
        await scheduler(center, now: now).reschedule(enabled: true, completedMonths: [])
        let pending = await center.pendingNotificationRequests()
        #expect(pending.map(\.identifier) == ["kado.reflection.2026-10", "kado.reflection.2026-11", "kado.reflection.2026-12"])
        let dates = pending.compactMap { ($0.trigger as? UNCalendarNotificationTrigger)?.dateComponents }
        #expect(dates.map(\.day) == [31, 30, 31])
        #expect(dates.allSatisfy { $0.hour == 19 })
        #expect(pending.first?.content.userInfo["reflectionMonth"] as? String == "2026-10")
    }

    @Test("Done months and past times get no reminder; disabling removes them all")
    func skipsAndClears() async {
        let center = FakeUserNotificationCenter()
        let now = TestCalendar.instant(calendar, 2026, 10, 31, 20)
        let october = ReflectionMonth(year: 2026, month: 10)
        await scheduler(center, now: now).reschedule(enabled: true, completedMonths: [october.next])
        #expect(await center.pendingNotificationRequests().map(\.identifier) == ["kado.reflection.2026-12"])
        await scheduler(center, now: now).reschedule(enabled: false, completedMonths: [])
        #expect(await center.pendingNotificationRequests().isEmpty)
    }

    @Test("Habit reminders are left alone")
    func keepsOthers() async throws {
        let center = FakeUserNotificationCenter()
        let other = UNNotificationRequest(identifier: "kado.reminder.x", content: UNMutableNotificationContent(), trigger: nil)
        try await center.add(other)
        await scheduler(center, now: TestCalendar.instant(calendar, 2026, 10, 15)).reschedule(enabled: false, completedMonths: [])
        #expect(await center.pendingNotificationRequests().map(\.identifier) == ["kado.reminder.x"])
    }

    @Test("Month keys round-trip")
    func keys() {
        let month = ReflectionMonth(year: 2026, month: 3)
        #expect(ReflectionReminderScheduler.key(for: month) == "2026-03")
        #expect(ReflectionReminderScheduler.month(fromKey: "2026-03") == month)
        #expect(ReflectionReminderScheduler.month(fromKey: "2026-13") == nil)
    }
}
