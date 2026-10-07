import Foundation

/// Decides which month the check-in is for, when to nudge, and which
/// screens a check-in has. Pure: callers pass the entries they read.
nonisolated public struct ReflectionPlanner: Sendable {
    public let calendar: Calendar

    /// The check-in opens this many days before the month ends.
    public static let opensDaysBeforeEnd = 3
    /// A month not checked in is still offered this many days into the next.
    public static let graceDays = 7

    public init(calendar: Calendar) {
        self.calendar = calendar
    }

    /// The month to check in for at `now`: the month before during its
    /// grace days if that one is not complete, else the current month.
    public func checkInMonth(now: Date, entries: [ReflectionEntry]) -> ReflectionMonth {
        let current = ReflectionMonth(containing: now, calendar: calendar)
        let previous = current.previous
        if dayOfMonth(now) <= Self.graceDays,
           !(entries.first { $0.month == previous }?.isComplete ?? false) {
            return previous
        }
        return current
    }

    /// True when a nudge to check in is due: the last days of the
    /// month, or the grace days after it, while that month is not complete.
    public func isDue(now: Date, entries: [ReflectionEntry]) -> Bool {
        let month = checkInMonth(now: now, entries: entries)
        if entries.first(where: { $0.month == month })?.isComplete == true { return false }
        let current = ReflectionMonth(containing: now, calendar: calendar)
        if month < current { return true }
        let lastDay = month.lastDay(in: calendar)
        let opens = calendar.date(byAdding: .day, value: -(Self.opensDaysBeforeEnd - 1), to: lastDay) ?? lastDay
        return calendar.startOfDay(for: now) >= opens
    }

    /// The screens of the check-in for `month`, in order. Follow-ups
    /// quote the latest earlier answer to the biggest-problem and
    /// intention questions, from any earlier month.
    public func steps(for month: ReflectionMonth, entries: [ReflectionEntry]) -> [ReflectionStep] {
        var steps: [ReflectionStep] = [.intro, .ratings(ReflectionCatalog.ratings)]
        let followUps = ReflectionCatalog.followUps
        if let source = Self.latest(ReflectionCatalog.problemID, before: month, in: entries) {
            steps.append(.followUp(followUps[0], quoted: source.text, sourceMonth: source.month,
                                   options: ReflectionFollowUpStatus.problemOptions))
        }
        if let source = Self.latest(ReflectionCatalog.intentionID, before: month, in: entries) {
            steps.append(.followUp(followUps[1], quoted: source.text, sourceMonth: source.month,
                                   options: ReflectionFollowUpStatus.intentionOptions))
        }
        steps += ReflectionCatalog.core.map(ReflectionStep.question)
        steps.append(.question(ReflectionCatalog.deepQuestion(for: month)))
        steps.append(.finish)
        return steps
    }

    /// The latest non-empty answer to `questionID` in a month before `month`.
    public static func latest(
        _ questionID: String, before month: ReflectionMonth, in entries: [ReflectionEntry]
    ) -> (month: ReflectionMonth, text: String)? {
        entries
            .filter { $0.month < month }
            .sorted { $0.month > $1.month }
            .lazy
            .compactMap { entry in entry.text(questionID).map { (entry.month, $0) } }
            .first
    }

    private func dayOfMonth(_ date: Date) -> Int {
        calendar.component(.day, from: date)
    }
}
