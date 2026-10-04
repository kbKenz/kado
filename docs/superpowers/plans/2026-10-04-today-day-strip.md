# Today Day Strip Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers-extended-cc:subagent-driven-development (recommended) or superpowers-extended-cc:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A horizontal day strip at the top of Today selects any day; Today then shows that day's tasks and habits, lets the user backfill past days, and shows future days (tasks editable, habits view-only).

**Architecture:** Pure, tested day logic lives in KadoCore (`DayStripRange`, `DayStripProgress`, `Habit.isListed`) and in the app target (`TodayDayKind`, `TaskDaySections`). `TodayView` stores `selectedDay: Date?` (`nil` = today) and passes a `displayedDay` everywhere it used `today`. A new `DayStrip` view is pinned with `.safeAreaInset(edge: .top)`.

**Tech Stack:** Swift 6 (default MainActor isolation), SwiftUI, SwiftData, Swift Testing, XCUITest.

**Spec:** `docs/superpowers/specs/2026-10-04-today-day-strip-design.md`

---

## Ground rules for every task

- Work only in the worktree `/Users/bekturkenzhebaev/Documents/GitHub/kado/.worktrees/feat-today-day-strip`. Check with `git rev-parse --show-toplevel` before the first edit.
- Toolchain: prefix every `make`/`xcodebuild` with `DEVELOPER_DIR=/Applications/Xcode-26.5.app/Contents/Developer`. The worktree's simulator is `Kado feat-today-day-strip` (`make sim` creates it).
- Run a single suite: `DEVELOPER_DIR=/Applications/Xcode-26.5.app/Contents/Developer make test` runs all of `KadoTests`. For one suite, use
  `DEVELOPER_DIR=/Applications/Xcode-26.5.app/Contents/Developer xcodebuild test -project Kado.xcodeproj -scheme Kado -destination 'platform=iOS Simulator,name=Kado feat-today-day-strip' -derivedDataPath build -only-testing:KadoTests/<SuiteStructName> -quiet`.
  If it reports "0 tests" or "No eligible connection available", run it again once (known flake).
- KadoCore types: `nonisolated public`. Day math through `Calendar` only (never `86_400`).
- Tests pin calendars with `TestCalendar.utc`, `.paris`, `.havana` (`KadoTests/Helpers/TestCalendar.swift`).
- `Localizable.xcstrings` (`Kado/Resources/Localizable.xcstrings`): insert new keys only, in Xcode's sorted key order, each with `comment` and `en` + `fr` `stringUnit` (`"state" : "translated"`). Do not reformat the file. FR uses `tu`.
- Commits: conventional, small, ending with
  ```
  Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>
  Claude-Session: https://claude.ai/code/session_01HWT8fo21dQ2K9hgBPEj1e7
  ```

## File map

| File | Status | Responsibility |
|---|---|---|
| `Packages/KadoCore/Sources/KadoCore/Services/DayStripRange.swift` | new | Days the strip offers; clamp |
| `Packages/KadoCore/Sources/KadoCore/Models/Habit+Listing.swift` | new | First day a habit shows on Today |
| `Packages/KadoCore/Sources/KadoCore/Services/DayStripProgress.swift` | new | Ring progress for one day |
| `Kado/Views/Today/TodayDayKind.swift` | new | past / today / future |
| `Kado/Views/Tasks/TaskDaySections.swift` | new | Task sections for one day |
| `Kado/Views/Today/TodayRow.swift` | modify | First-day filter |
| `Kado/Views/Today/DayStripCell.swift` | new | One cell |
| `Kado/Views/Today/DayStrip.swift` | new | Scrolling strip |
| `Shared/AccessibilityID.swift` | modify | Strip + Today button ids |
| `Kado/Views/Today/TodayView.swift` | modify | Selected day wiring |
| `Kado/Views/Today/CounterLogSheet.swift`, `Kado/Views/HabitDetail/TimerLogSheet.swift` | modify | `day` parameter |
| `Kado/Resources/Localizable.xcstrings` | modify | New strings |
| `KadoTests/DayStripRangeTests.swift`, `DayStripProgressTests.swift`, `TodayDayKindTests.swift`, `TaskDaySectionsTests.swift`, `TodayBackfillTests.swift` | new | Unit tests |
| `KadoTests/TodayRowTests.swift` | modify | First-day filter tests |
| `KadoUITests/TodayDayStripTests.swift` | new | End-to-end |

---

### Task 1: DayStripRange (KadoCore)

**Goal:** A pure function that lists the strip's days, DST-safe, plus a clamp.

**Files:**
- Create: `Packages/KadoCore/Sources/KadoCore/Services/DayStripRange.swift`
- Test: `KadoTests/DayStripRangeTests.swift`

**Acceptance Criteria:**
- [ ] With no data: today … today+60 (61 days).
- [ ] With an earlier date: starts at that date's midnight.
- [ ] A future `earliest` never starts the range after today.
- [ ] Every element is a real midnight and consecutive days differ by exactly one calendar day, in Paris (2026-10-25) and Havana (2026-03-08).
- [ ] `clamp` returns the nearest end for out-of-range days.

**Verify:** `-only-testing:KadoTests/DayStripRangeTests` → all pass

**Steps:**

- [ ] **Step 1: Write the failing tests** — `KadoTests/DayStripRangeTests.swift`

