# Now view — design

Date: 2026-10-04
Branch: `feature/now-view`

## Goal

A screen that shows exactly one thing: what to work on now. It tracks
real time on that one thing (start, pause, finish) and shows what comes
next.

```
NOW
Research
10:00–12:00

Started 10:17
48 min elapsed

[ Finish ]   [ Pause ]

Up next
Professor outreach — 14:00
```

## Decisions

| Question | Decision |
|---|---|
| What "Started" and "elapsed" record | Real tracked time, stored and synced (schema V8). |
| Where Now lives | First tab. Calendar moves into Today as a List / Calendar switch. |
| What Now shows with no session open | It suggests the right block: the current one, else the next one, else "Start something…". |
| What Finish does | It ends the session and asks: Done, Not yet, or Cancel. |
| Storage shape | One record per session; pauses are added up into one total. |
| AI suggestion | Phase 2, on Apple's on-device model. Phase 1 ships without it. |

## Navigation

Tabs become: **Now · Today · Goals · Overview · Settings** (still 5, so
iPhone shows no "More" tab).

- `NowView` is the first tab.
- The Calendar tab is removed. `TodayView` gets a segmented List /
  Calendar switch at the top. The calendar side shows the existing
  `PlannerCalendarView` content. The choice is kept in
  `@AppStorage`.
- The day strip (`DayStrip`, from the Today day strip work) stays above
  both sides, and both show its `selectedDay`: List shows that day's
  habits and tasks, Calendar shows that day's timeline. The calendar's
  own day navigation is replaced by the strip, so there is one day
  picker, not two.
- `AccessibilityID.Tab` positions and SF Symbols change with the tab
  order; the UI tests that open the Calendar tab change to open Today
  and select Calendar.

## Data: `WorkSessionRecord` (KadoSchemaV8)

