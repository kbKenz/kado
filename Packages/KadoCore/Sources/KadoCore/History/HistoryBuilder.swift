import Foundation

/// Which items the History shows.
nonisolated public enum HistoryKind: String, CaseIterable, Hashable, Sendable, Identifiable {
    case all
    case tasks
    case habits

    public var id: String { rawValue }
}

/// The order of the days.
nonisolated public enum HistoryDayOrder: String, CaseIterable, Hashable, Sendable, Identifiable {
    case newestFirst
    case oldestFirst

    public var id: String { rawValue }
}

/// The order of the items in one day.
nonisolated public enum HistoryItemOrder: String, CaseIterable, Hashable, Sendable, Identifiable {
    /// Latest first for newest-first days, earliest first for
    /// oldest-first days, so the page always reads in one direction.
    case time
    /// Category order (`ItemCategory.allCases`), then time.
    case category
    /// Title, A to Z.
    case name

    public var id: String { rawValue }
}

/// What the user asked the History to show.
nonisolated public struct HistoryQuery: Hashable, Sendable {
    public var kind: HistoryKind
    /// Empty: every category.
    public var categories: Set<ItemCategory>
    /// Matched against titles and goal names, case and diacritic
    /// insensitive. Blank: no search.
    public var search: String
    public var dayOrder: HistoryDayOrder
    public var itemOrder: HistoryItemOrder

    public init(
        kind: HistoryKind = .all,
        categories: Set<ItemCategory> = [],
        search: String = "",
        dayOrder: HistoryDayOrder = .newestFirst,
        itemOrder: HistoryItemOrder = .time
    ) {
        self.kind = kind
        self.categories = categories
        self.search = search
        self.dayOrder = dayOrder
        self.itemOrder = itemOrder
    }

    /// `true` when something narrows the items, so an empty result
    /// means "no match" rather than "nothing done yet".
    public var isFiltered: Bool {
        kind != .all || !categories.isEmpty || !search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

/// One thing done on one day.
nonisolated public struct HistoryEntry: Hashable, Sendable, Identifiable {
    public enum Item: Hashable, Sendable {
        /// A task completed that day.
        case task(id: UUID)
        /// A habit record with a positive value. A record of a negative
        /// habit is a slip.
        case habit(id: UUID, completionID: UUID, type: HabitType, value: Double, note: String?)
        /// Time tracked on a task or habit that was not completed or
        /// logged that day.
        case focus(taskID: UUID?, habitID: UUID?)
    }

    public var id: String
    public var item: Item
    public var title: String
    public var category: ItemCategory
    /// A habit's own icon and colour. `nil` for tasks, which show their
    /// category glyph.
    public var habitIcon: String?
    public var habitColor: HabitColor?
    public var goalName: String?
    /// When it happened: completion instant, record instant, or the
    /// start of the first session for a focus entry.
    public var time: Date
    /// Session time tracked on this item that day.
    public var trackedSeconds: TimeInterval

    public var isTask: Bool {
        switch item {
        case .task: true
        case .habit: false
        case .focus(let taskID, _): taskID != nil
        }
    }

    public var isSlip: Bool {
        if case .habit(_, _, .negative, _, _) = item { return true }
        return false
    }
}

/// One day with something done.
nonisolated public struct HistoryDay: Hashable, Sendable, Identifiable {
    /// Calendar midnight.
    public var day: Date
    public var entries: [HistoryEntry]
    /// Days with nothing shown between this day and the one shown
    /// before it on the page. 0 for the first day on the page.
    public var quietDaysBefore: Int

    public var id: Date { day }

    public var tasksDone: Int {
        entries.filter { if case .task = $0.item { true } else { false } }.count
    }

    /// Habit records, slips excluded.
    public var habitsDone: Int {
        entries.filter { if case .habit = $0.item { !$0.isSlip } else { false } }.count
    }

    public var slips: Int { entries.filter(\.isSlip).count }

    public var trackedSeconds: TimeInterval { entries.reduce(0) { $0 + $1.trackedSeconds } }
}

/// Builds the History pages from Insights values.
///
/// Day rules, the same as everywhere else in the app: a habit record
/// belongs to `calendar.startOfDay(for: completion.date)` (records are
/// already stamped on their logical day), a task to the civil day of
/// `completedAt`, a session to `dayBoundary.startOfDay(for: startedAt)`.
/// Cancelled imported events and open sessions are skipped. Zero-value
/// (note-only) habit records are skipped too: nothing was done.
nonisolated public enum HistoryBuilder {
    public static func days(
        input: InsightsInput,
        query: HistoryQuery,
        calendar: Calendar,
        dayBoundary: DayBoundary
    ) -> [HistoryDay] {
        let goalNames = Dictionary(input.goals.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
        let habitsByID = Dictionary(input.habits.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let tasksByID = Dictionary(input.tasks.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        var entries: [Date: [HistoryEntry]] = [:]

        // Tasks.
        for task in input.tasks where !task.isCancelled {
            guard let completedAt = task.completedAt else { continue }
            let day = calendar.startOfDay(for: completedAt)
            entries[day, default: []].append(HistoryEntry(
                id: "task-\(task.id.uuidString)",
                item: .task(id: task.id),
                title: task.title,
                category: task.category,
                goalName: task.goalID.flatMap { goalNames[$0] },
                time: completedAt,
                trackedSeconds: 0
            ))
        }

        // Habit records.
        for habit in input.habits {
            for completion in habit.completions where completion.value > 0 {
                let day = calendar.startOfDay(for: completion.date)
                let note = completion.note?.trimmingCharacters(in: .whitespacesAndNewlines)
                entries[day, default: []].append(HistoryEntry(
                    id: "habit-\(completion.id.uuidString)",
                    item: .habit(
                        id: habit.id,
                        completionID: completion.id,
                        type: habit.habit.type,
                        value: completion.value,
                        note: note?.isEmpty == false ? note : nil
                    ),
                    title: habit.habit.name,
                    category: habit.category,
                    habitIcon: habit.habit.icon,
                    habitColor: habit.habit.color,
                    goalName: habit.habit.goalID.flatMap { goalNames[$0] },
                    time: completion.date,
                    trackedSeconds: 0
                ))
            }
        }

        // Sessions: added to the entry of the same item on the same day,
        // else one focus entry per item and day.
        for session in input.sessions where !session.session.isOpen {
            let seconds = session.session.elapsed(at: session.session.endedAt ?? session.session.startedAt)
            guard seconds > 0, session.taskID != nil || session.habitID != nil else { continue }
            let day = dayBoundary.startOfDay(for: session.session.startedAt)
            var dayEntries = entries[day] ?? []
            if let index = dayEntries.firstIndex(where: { matches($0, session) }) {
                dayEntries[index].trackedSeconds += seconds
                if case .focus = dayEntries[index].item {
                    dayEntries[index].time = min(dayEntries[index].time, session.session.startedAt)
                }
            } else if let entry = focusEntry(for: session, day: day, seconds: seconds,
                                             tasksByID: tasksByID, habitsByID: habitsByID, goalNames: goalNames) {
                dayEntries.append(entry)
            }
            entries[day] = dayEntries
        }

        let search = query.search.trimmingCharacters(in: .whitespacesAndNewlines)
        let keep: (HistoryEntry) -> Bool = { entry in
            switch query.kind {
            case .all: break
            case .tasks: guard entry.isTask else { return false }
            case .habits: guard !entry.isTask else { return false }
            }
            if !query.categories.isEmpty, !query.categories.contains(entry.category) { return false }
            if !search.isEmpty {
                let fields = [entry.title, entry.goalName ?? ""]
                guard fields.contains(where: { $0.range(of: search, options: [.caseInsensitive, .diacriticInsensitive]) != nil }) else {
                    return false
                }
            }
            return true
        }

        let newestFirst = query.dayOrder == .newestFirst
        let sortedDays = entries.keys.sorted(by: newestFirst ? (>) : (<))
        var result: [HistoryDay] = []
        for day in sortedDays {
            let shown = (entries[day] ?? []).filter(keep)
            guard !shown.isEmpty else { continue }
            let quiet = result.last.map { quietDays(between: $0.day, and: day, calendar: calendar) } ?? 0
            result.append(HistoryDay(
                day: day,
                entries: sorted(shown, by: query.itemOrder, latestFirst: newestFirst),
                quietDaysBefore: quiet
            ))
        }
        return result
    }

    private static func matches(_ entry: HistoryEntry, _ session: InsightsSession) -> Bool {
        switch entry.item {
        case .task(let id): session.taskID == id
        case .habit(let id, _, _, _, _): session.taskID == nil && session.habitID == id
        case .focus(let taskID, let habitID): taskID == session.taskID && habitID == session.habitID
        }
    }

    private static func focusEntry(
        for session: InsightsSession,
        day: Date,
        seconds: TimeInterval,
        tasksByID: [UUID: InsightsTask],
        habitsByID: [UUID: InsightsHabit],
        goalNames: [UUID: String]
    ) -> HistoryEntry? {
        let key = "\(session.taskID?.uuidString ?? "-")-\(session.habitID?.uuidString ?? "-")-\(day.timeIntervalSinceReferenceDate)"
        if let taskID = session.taskID {
            guard let task = tasksByID[taskID], !task.isCancelled else { return nil }
            return HistoryEntry(
                id: "focus-\(key)",
                item: .focus(taskID: taskID, habitID: session.habitID),
                title: task.title,
                category: task.category,
                goalName: task.goalID.flatMap { goalNames[$0] },
                time: session.session.startedAt,
                trackedSeconds: seconds
            )
        }
        guard let habitID = session.habitID, let habit = habitsByID[habitID] else { return nil }
        return HistoryEntry(
            id: "focus-\(key)",
            item: .focus(taskID: nil, habitID: habitID),
            title: habit.habit.name,
            category: habit.category,
            habitIcon: habit.habit.icon,
            habitColor: habit.habit.color,
            goalName: habit.habit.goalID.flatMap { goalNames[$0] },
            time: session.session.startedAt,
            trackedSeconds: seconds
        )
    }

    private static func sorted(_ entries: [HistoryEntry], by order: HistoryItemOrder, latestFirst: Bool) -> [HistoryEntry] {
        let byTime: (HistoryEntry, HistoryEntry) -> Bool = { lhs, rhs in
            if lhs.time != rhs.time { return latestFirst ? lhs.time > rhs.time : lhs.time < rhs.time }
            return lhs.id < rhs.id
        }
        switch order {
        case .time:
            return entries.sorted(by: byTime)
        case .category:
            let rank = Dictionary(uniqueKeysWithValues: ItemCategory.allCases.enumerated().map { ($1, $0) })
            return entries.sorted { lhs, rhs in
                let left = rank[lhs.category] ?? .max
                let right = rank[rhs.category] ?? .max
                return left == right ? byTime(lhs, rhs) : left < right
            }
        case .name:
            return entries.sorted { lhs, rhs in
                let comparison = lhs.title.localizedStandardCompare(rhs.title)
                return comparison == .orderedSame ? byTime(lhs, rhs) : comparison == .orderedAscending
            }
        }
    }

    /// Whole days strictly between two calendar midnights.
    static func quietDays(between first: Date, and second: Date, calendar: Calendar) -> Int {
        let distance = abs(calendar.dateComponents([.day], from: first, to: second).day ?? 0)
        return max(0, distance - 1)
    }
}