```swift
import Foundation
import Testing
import KadoCore

@Suite("DayStripRange")
struct DayStripRangeTests {
    @Test("No data: today through 60 days ahead")
    func noData() {
        let cal = TestCalendar.utc
        let today = TestCalendar.referenceDate
        let days = DayStripRange.days(from: nil, today: today, calendar: cal)
        #expect(days.count == 61)
        #expect(days.first == cal.startOfDay(for: today))
        #expect(days.last == cal.startOfDay(for: TestCalendar.day(60)))
    }

    @Test("Starts at the earliest day's midnight")
    func earliestInPast() {
        let cal = TestCalendar.utc
        let earliest = cal.date(byAdding: .hour, value: 3, to: TestCalendar.day(-3))!
        let days = DayStripRange.days(from: earliest, today: TestCalendar.referenceDate, calendar: cal)
        #expect(days.first == cal.startOfDay(for: TestCalendar.day(-3)))
        #expect(days.count == 64)
    }

    @Test("A future earliest date never moves the start past today")
    func earliestInFuture() {
        let cal = TestCalendar.utc
        let days = DayStripRange.days(from: TestCalendar.day(5), today: TestCalendar.referenceDate, calendar: cal)
        #expect(days.first == cal.startOfDay(for: TestCalendar.referenceDate))
    }

    @Test("Every day is a midnight, one calendar day apart, across DST", arguments: [
        (TestCalendar.paris, 2026, 10, 20, 2026, 10, 30),
        (TestCalendar.havana, 2026, 3, 4, 2026, 3, 12),
    ])
    func dstInvariant(_ cal: Calendar, _ y1: Int, _ m1: Int, _ d1: Int, _ y2: Int, _ m2: Int, _ d2: Int) {
        let earliest = TestCalendar.instant(cal, y1, m1, d1, 12)
        let today = TestCalendar.instant(cal, y2, m2, d2, 12)
        let days = DayStripRange.days(from: earliest, today: today, futureDays: 3, calendar: cal)
        let back = cal.dateComponents([.day], from: cal.startOfDay(for: earliest), to: cal.startOfDay(for: today)).day!
        #expect(days.count == back + 1 + 3)
        for day in days { #expect(day == cal.startOfDay(for: day)) }
        for (a, b) in zip(days, days.dropFirst()) {
            #expect(cal.dateComponents([.day], from: cal.startOfDay(for: a), to: cal.startOfDay(for: b)).day == 1)
        }
    }

    @Test("Clamp returns the nearest end")
    func clamp() {
        let cal = TestCalendar.utc
        let days = DayStripRange.days(from: TestCalendar.day(-2), today: TestCalendar.referenceDate, futureDays: 2, calendar: cal)
        #expect(DayStripRange.clamp(TestCalendar.day(-10), to: days) == days.first)
        #expect(DayStripRange.clamp(TestCalendar.day(10), to: days) == days.last)
        #expect(DayStripRange.clamp(days[1], to: days) == days[1])
        #expect(DayStripRange.clamp(TestCalendar.day(0), to: []) == nil)
    }
}
```

- [ ] **Step 2: Run, expect FAIL** ("cannot find 'DayStripRange'").

- [ ] **Step 3: Implement** — `Packages/KadoCore/Sources/KadoCore/Services/DayStripRange.swift`

```swift
import Foundation

/// The days Today's day strip offers: from the first day the user had
/// anything to look back on, to `futureDays` after today. Every element
/// is a calendar midnight, as `Calendar.startOfDay` returns them.
nonisolated public enum DayStripRange {
    /// How far ahead the strip reaches.
    public static let defaultFutureDays = 60

    public static func days(
        from earliest: Date?,
        today: Date,
        futureDays: Int = defaultFutureDays,
        calendar: Calendar
    ) -> [Date] {
        let todayStart = calendar.startOfDay(for: today)
        let first = earliest.map { min(calendar.startOfDay(for: $0), todayStart) } ?? todayStart
        guard let last = calendar.date(byAdding: .day, value: max(futureDays, 0), to: todayStart) else {
            return [todayStart]
        }
        let lastStart = calendar.startOfDay(for: last)
        var days: [Date] = []
        var cursor = first
        while cursor <= lastStart {
            days.append(cursor)
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            // Re-anchored: where DST starts at midnight (Havana) the
            // next day begins at 01:00, and adding a day from there
            // keeps the 01:00 rather than landing on a midnight.
            cursor = calendar.startOfDay(for: next)
        }
        return days
    }

    /// `day` moved inside `days`, or `nil` when `days` is empty.
    public static func clamp(_ day: Date, to days: [Date]) -> Date? {
        guard let first = days.first, let last = days.last else { return nil }
        return min(max(day, first), last)
    }
}
```

- [ ] **Step 4: Run, expect PASS.**
- [ ] **Step 5: Commit** — `feat(today): add day strip range`

---

### Task 2: Habit listing rule and DayStripProgress (KadoCore)

**Goal:** One rule for "does this habit show on day D" and the ring's `DayProgress` for a day.

**Files:**
- Create: `Packages/KadoCore/Sources/KadoCore/Models/Habit+Listing.swift`
- Create: `Packages/KadoCore/Sources/KadoCore/Services/DayStripProgress.swift`
- Test: `KadoTests/DayStripProgressTests.swift`

**Acceptance Criteria:**
- [ ] `isListed(on:)` is false before the earlier of `createdAt` and `effectiveStart`, true from that day on.
- [ ] Progress counts habits that are listed and `isDueOrLogged` that day; `completed` counts `HabitRowState.isDone`.
- [ ] Future days: `completed == 0`, `total` = due count.
- [ ] Nothing due → `DayProgress.empty`.

**Verify:** `-only-testing:KadoTests/DayStripProgressTests` → all pass

**Steps:**

- [ ] **Step 1: Write the failing tests** — `KadoTests/DayStripProgressTests.swift`

```swift
import Foundation
import Testing
import KadoCore

@Suite("DayStripProgress")
struct DayStripProgressTests {
    private let cal = TestCalendar.utc
    private let evaluator = DefaultFrequencyEvaluator()

    private func habit(_ name: String, type: HabitType = .binary, createdDaysAgo: Int = 10) -> Habit {
        Habit(name: name, frequency: .daily, type: type, createdAt: TestCalendar.day(-createdDaysAgo))
    }

    @Test("Listed from the earlier of creation and first completion")
    func listing() {
        let h = habit("Read", createdDaysAgo: 3)
        #expect(!h.isListed(on: TestCalendar.day(-4), completions: [], calendar: cal))
        #expect(h.isListed(on: TestCalendar.day(-3), completions: [], calendar: cal))
        let backfilled = [Completion(habitID: h.id, date: TestCalendar.day(-6))]
        #expect(h.isListed(on: TestCalendar.day(-6), completions: backfilled, calendar: cal))
    }

    @Test("Counts due and done habits on a past day")
    func pastDay() {
        let a = habit("A"), b = habit("B")
        let day = TestCalendar.day(-1)
        let comps = [a.id: [Completion(habitID: a.id, date: day)]]
        let p = DayStripProgress.progress(on: day, isFuture: false, habits: [a, b],
                                          completions: comps, evaluator: evaluator, calendar: cal)
        #expect(p == DayProgress(completed: 1, total: 2))
    }

    @Test("Future days count due habits but none done")
    func futureDay() {
        let negative = habit("No sugar", type: .negative)
        let p = DayStripProgress.progress(on: TestCalendar.day(2), isFuture: true, habits: [habit("A"), negative],
                                          completions: [:], evaluator: evaluator, calendar: cal)
        #expect(p == DayProgress(completed: 0, total: 2))
    }

    @Test("A day before every habit's first day is empty")
    func beforeStart() {
        let p = DayStripProgress.progress(on: TestCalendar.day(-20), isFuture: false, habits: [habit("A")],
                                          completions: [:], evaluator: evaluator, calendar: cal)
        #expect(p == .empty)
    }
}
```

- [ ] **Step 2: Run, expect FAIL.**

- [ ] **Step 3: Implement** — `Habit+Listing.swift`