`ScheduleBlockRecord` stays a plan only ("These dates never represent
actual tracked time"). Tracked time gets its own record.

```swift
@Model
public final class WorkSessionRecord {
    public var id: UUID = UUID()
    public var startedAt: Date = Date()
    public var endedAt: Date?          // nil while open
    public var pausedAt: Date?         // set while paused
    public var pausedSeconds: Double = 0 // total of finished pauses
    public var createdAt: Date = Date()
    public var updatedAt: Date = Date()
    public var task: TaskRecord?
    public var habit: HabitRecord?
    public var scheduleBlock: ScheduleBlockRecord?
}
```

- V8 is additive: one new model plus inverse relationships on
  `TaskRecord`, `HabitRecord` and `ScheduleBlockRecord` (optional,
  delete rule `.nullify` from the block, `.cascade` from task and
  habit). Lightweight migration from V7; CloudKit-compatible (all
  properties have defaults, relationships optional).
- A session links to a task or a habit; `scheduleBlock` is set when
  the session started from a planned block.
- **One open session** (`endedAt == nil`) at a time. `WorkSessionTracker`
  enforces it; if sync brings a second open session from another
  device, the one started earlier is shown and the other is listed as
  "Also running" with Finish.

Schema bump follows the CLAUDE.md checklist (new `KadoSchemaV8` file,
migration plan, typealiases, both production factories, schema tests,
V7 → V8 migration test). Two more steps:

- **Backup**: JSON export/import and CSV export include sessions, with
  a round-trip test (the user must be able to extract 100% of their
  data).
- **CloudKit**: deploy the V8 schema to Production in the CloudKit
  Console before the next TestFlight/App Store build (PR "Next steps").

A pure value type in KadoCore does the arithmetic:

```swift
public struct WorkSession: Sendable, Equatable {
    public var startedAt: Date
    public var endedAt: Date?
    public var pausedAt: Date?
    public var pausedSeconds: TimeInterval

    /// Worked time: (end or now) − start − pauses, including an open pause.
    public func elapsed(at now: Date) -> TimeInterval
    public var isPaused: Bool { pausedAt != nil && endedAt == nil }
}
```

## Units

| Unit | Layer | Job |
|---|---|---|
| `WorkSession` | KadoCore value | Elapsed time and paused state. |
| `NowResolver` | KadoCore, pure | Input: now, the day start hour, today's blocks, the open session, open tasks and today's pending habits. Output: `NowState` (below) and "Up next". No SwiftData, no UI. |
| `WorkSessionTracker` | App service, SwiftData | `start(block:)`, `start(task:)`, `start(habit:)`, `pause()`, `resume()`, `finish(markDone:)`, `cancel()` (deletes a session the user started by mistake). All writes go here. |
| `NowView` | UI | Renders `NowState`. Live time via `Text(timerInterval:)`/`TimelineView`, no app timer. |
| `TodayView` | UI change | List / Calendar switch. |

```swift
/// What a session or block is about, as a value: views address records
/// by UUID and never hold a `@Model` (CLAUDE.md, issue #63).
public enum NowItem: Equatable, Sendable {
    case task(id: UUID, title: String)
    case habit(id: UUID, name: String, type: HabitType)
}

public enum NowState: Equatable {
    case running(NowItem, WorkSession, plannedRange: ClosedRange<Date>?)
    case paused(NowItem, WorkSession, plannedRange: ClosedRange<Date>?)
    case suggestedCurrent(NowItem, plannedRange: ClosedRange<Date>)  // planned now, not started
    case suggestedNext(NowItem, plannedRange: ClosedRange<Date>)     // next block today
    case empty                                                    // nothing left today
}
// Plus: upNext: (NowItem, start: Date)? — the next timed block after the shown one.
```

### Resolver rules

1. An open session wins over any plan.
2. Else, a timed block whose range contains now → `suggestedCurrent`.
   Overlapping blocks: the earlier start wins, then the earlier
   created.
3. Else, the next timed block later today → `suggestedNext`.
4. Else `empty`.
- "Today" follows the "Day starts at" hour (`DayStartDefaults`).
- Blocks without a start time are never suggested; they appear in
  "Start something…".
- Skipped: completed or archived tasks, cancelled imported events,
  archived habits, habits already done today, and negative habits
  (there is nothing to work on for "avoid X").
- A block with a start but no end is treated as one hour long
  (`ScheduleDefaults`).

## Screen states

**Running**

```
NOW
Research
10:00–12:00
Started 10:17
48 min elapsed
━━━━━━━━━━░░░░░  72 min left      ("12 min over" past the planned end)
[ Finish ]   [ Pause ]
Up next
Professor outreach — 14:00
```

**Paused**: "Paused · 48 min so far"; Pause becomes **Resume**; the
count stops.

**Suggested (current / next)**

```
NOW                          NEXT
Research                     Professor outreach
10:00–12:00                  14:00–15:00
Planned 17 min ago           In 2 h 10 min
[ Start ]                    [ Start early ]
```

**Empty**: "Nothing planned for the rest of today" and
**Start something…**, which lists open tasks (untimed and unscheduled
included) and today's pending habits.

### Interactions

- **Finish** ends the session (`endedAt = now`, an open pause is
  closed first) and shows a dialog:
  - **Done**: the task gets `completedAt`; a habit gets a completion
    for today. A timer habit's completion value is the session's worked
    seconds. A counter habit gets one unit.
  - **Not yet**: the session is kept; the task stays open.
  - **Cancel**: nothing changes; the session keeps running.
- **Start while another session is open**: a dialog asks to finish the
  open one first (same Done / Not yet choices).
- Nothing stops by itself at the planned end.
- Tapping the title opens the task or habit detail.
- Imported Google Calendar tasks work like local ones; Done marks only
  the local task, as today.
- Accessibility: one VoiceOver sentence per state ("Research, started
  10:17, 48 minutes elapsed"); buttons stack at accessibility text
  sizes; every control has an `AccessibilityID.Now` identifier.
- EN and FR strings in `Localizable.xcstrings`.

## Phase 2: suggestion with Apple Intelligence

Applies to the gap and empty states. Phase 1 already ranks candidates
with code; phase 2 lets the on-device model choose among them and give
a reason.

```
Free until 15:30 (85 min)
Suggested: Professor outreach email
"Due tomorrow and fits your free hour."
[ Start ]   [ Something else… ]
```

- `SuggestionRanker` (KadoCore, pure, phase 1): scores open tasks and
  pending habits by due date, fit in the free time, and habit streak;
  returns the top 3–8 candidates with a fixed reason each ("Due
  tomorrow").
- `NextSuggesting` protocol, injected through the environment like
  `TextCleaning`. `RankedNextSuggester` returns the top candidate.
  `FoundationModelsNextSuggester` (iOS 26) sends the short candidate
  list and gets a `@Generable` answer:

  ```swift
  @Generable
  struct NextSuggestion {
      @Guide(description: "ID of one candidate from the list")
      var candidateID: String
      @Guide(description: "One short sentence on why, under 15 words")
      var reason: String
  }
  ```

- An ID not in the list, an error, or no model → the ranked top
  candidate with its fixed reason. The model never sees more than the
  candidate list (titles, due dates, durations, streak), and it runs on
  device; `PRIVACY.md` gets one line.

## Out of scope

- Live Activity / Lock Screen timer (on the roadmap; builds on
  `WorkSessionRecord` later).
- Stats on tracked time (planned vs. actual).
- Editing past sessions.
- Widgets.

## Testing

| Level | Covers |
|---|---|
| Unit `WorkSession` | Elapsed while running, paused, after resume, finished. |
| Unit `NowResolver` | Current block, gap, next block, end of day, overlap order, untimed blocks, start without end, past the planned end, day start hour, skipped items. |
| Unit `WorkSessionTracker` (in-memory SwiftData) | One open session; finish Done vs Not yet; habit completion; timer habit seconds; cancel. |
| Migration | A V7 store opens as V8 with data intact; `CloudKitShapeTests` cover the new model. |
| Backup | Sessions survive a JSON export → import round trip and appear in CSV. |
| Unit `SuggestionRanker` (phase 2) | Order and fixed reasons; unknown model ID falls back. |
| UI | Start → Pause → Resume → Finish → Done; Today List / Calendar switch; updated tab positions. |