```swift
import Foundation

public extension Habit {
    /// The first day this habit shows on Today's other days: the earlier
    /// of its creation day and its effective start (a backfill can move
    /// the start before creation). Today never lists a habit before this
    /// day, so it never logs a pre-start day — that case keeps its
    /// warning in Overview and Habit Detail (issue #104).
    func firstListedDay(completions: [Completion], calendar: Calendar) -> Date {
        let start = effectiveStart(completions: completions, calendar: calendar)
        return calendar.startOfDay(for: min(createdAt, start))
    }

    func isListed(on day: Date, completions: [Completion], calendar: Calendar) -> Bool {
        calendar.startOfDay(for: day) >= firstListedDay(completions: completions, calendar: calendar)
    }
}
```

`DayStripProgress.swift`:

```swift
import Foundation

/// The ring on one day-strip cell: habits done against habits due, with
/// the same rule as Today's "Habits today" section (listed on the day,
/// `isDueOrLogged`, `HabitRowState.isDone`), so the ring and the list
/// never disagree. Tasks are not counted — `DayProgress` is habits-only
/// everywhere (confetti, lock-screen ring).
nonisolated public enum DayStripProgress {
    public static func progress(
        on day: Date,
        isFuture: Bool,
        habits: [Habit],
        completions: [UUID: [Completion]],
        evaluator: any FrequencyEvaluating,
        calendar: Calendar
    ) -> DayProgress {
        var total = 0
        var completed = 0
        for habit in habits {
            let comps = completions[habit.id] ?? []
            guard habit.isListed(on: day, completions: comps, calendar: calendar),
                  evaluator.isDueOrLogged(habit: habit, on: day, completions: comps, calendar: calendar)
            else { continue }
            total += 1
            // Nothing can be done ahead of its day; a negative habit
            // would otherwise read as "done" on every future day.
            guard !isFuture else { continue }
            let state = HabitRowState.resolve(habit: habit, completions: comps, calendar: calendar, asOf: day)
            if state.isDone(for: habit) { completed += 1 }
        }
        return DayProgress(completed: completed, total: total)
    }
}
```

If `Habit` / `DayProgress` lack `Equatable` for `#expect(==)`: both are `Hashable`, so `==` works.

- [ ] **Step 4: Run, expect PASS.**
- [ ] **Step 5: Commit** — `feat(today): add habit listing rule and day strip progress`

---

### Task 3: TodayDayKind and TaskDaySections (app target)

**Goal:** Classify the selected day and compute the task sections for it; today's output equals the current `TodayView.taskSections`.

**Files:**
- Create: `Kado/Views/Today/TodayDayKind.swift`
- Create: `Kado/Views/Tasks/TaskDaySections.swift`
- Modify: `Kado/Views/Today/TodayView.swift` (`taskSections`, ~line 307-332)
- Test: `KadoTests/TodayDayKindTests.swift`, `KadoTests/TaskDaySectionsTests.swift`

**Acceptance Criteria:**
- [ ] `TodayDayKind(day:today:calendar:)` gives `.past/.today/.future` by calendar day; `allowsHabitLogging` is false only for `.future`.
- [ ] Today: same due/overdue, inbox, completed as before (moved code, no behaviour change).
- [ ] Past: `completed` = completed that day; `due` = open tasks due that day or scheduled on it (not overdue ones from earlier); inbox empty.
- [ ] Future: `due` = tasks due or scheduled that day, open **and** completed (completed rows show ticked); `completed` and inbox empty.
- [ ] A schedule block from 23:00 to 01:00 belongs to both days.

**Verify:** `-only-testing:KadoTests/TodayDayKindTests -only-testing:KadoTests/TaskDaySectionsTests` → all pass

**Steps:**

- [ ] **Step 1: Write the failing tests**

`KadoTests/TodayDayKindTests.swift`:

```swift
import Foundation
import Testing
@testable import Kado

@Suite("TodayDayKind")
struct TodayDayKindTests {
    private let cal = TestCalendar.utc

    @Test("Past, today and future by calendar day")
    func kinds() {
        let today = TestCalendar.referenceDate
        #expect(TodayDayKind(day: TestCalendar.day(-1), today: today, calendar: cal) == .past)
        #expect(TodayDayKind(day: cal.startOfDay(for: today), today: today, calendar: cal) == .today)
        #expect(TodayDayKind(day: TestCalendar.day(1), today: today, calendar: cal) == .future)
    }

    @Test("Only future days refuse habit logging")
    func logging() {
        #expect(TodayDayKind.past.allowsHabitLogging)
        #expect(TodayDayKind.today.allowsHabitLogging)
        #expect(!TodayDayKind.future.allowsHabitLogging)
    }
}
```

`KadoTests/TaskDaySectionsTests.swift`:

```swift
import Foundation
import Testing
@testable import Kado

@Suite("TaskDaySections")
struct TaskDaySectionsTests {
    private let cal = TestCalendar.utc
    private var today: Date { cal.startOfDay(for: TestCalendar.referenceDate) }

    private func ids(_ items: [TaskListItem]) -> [String] { items.map(\.title) }

    @Test("Today keeps overdue, inbox and completed-today")
    func todaySections() {
        let items = [
            TaskListItem(title: "Overdue", dueDate: TestCalendar.day(-2)),
            TaskListItem(title: "Due", dueDate: TestCalendar.day(0)),
            TaskListItem(title: "Inbox"),
            TaskListItem(title: "Later", dueDate: TestCalendar.day(3)),
            TaskListItem(title: "Done", dueDate: TestCalendar.day(0), completedAt: TestCalendar.day(0)),
        ]
        let s = TaskDaySections.make(for: today, kind: .today, items: items, calendar: cal)
        #expect(ids(s.due) == ["Overdue", "Due"])
        #expect(ids(s.inbox) == ["Inbox"])
        #expect(ids(s.completed) == ["Done"])
    }

    @Test("Past day: completed that day, still-open due that day, no overdue, no inbox")
    func pastSections() {
        let day = TestCalendar.day(-2)
        let items = [
            TaskListItem(title: "Older", dueDate: TestCalendar.day(-5)),
            TaskListItem(title: "Missed", dueDate: day),
            TaskListItem(title: "Done then", completedAt: cal.date(byAdding: .hour, value: 2, to: day)),
            TaskListItem(title: "Inbox"),
        ]
        let s = TaskDaySections.make(for: day, kind: .past, items: items, calendar: cal)
        #expect(ids(s.due) == ["Missed"])
        #expect(ids(s.completed) == ["Done then"])
        #expect(s.inbox.isEmpty)
    }

    @Test("Future day: planned tasks, open and completed")
    func futureSections() {
        let day = TestCalendar.day(3)
        let items = [
            TaskListItem(title: "Plan", dueDate: day),
            TaskListItem(title: "Early", dueDate: day, completedAt: TestCalendar.day(0)),
            TaskListItem(title: "Other", dueDate: TestCalendar.day(4)),
        ]
        let s = TaskDaySections.make(for: day, kind: .future, items: items, calendar: cal)
        #expect(Set(ids(s.due)) == ["Plan", "Early"])
        #expect(s.completed.isEmpty && s.inbox.isEmpty)
    }

    @Test("A block across midnight belongs to both days")
    func acrossMidnight() {
        let d1 = TestCalendar.day(2), d2 = TestCalendar.day(3)
        let block = TaskScheduleItem(plannedDay: d1,
                                     startAt: cal.date(byAdding: .hour, value: 11, to: d1),   // 23:00 (reference is 12:00)
                                     endAt: cal.date(byAdding: .hour, value: 13, to: d1))     // 01:00 next day
        let item = TaskListItem(title: "Night", schedules: [block])
        #expect(ids(TaskDaySections.make(for: d1, kind: .future, items: [item], calendar: cal).due) == ["Night"])
        #expect(ids(TaskDaySections.make(for: d2, kind: .future, items: [item], calendar: cal).due) == ["Night"])
    }
}
```

(`TestCalendar.day(n)` is noon UTC, so +11 h = 23:00 and +13 h = 01:00 next day.)

- [ ] **Step 2: Run, expect FAIL.**

- [ ] **Step 3: Implement**

`Kado/Views/Today/TodayDayKind.swift`:

```swift
import Foundation

/// Where the day Today is showing sits relative to the habit-day today.
enum TodayDayKind: Equatable {
    case past, today, future

    init(day: Date, today: Date, calendar: Calendar) {
        let day = calendar.startOfDay(for: day)
        let today = calendar.startOfDay(for: today)
        if day < today { self = .past } else if day == today { self = .today } else { self = .future }
    }

    /// A habit can't be done before its day, so future days are view-only
    /// for habits. Past days allow backfill.
    var allowsHabitLogging: Bool { self != .future }
}
```

`Kado/Views/Tasks/TaskDaySections.swift`:

```swift
import Foundation

/// The task sections Today shows for one day.
///
/// - today: due and overdue, the inbox, and tasks completed today.
/// - past: tasks completed that day, then tasks due or scheduled that
///   day that are still open. Overdue tasks from earlier days show only
///   on today, as before.
/// - future: tasks due or scheduled that day, open and completed, so a
///   task completed early stays on its day with a tick.
///
/// Task days are civil days (as the Calendar tab); callers pass a civil
/// midnight for `day`.
struct TaskDaySections {
    var due: [TaskListItem] = []
    var inbox: [TaskListItem] = []
    var completed: [TaskListItem] = []

    static func make(for day: Date, kind: TodayDayKind, items: [TaskListItem], calendar: Calendar) -> TaskDaySections {
        let start = calendar.startOfDay(for: day)
        let pending = items.filter { !$0.isComplete }
        let onDay: (TaskListItem) -> Bool = { item in
            item.dueDate.map { calendar.isDate($0, inSameDayAs: start) } == true
                || item.schedules.contains { $0.belongs(to: start, calendar: calendar) }
        }
        let completedOnDay = items.filter { item in
            item.completedAt.map { calendar.isDate($0, inSameDayAs: start) } == true
        }.sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }

        switch kind {
        case .today:
            let due = pending.filter { item in
                item.dueDate.map { calendar.startOfDay(for: $0) <= start } == true
                    || item.schedules.contains { $0.belongs(to: start, calendar: calendar) }
            }
            let inbox = pending.filter { $0.dueDate == nil && $0.schedules.isEmpty }
            return TaskDaySections(due: sortedByPlan(due), inbox: inbox, completed: completedOnDay)
        case .past:
            return TaskDaySections(due: sortedByPlan(pending.filter(onDay)), completed: completedOnDay)
        case .future:
            return TaskDaySections(due: sortedByPlan(items.filter(onDay)))
        }
    }

    /// Due day, then start time, then title — the order Today always used.
    private static func sortedByPlan(_ items: [TaskListItem]) -> [TaskListItem] {
        items.sorted { lhs, rhs in
            let leftDate = lhs.dueDate ?? lhs.schedules.first?.plannedDay ?? .distantFuture
            let rightDate = rhs.dueDate ?? rhs.schedules.first?.plannedDay ?? .distantFuture
            if leftDate != rightDate { return leftDate < rightDate }
            let leftTime = lhs.schedules.first?.startAt ?? .distantFuture
            let rightTime = rhs.schedules.first?.startAt ?? .distantFuture
            return leftTime == rightTime
                ? lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
                : leftTime < rightTime
        }
    }
}
```

In `TodayView.swift`, replace the body of `taskSections` (keep the signature for now; Task 6 changes it):

```swift
    private var taskSections: (due: [TaskListItem], inbox: [TaskListItem], completed: [TaskListItem]) {
        // Task planning uses civil days, while the existing habit rows
        // continue to use the user's custom habit-day boundary.
        let s = TaskDaySections.make(for: civilToday, kind: .today,
                                     items: activeTasks.map { TaskListItem($0) }, calendar: calendar)
        return (s.due, s.inbox, s.completed)
    }
```

- [ ] **Step 4: Run the two suites and `-only-testing:KadoTests/TodayRowTests`, expect PASS.**
- [ ] **Step 5: Commit** — `feat(today): add day kind and per-day task sections`

---

### Task 4: First-day filter in TodayRow.sections

**Goal:** Habits don't appear on days before their first listed day.

**Files:**
- Modify: `Kado/Views/Today/TodayRow.swift` (loop in `sections(from:on:evaluator:calendar:)`)
- Test: `KadoTests/TodayRowTests.swift` (add one test)

**Acceptance Criteria:**
- [ ] A habit created on day X is in neither section on X−1, and is in a section on X.
- [ ] Existing `TodayRowTests` still pass.

**Verify:** `-only-testing:KadoTests/TodayRowTests` → all pass

**Steps:**

- [ ] **Step 1: Add the failing test** inside `TodayRowTests` (it uses `makeContainer()`, `calendar`, `evaluator`, `now` = 2026-03-11 12:00 UTC):

```swift
    @Test("A habit is not listed before its first day")
    func notListedBeforeFirstDay() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let habit = HabitRecord(name: "Walk", frequency: .daily, type: .binary, createdAt: now)
        ctx.insert(habit)
        try ctx.save()

        let yesterday = calendar.date(byAdding: .day, value: -1, to: now)!
        let before = TodayRow.sections(from: [habit], on: yesterday, evaluator: evaluator, calendar: calendar)
        #expect(before.due.isEmpty && before.other.isEmpty)

        let onDay = TodayRow.sections(from: [habit], on: now, evaluator: evaluator, calendar: calendar)
        #expect(onDay.due.map(\.id) == [habit.id])
    }
```

Check `HabitRecord`'s init labels in `Packages/KadoCore/Sources/KadoCore/Models/Persistence/KadoSchemaV7.swift` and match them (the existing test in this file shows the call shape).

- [ ] **Step 2: Run, expect FAIL** (habit shows in `other` on yesterday).

- [ ] **Step 3: Implement** — at the top of the `for row in records.map({ TodayRow($0) })` loop body:

```swift
            // Days before a habit's first day aren't its days at all;
            // listing it there would let a tap backdate its start (#104).
            guard row.habit.isListed(on: now, completions: row.completions, calendar: calendar) else {
                continue
            }
```

- [ ] **Step 4: Run, expect PASS.**
- [ ] **Step 5: Commit** — `feat(today): hide habits on days before their first day`

---

### Task 5: DayStrip and DayStripCell views

**Goal:** The strip UI, with accessibility, previews and strings.

**Files:**
- Create: `Kado/Views/Today/DayStripCell.swift`, `Kado/Views/Today/DayStrip.swift`
- Modify: `Shared/AccessibilityID.swift` (inside `enum Today`)
- Modify: `Kado/Resources/Localizable.xcstrings`

**Acceptance Criteria:**
- [ ] Cell: weekday letter (`Weekday.localizedShort`), day number, ring of `progress.fraction`; dot when `progress.total == 0`.
- [ ] Selected: accent fill, text `Color.kadoBackground`. Today (unselected): number in `Color.kadoAccent`.
- [ ] Cell is a `Button`: label = full date ("Saturday, October 4"), value = "%lld of %lld habits done" (plural) or "Nothing due", `.isSelected` trait when selected; identifier `AccessibilityID.Today.dayStripCell(day)`.
- [ ] Strip scrolls horizontally, snaps to cells, centres the selection on appear and on change (animation off under Reduce Motion).
- [ ] Previews: default, and `#Preview("Dark")`.
- [ ] Build succeeds.

**Verify:** `DEVELOPER_DIR=… make build` (or `xcodebuild build` with the destination above) → succeeds with no new warnings

**Steps:**

- [ ] **Step 1: AccessibilityID** — add inside `enum Today`:

```swift
        /// One day-strip cell. On the cell's `Button` (a leaf).
        static func dayStripCell(_ day: Date) -> String {
            let f = DateFormatter()
            f.calendar = Calendar(identifier: .gregorian)
            f.locale = Locale(identifier: "en_US_POSIX")
            f.timeZone = .current
            f.dateFormat = "yyyy-MM-dd"
            return "today.dayStrip.\(f.string(from: day))"
        }
        /// The toolbar button that jumps back to today.
        static let jumpToTodayButton = "today.jumpToToday"
```

- [ ] **Step 2: `DayStripCell.swift`**

```swift
import SwiftUI
import KadoCore

/// One day in Today's day strip: weekday letter, day number, and a ring
/// of that day's habit progress.
struct DayStripCell: View {
    let day: Date
    let isSelected: Bool
    let isToday: Bool
    let progress: DayProgress
    let onSelect: () -> Void

    @Environment(\.calendar) private var calendar

    private var weekday: Weekday {
        Weekday(rawValue: calendar.component(.weekday, from: day)) ?? .monday
    }

    var body: some View {
        Button(action: onSelect) {
            VStack(spacing: 4) {
                Text(weekday.localizedShort)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(isSelected ? Color.kadoBackground : Color.kadoForegroundSecondary)
                Text(day, format: .dateTime.day())
                    .font(.callout.weight(.semibold).monospacedDigit())
                    .foregroundStyle(numberColor)
                ring
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 6)
            .frame(minWidth: 44)
            .background {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isSelected ? Color.kadoAccent : Color.clear)
            }
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(day, format: .dateTime.weekday(.wide).month(.wide).day()))
        .accessibilityValue(accessibilityValue)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier(AccessibilityID.Today.dayStripCell(day))
    }

    private var numberColor: Color {
        if isSelected { return Color.kadoBackground }
        return isToday ? Color.kadoAccent : Color.kadoForeground
    }

    @ViewBuilder
    private var ring: some View {
        let tint = isSelected ? Color.kadoBackground : Color.kadoAccent
        if progress.total == 0 {
            Circle().fill(tint.opacity(0.4)).frame(width: 4, height: 4).frame(width: 14, height: 14)
        } else {
            ZStack {
                Circle().stroke(tint.opacity(0.25), lineWidth: 2.5)
                Circle().trim(from: 0, to: progress.fraction)
                    .stroke(tint, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            .frame(width: 14, height: 14)
        }
    }

    private var accessibilityValue: String {
        progress.total == 0
            ? String(localized: "Nothing due")
            : String(localized: "\(progress.completed) of \(progress.total) habits done")
    }
}

#Preview {
    HStack {
        DayStripCell(day: .now, isSelected: true, isToday: true, progress: .init(completed: 2, total: 3)) {}
        DayStripCell(day: .now.addingTimeInterval(-86_400), isSelected: false, isToday: false, progress: .init(completed: 3, total: 3)) {}
        DayStripCell(day: .now.addingTimeInterval(86_400), isSelected: false, isToday: false, progress: .empty) {}
    }
    .padding()
}

#Preview("Dark") {
    HStack {
        DayStripCell(day: .now, isSelected: false, isToday: true, progress: .init(completed: 1, total: 4)) {}
        DayStripCell(day: .now, isSelected: true, isToday: false, progress: .init(completed: 4, total: 4)) {}
    }
    .padding()
    .preferredColorScheme(.dark)
}
```

(`addingTimeInterval` is acceptable only in previews; never in logic.) (`Color.kadoForeground` exists; `DayEditPopover` uses it.)

- [ ] **Step 3: `DayStrip.swift`**

```swift
import SwiftUI
import KadoCore

/// The scrolling row of days at the top of Today, like the date strip in
/// sleep-score apps. Lazy, so a long history costs only what's on screen.
struct DayStrip: View {
    let days: [Date]
    @Binding var selection: Date
    let today: Date
    let progress: (Date) -> DayProgress

    @Environment(\.calendar) private var calendar
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 4) {
                    ForEach(days, id: \.self) { day in
                        DayStripCell(
                            day: day,
                            isSelected: calendar.isDate(day, inSameDayAs: selection),
                            isToday: calendar.isDate(day, inSameDayAs: today),
                            progress: progress(day),
                            onSelect: { selection = day }
                        )
                        .id(day)
                    }
                }
                .scrollTargetLayout()
                .padding(.horizontal, 16)
            }
            .scrollTargetBehavior(.viewAligned)
            .onAppear { proxy.scrollTo(selection, anchor: .center) }
            .onChange(of: selection) { _, newValue in
                withAnimation(reduceMotion ? nil : .snappy) {
                    proxy.scrollTo(newValue, anchor: .center)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

private struct DayStripPreview: View {
    @State private var selection = Calendar.current.startOfDay(for: .now)
    var body: some View {
        let cal = Calendar.current
        let days = DayStripRange.days(from: cal.date(byAdding: .day, value: -30, to: .now), today: .now, calendar: cal)
        DayStrip(days: days, selection: $selection, today: cal.startOfDay(for: .now)) { day in
            day < selection ? DayProgress(completed: 2, total: 3) : .empty
        }
    }
}

#Preview { DayStripPreview() }
#Preview("Dark") { DayStripPreview().preferredColorScheme(.dark) }
```

- [ ] **Step 4: Strings** — insert into `Localizable.xcstrings` in sorted position:
  - `"%lld of %lld habits done"` — comment "Day strip cell accessibility value: habits done of habits due that day"; en `%1$lld of %2$lld habits done`; fr `%1$lld habitudes faites sur %2$lld`. Use `variations.plural` on the second argument only if the catalog's other `%lld of %lld` keys do; otherwise a plain `stringUnit`.
  - `"Nothing due"` — comment "Day strip cell accessibility value when no habit is due that day"; fr `Rien de prévu`.
  Look at an existing two-argument key in the catalog first and copy its shape exactly.

- [ ] **Step 5: Build, expect success.** Run `-only-testing:KadoTests/LocalizationCoverageTests`, expect PASS.
- [ ] **Step 6: Commit** — `feat(today): add day strip views`

---

### Task 6: Wire the selected day into TodayView

**Goal:** Today shows and edits the selected day; strip pinned at the top; title and Today button.

**Files:**
- Modify: `Kado/Views/Today/TodayView.swift`
- Modify: `Kado/Resources/Localizable.xcstrings`
- Test: `KadoTests/TodayBackfillTests.swift`

**Acceptance Criteria:**
- [ ] `@State private var selectedDay: Date?`; `displayedDay = selectedDay.map { calendar.startOfDay(for: $0) } ?? today`; `dayKind = TodayDayKind(day: displayedDay, today: today, calendar: calendar)`.
- [ ] Strip pinned via `.safeAreaInset(edge: .top)` with `Color.kadoBackground` behind it; range from `DayStripRange.days(from: earliestRecordDate, today: today, calendar:)`, where `earliestRecordDate` = min of habit `createdAt`, completion dates and task `createdAt` — all from the `@Query` arrays.
- [ ] Selecting today sets `selectedDay = nil`. If `selectedDay` falls outside the range, clamp it in `.onChange(of: days)`.
- [ ] Title: "Today" for `.today`, else `Text(displayedDay, format: .dateTime.weekday(.abbreviated).month(.abbreviated).day())`. Toolbar `Button("Today")` (identifier `jumpToTodayButton`, placement `.topBarLeading`) only when not today.
- [ ] Sections per the spec table: task sections from `TaskDaySections.make(for: kind == .today ? civilToday : displayedDay, kind: dayKind, …)`; section headers: today unchanged; past "Completed" / "Due"; future "Planned"; inbox, rollover caption and bottom card only on `.today`; empty text "Nothing on this day" for past/future.
- [ ] Habit rows: `TodayRow.sections(from:on: displayedDay, …)`; state/streak/score `asOf: displayedDay`; on `.future` all habit callbacks except `onOpenDetail` are `nil` and no swipe actions; `moveHabits` only on `.today` (`.onMove` nil otherwise).
- [ ] `loggingInstant` uses `displayedDay`.
- [ ] Task toggle: `completedAt = dayKind == .past ? dayBoundary.loggingInstant(for: .now, on: displayedDay) : .now`.
- [ ] `checkMilestones` returns early unless `dayKind == .today`.
- [ ] New task sheet: `TaskFormView(defaultDay: dayKind == .today ? nil : displayedDay)`.
- [ ] Unit tests for backfill pass; the whole `KadoTests` suite passes.

**Verify:** `DEVELOPER_DIR=… make test` → all pass (1 known issue allowed, as on `main`)

**Steps:**

- [ ] **Step 1: Write backfill tests** — `KadoTests/TodayBackfillTests.swift`. These pin the contract TodayView relies on: logging pinned to a past day lands on that day only.

```swift
import Foundation
import SwiftData
import Testing
@testable import Kado
import KadoCore

@Suite("Today backfill")
@MainActor
struct TodayBackfillTests {
    private let cal = TestCalendar.utc

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema(versionedSchema: KadoSchemaV7.self)
        return try ModelContainer(for: schema, migrationPlan: KadoMigrationPlan.self,
                                  configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true))
    }

    @Test("Toggling on a past day writes that day's completion")
    func toggleOnPastDay() throws {
        let ctx = try makeContainer().mainContext
        let habit = HabitRecord(name: "Read", frequency: .daily, type: .binary, createdAt: TestCalendar.day(-10))
        ctx.insert(habit)
        let past = cal.startOfDay(for: TestCalendar.day(-3))
        let instant = DayBoundary(calendar: cal).loggingInstant(for: TestCalendar.referenceDate, on: past)
        CompletionToggler(calendar: cal).toggleToday(for: habit, on: instant, in: ctx)
        let dates = (habit.completions ?? []).map(\.date)
        #expect(dates.count == 1)
        #expect(cal.isDate(dates[0], inSameDayAs: past))
    }

    @Test("A counter + on a past day changes only that day")
    func counterOnPastDay() throws {
        let ctx = try makeContainer().mainContext
        let habit = HabitRecord(name: "Water", frequency: .daily, type: .counter(target: 8), createdAt: TestCalendar.day(-10))
        ctx.insert(habit)
        let past = cal.startOfDay(for: TestCalendar.day(-2))
        let boundary = DayBoundary(calendar: cal)
        let logger = CompletionLogger(calendar: cal)
        logger.incrementCounter(for: habit, on: boundary.loggingInstant(for: .now, on: past), in: ctx)
        #expect(logger.value(for: habit, on: past) == 1.0)
        #expect(logger.value(for: habit, on: TestCalendar.referenceDate) == 0.0)
    }
}
```

Match `HabitRecord`'s init labels and the `.counter` case shape to `KadoSchemaV7.swift` / `HabitType.swift`.

- [ ] **Step 2: Run, expect PASS** (it pins existing behaviour; if it fails, stop and report — the logging contract differs from the spec's assumption).

- [ ] **Step 3: Edit `TodayView`.** Add state and derived values next to the other `@State`s:

```swift
    /// The day the list shows. `nil` means today, so the selection
    /// follows the rollover instead of sticking to yesterday.
    @State private var selectedDay: Date?

    private var displayedDay: Date {
        selectedDay.map { calendar.startOfDay(for: $0) } ?? today
    }

    private var dayKind: TodayDayKind {
        TodayDayKind(day: displayedDay, today: today, calendar: calendar)
    }

    private var stripDays: [Date] {
        let habitDates = activeHabits.flatMap { habit in
            [habit.createdAt] + (habit.completions ?? []).map(\.date)
        }
        let taskDates = activeTasks.map(\.createdAt)
        return DayStripRange.days(from: (habitDates + taskDates).min(), today: today, calendar: calendar)
    }

    private var stripSelection: Binding<Date> {
        Binding(
            get: { displayedDay },
            set: { newDay in
                selectedDay = calendar.isDate(newDay, inSameDayAs: today) ? nil : newDay
            }
        )
    }

    private func stripProgress(for day: Date) -> DayProgress {
        let habits = activeHabits.map(\.snapshot)
        let completions = Dictionary(
            activeHabits.map { ($0.id, ($0.completions ?? []).compactMap(\.snapshot)) },
            uniquingKeysWith: { first, _ in first }
        )
        return DayStripProgress.progress(
            on: day,
            isFuture: TodayDayKind(day: day, today: today, calendar: calendar) == .future,
            habits: habits, completions: completions,
            evaluator: frequencyEvaluator, calendar: calendar
        )
    }
```

`stripProgress` re-snapshots per cell; if the strip feels slow on device, hoist the snapshot into a `let` computed once per body pass and pass it into the closure.

In `body`, on `content` (before `.navigationTitle`), add:

```swift
                .safeAreaInset(edge: .top, spacing: 0) {
                    DayStrip(days: stripDays, selection: stripSelection, today: today, progress: stripProgress(for:))
                        .background(Color.kadoBackground)
                }
                .onChange(of: stripDays) { _, days in
                    if let selectedDay, let clamped = DayStripRange.clamp(selectedDay, to: days), clamped != selectedDay {
                        self.selectedDay = calendar.isDate(clamped, inSameDayAs: today) ? nil : clamped
                    }
                }
```

Replace `.navigationTitle(Text("Today"))` with `.navigationTitle(titleText)` and add:

```swift
    private var titleText: Text {
        dayKind == .today
            ? Text("Today")
            : Text(displayedDay, format: .dateTime.weekday(.abbreviated).month(.abbreviated).day())
    }
```

Add to `.toolbar { … }`:

```swift
                    if dayKind != .today {
                        ToolbarItem(placement: .topBarLeading) {
                            Button("Today") { selectedDay = nil }
                                .accessibilityIdentifier(AccessibilityID.Today.jumpToTodayButton)
                        }
                    }
```

`taskSections` becomes:

```swift
    private var taskSections: TaskDaySections {
        // Task planning uses civil days, while the habit rows use the
        // user's custom habit-day boundary.
        TaskDaySections.make(
            for: dayKind == .today ? civilToday : displayedDay,
            kind: dayKind,
            items: activeTasks.map { TaskListItem($0) },
            calendar: calendar
        )
    }
```

`sections` uses `on: displayedDay`. In `content`'s `List`:
- Wrap the rollover caption in `if dayKind == .today { … }`.
- Task sections:

```swift
                if !tasks.completed.isEmpty, dayKind == .past {
                    Section("Completed") { ForEach(tasks.completed) { taskRow($0) } }
                }
                if !tasks.due.isEmpty {
                    Section(taskDueHeader) { ForEach(tasks.due) { taskRow($0) } }
                }
                if dayKind == .today, !tasks.inbox.isEmpty { /* existing inbox section unchanged */ }
                if dayKind == .today, !tasks.completed.isEmpty {
                    Section("Tasks completed today") { ForEach(tasks.completed) { taskRow($0) } }
                }
```

with

```swift
    private var taskDueHeader: LocalizedStringKey {
        switch dayKind {
        case .today: "Tasks today & overdue"
        case .past: "Due"
        case .future: "Planned"
        }
    }
```

- Empty state: when every section is empty, `.today` keeps its current two texts; otherwise show `Text("Nothing on this day")` in the same styled `Section`.
- Habit sections: `.onMove` only when `dayKind == .today` (use `.onMove(perform: dayKind == .today ? { moveHabits(due, from: $0, to: $1) } : nil)`). On `.future` skip the "Not scheduled today" section; on `.past` its header reads "Not scheduled" (new key) and its footer stays.
- `switch card` block only when `dayKind == .today`.

In `row(_:)`: every `asOf: today` → `asOf: displayedDay`; callbacks:

```swift
                onToggle: dayKind.allowsHabitLogging && canToggle(item) ? { toggle(item.id) } : nil,
                onCounterIncrement: dayKind.allowsHabitLogging && isCounter(item) ? { incrementCounter(item.id) } : nil,
                onCounterDecrement: dayKind.allowsHabitLogging && isCounter(item) ? { decrementCounter(item.id) } : nil,
                onTimerAddFiveMinutes: dayKind.allowsHabitLogging && isTimer(item) ? { addFiveMinutes(item.id) } : nil,
                onLogSpecificValue: dayKind.allowsHabitLogging ? logSheetCallback(for: item) : nil,
                onOpenDetail: { path.append(HabitRoute(id: item.id)) },
                onEdit: { sheet = .editHabit(item.id) },
                onArchive: dayKind == .today ? { confirmingArchiveOf = item.id } : nil
```

and the swipe Undo: `if dayKind.allowsHabitLogging, canSwipeUndo(item, state: state)`.

`loggingInstant`: `dayBoundary.loggingInstant(for: .now, on: displayedDay)`.

`checkMilestones`: first line `guard dayKind == .today else { return }`.

`toggleTask`:

```swift
        record.completedAt = record.completedAt == nil
            ? (dayKind == .past ? dayBoundary.loggingInstant(for: .now, on: displayedDay) : .now)
            : nil
```

`sheetContent(.newTask)`: `TaskFormView(defaultDay: dayKind == .today ? nil : displayedDay)`.

`.logCounter`/`.logTimer` get the day in Task 7 — leave them for now.

- [ ] **Step 4: Strings** — insert with EN + FR + comment: "Completed" (fr "Terminées"), "Due" (fr "À faire"), "Planned" (fr "Prévues"), "Nothing on this day" (fr "Rien ce jour-là"), "Not scheduled" (fr "Pas prévue"). "Today" already exists — reuse it. Before inserting, `grep -n '"Completed"\|"Due"\|"Planned"' Kado/Resources/Localizable.xcstrings`; if a key exists with a different meaning, use a distinct key such as `"Completed that day"` instead of reusing it.

- [ ] **Step 5: Build, run the full `make test`, expect PASS.**
- [ ] **Step 6: Commit** — `feat(today): show and edit the day picked in the strip`

---

### Task 7: Log sheets write to the selected day

**Goal:** Counter and timer sheets opened from another day read and write that day.

**Files:**
- Modify: `Kado/Views/Today/CounterLogSheet.swift`, `Kado/Views/HabitDetail/TimerLogSheet.swift`, `Kado/Views/Today/TodayView.swift` (`TodaySheet`)
- Modify: `Kado/Resources/Localizable.xcstrings`

**Acceptance Criteria:**
- [ ] Both sheets take `var day: Date? = nil`; `private var logDay: Date { day ?? today }` replaces every `today` read (prefill lookup and `loggingInstant(for: .now, on:)`).
- [ ] When `day` is set and differs from `today`, the footer reads "Saves for %@" with the short date instead of the "today's completion" text.
- [ ] `TodaySheet.logCounter(UUID, Date)` / `.logTimer(UUID, Date)`; ids include the day; `logSheetCallback` passes `displayedDay`.
- [ ] Other callers of the sheets (Habit Detail) compile unchanged.

**Verify:** build succeeds; `make test` passes

**Steps:**

- [ ] **Step 1:** In each sheet add after the existing `let habit`:

```swift
    /// The habit day this sheet logs to. `nil` means today — the case
    /// for every caller except Today's day strip.
    var day: Date? = nil

    private var logDay: Date { day ?? today }
```

Replace `today` with `logDay` in `todayValue()`'s `calendar.isDate($0.date, inSameDayAs: today)` and in `dayBoundary.loggingInstant(for: .now, on: today)` (CounterLogSheet ~lines 115, 124; TimerLogSheet ~lines 107, 126).

- [ ] **Step 2:** Footer — wrap the existing footer `Text`:

```swift
                    if let day, !calendar.isDate(day, inSameDayAs: today) {
                        Text("Saves for \(day.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))")
                    } else {
                        Text("Saves as today's completion. Setting it to 0 clears today's progress.") // existing text, unchanged per sheet
                    }
```

Keep each sheet's existing text exactly; only add the branch.

- [ ] **Step 3:** `TodaySheet`:

```swift
        case logCounter(UUID, Date)
        case logTimer(UUID, Date)
        ...
            case .logCounter(let habitID, let day): "counter-\(habitID)-\(day.timeIntervalSinceReferenceDate)"
            case .logTimer(let habitID, let day): "timer-\(habitID)-\(day.timeIntervalSinceReferenceDate)"
```

`sheetContent`: `CounterLogSheet(habit: record, day: day)` / `TimerLogSheet(habit: record, day: day)`. `logSheetCallback`: `sheet = .logCounter(item.id, displayedDay)` / `.logTimer(item.id, displayedDay)`. Check that `CounterLogSheet`/`TimerLogSheet` use the memberwise init (no custom `init`); if one has a custom init, add a `day: Date? = nil` parameter to it.

- [ ] **Step 4:** String `"Saves for %@"` — comment "Log sheet footer when logging a day other than today; %@ is the short date"; fr `Enregistré pour le %@`.
- [ ] **Step 5:** Build, `make test`, expect PASS.
- [ ] **Step 6: Commit** — `feat(today): log counter and timer sheets to the selected day`

---

### Task 8: UI test

**Goal:** End-to-end: pick yesterday, log a habit, jump back to today.

**Files:**
- Create: `KadoUITests/TodayDayStripTests.swift`

**Acceptance Criteria:**
- [ ] Launch with `seedProduction: true`; tap yesterday's cell; title is not "Today"; tap the first row's trailing control; the row's accessibility value changes; tap the Today button; the Today button is gone.

**Verify:** `DEVELOPER_DIR=… xcodebuild test -project Kado.xcodeproj -scheme Kado -destination 'platform=iOS Simulator,name=Kado feat-today-day-strip' -derivedDataPath build -only-testing:KadoUITests/TodayDayStripTests` → passes

**Steps:**

- [ ] **Step 1: Write the test**

```swift
import XCTest

/// The day strip end to end: a strip cell is the only way to reach
/// another day, and the backfill tap happens inside a List row that a
/// unit test can't drive.
final class TodayDayStripTests: KadoUITestCase {

    @MainActor
    func testPickingYesterdayLogsThereAndTodayJumpsBack() {
        let app = launchApp(seedProduction: true)
        tapTab(.today, in: app)
        waitForTodayRows(in: app)

        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: .now)!
        let cell = app.buttons[AccessibilityID.Today.dayStripCell(yesterday)].firstMatch
        XCTAssertTrue(cell.waitForExistence(timeout: 5), "Yesterday's strip cell should exist.")
        cell.tap()

        let jumpBack = app.buttons[AccessibilityID.Today.jumpToTodayButton].firstMatch
        XCTAssertTrue(jumpBack.waitForExistence(timeout: 5), "Another day shows the Today button.")

        waitForTodayRows(in: app)
        let row = todayRows(in: app).firstMatch
        let before = row.value as? String
        // Trailing edge = the check / + control; the centre would push Detail.
        row.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
        let changed = NSPredicate { _, _ in (row.value as? String) != before }
        wait(for: [XCTNSPredicateExpectation(predicate: changed, object: nil)], timeout: 5)

        jumpBack.tap()
        XCTAssertFalse(jumpBack.waitForExistence(timeout: 2), "Back on today, the Today button goes away.")
        capture(app, "today-day-strip")
    }
}
```

`AccessibilityID` is in `Shared/`, which the UI test target already compiles (other UI tests use it). If `dayStripCell` uses `TimeZone.current` and the simulator and test runner agree (same machine), ids match.

- [ ] **Step 2: Run, expect PASS.** If yesterday has no listed habit in the seed, pick the day from `DevModeSeed` that has one and say so in the test comment.
- [ ] **Step 3: Commit** — `test(today): cover the day strip end to end`

---

### Task 9: Verification and docs

**Goal:** Prove it works and record it.

**Files:**
- Modify: `docs/ROADMAP.md` (one line under the current version's done items, matching the Health on Calendar note's style)

**Acceptance Criteria:**
- [ ] `make test` passes (same known issue count as `main`: 1).
- [ ] `make deployment-check` passes.
- [ ] Screenshots on the simulator: today, a past day, a future day — light and dark; and Dynamic Type XXXL (`xcrun simctl ui '<sim>' content_size accessibility-extra-extra-extra-large`). The strip numbers must not truncate.
- [ ] iPad build succeeds (`-destination 'platform=iOS Simulator,name=iPad Air 13-inch (M3)'` or the installed iPad).
- [ ] ROADMAP line added; commit.

**Verify:** command outputs above, screenshots saved to the scratchpad and looked at.

**Steps:**

- [ ] **Step 1:** Run the commands; look at each screenshot.
- [ ] **Step 2:** Fix any visual defect in the task that owns it (new commit).
- [ ] **Step 3:** Commit — `docs: note the Today day strip in the roadmap`
