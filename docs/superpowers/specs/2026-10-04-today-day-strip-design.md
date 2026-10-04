# Today day strip — design

**Status:** approved in conversation, 2026-10-04
**Branch:** `feat/today-day-strip`

## Goal

Let the user look at any day from the Today tab: what they completed in the
past, and what is planned for the future. A horizontal day strip at the top of
Today, like the date scrubber in sleep-score apps, selects the day.

## Decisions

| Topic | Decision |
|---|---|
| Control | A scrolling day strip with a progress ring per day (not a week pager) |
| Past days | Show and edit: tick off a missed habit or task (backfill) |
| Future days | Show tasks and habits; tasks can be completed early or edited; **habits are view-only** |
| Strip range | From the earliest habit or task creation day to 60 days after today |
| Ring | Habits only, through the existing `DayProgress` (tasks are not in the ring) |
| Approach | `TodayView` shows a `selectedDay` instead of always `today`. No new tab, no per-day page view |

Approaches not used:

- **Separate History screen.** Duplicates every list and action of Today.
- **Paged full-screen days.** Builds a whole list per page, and its horizontal
  swipe fights the row swipe actions (complete, delete).

## User experience

### Day strip (`DayStrip`)

- Pinned under the navigation bar of Today, above the list.
- A lazy horizontal `ScrollView` with `.scrollTargetBehavior(.viewAligned)`.
- Each cell: weekday letter, day number, small ring with that day's
  `DayProgress.fraction`. A day with nothing due shows a dot, not an empty
  ring. Future days show an empty ring (nothing can be done yet).
- The selected cell has an accent fill. The today cell has an accent number
  when it is not selected.
- Tap a cell to select it. The strip opens on today, and scrolls to today
  again when the user taps **Today**.
- Accessibility: each cell is a button with label "Saturday, October 4",
  value "3 of 5 habits done", and the `.isSelected` trait when selected.
  Identifier on each cell (a leaf): `today.dayStrip.<yyyy-MM-dd>`, through a
  new `AccessibilityID.Today.dayStripCell(_:)`.
- The weekday letter comes from `Weekday.localizedShort`, not from new
  catalog keys.
- Dynamic Type: cells grow with the text; at accessibility sizes the strip
  shows fewer cells, it does not truncate the number.

### Title and toolbar

- Title is "Today" when `selectedDay` is today; otherwise the short date,
  for example "Sat, Oct 4".
- A **Today** toolbar button shows only when another day is selected. It
  selects today and scrolls the strip back.
- The **Add** menu stays. A task made from a future day gets that day as its
  due date. A habit is made as before.

### What a day shows

| | Past day | Today (no change) | Future day |
|---|---|---|---|
| Tasks | "Completed" (completed that day), then "Due" (due or scheduled that day, still open) | Due and overdue, inbox, completed today | "Planned" (due or scheduled that day, open and completed) |
| Habits | "Habits" (due or logged that day), "Not scheduled" | Same as now | "Habits" (due that day), view-only |
| Inbox | Hidden | Shown | Hidden |
| Rollover caption, notice cards | Hidden | Shown | Hidden |

- Overdue tasks show only on today, as now. A past day does not list tasks
  that became overdue later.
- A habit shows on a day only when the day is on or after the habit's first
  day: the earlier of its `createdAt` day and its `effectiveStart`. So Today
  never logs a day before a habit's start. That case keeps its warning in
  Overview and Habit Detail (issue #104).
- Archived habits and tasks are not shown on any day. This is the same as
  today's `@Query` filters.
- An empty day shows "Nothing on this day" for past and future days. Today
  keeps its present empty text.

### Actions on another day

- **Habits, past day:** tap to toggle, `−` / `+` / `+5m`, and the counter and
  timer sheets, all write to the selected day through
  `dayBoundary.loggingInstant(for: .now, on: selectedDay)`.
- **Habits, future day:** rows are not tappable for logging; they still open
  Habit Detail. No swipe actions.
- **Tasks:** on a past day, toggle sets `completedAt` to the selected day at
  the current clock time. On today and future days it sets `.now` (a task
  done early was done now); the task stays on its future day with a tick.
  Untoggle clears it. Edit and delete work as now.
- The confetti and the review-prompt milestones fire only for today.

## Architecture

### KadoCore

- `DayStripRange` — `nonisolated public enum` (no cases).
  `days(from earliest: Date?, today: Date, futureDays: Int = 60, calendar:)`
  returns the start-of-day dates. Empty data gives `today` and the future
  range. DST safe (`calendar.date(byAdding: .day)`, never `86_400`).
- `DayStripProgress` — computes the `DayProgress` for one day from habit and
  completion snapshots, with the same rule as Today's due section
  (`isDueOrLogged`, `HabitRowState.isDone(for:)`, the first-day rule above).
  `TodayView` and `DayStrip` both read it, so the ring and the list agree.

### App target

- `TodayDayKind` — `.past`, `.today`, `.future`, from `selectedDay` and the
  habit-day `today`.
- `TaskDaySections` — next to `TaskListItem`. Pure function:
  `sections(for day:, kind:, items:, now:, calendar:)` returns the task
  sections for the table above. Today's branch is the present
  `taskSections` logic, moved here without a change in behaviour.
- `TodayRow.sections(from:on:...)` gets the first-day filter.
- `DayStrip` view and `DayStripCell` view, in `Kado/Views/Today/`.
- `TodayView`:
  - `@State private var selectedDay: Date?` (`nil` means today, so the
    selection follows the rollover at midnight).
  - Every `today` used for sections, state, logging and milestones is replaced
    by `displayedDay`, except where the table says "today only".
  - `TodaySheet.logCounter` and `.logTimer` carry the day.
- `CounterLogSheet` and `TimerLogSheet` get a `day: Date` parameter, default
  `today`; their text says "Saves for Sat, Oct 4" when the day is not today.
- Day identity for tasks uses the civil calendar (as the Calendar tab).
  Day identity for habits uses the habit-day boundary (as now).

## Localization

New EN keys with FR translations and a `comment` each, in
`Localizable.xcstrings` (insertions only): "Nothing on this day",
"Completed", "Due", "Planned", "Saves for %@", the **Today** button, and the
cell accessibility value ("%lld of %lld habits done", with plural variants).
`LocalizationCoverageTests` must pass. FR strings need a native-speaker review
before release.

## Error handling

- Saves keep the present pattern: `try modelContext.save()`, rollback and
  the alert for tasks; widgets reload after each habit write.
- If `selectedDay` falls outside the strip range after data changes, it is
  clamped to the nearest day in the range.

## Testing

Unit tests (Swift Testing, `KadoTests` and `KadoCoreTests`):

- `DayStripRange`: no data, earliest in the past, DST days (Paris fall
  2026-10-25, Havana midnight spring-forward 2026-03-08), future limit.
- `DayStripProgress`: due and done counts; negative habit; a day before the
  habit's first day; a day with nothing due gives `.empty`.
- `TaskDaySections`: past day (completed and still-open), today (same output
  as the old code), future day, tasks with schedules across midnight.
- `TodayRow.sections` first-day filter.
- Backfill: toggling on a past day writes a completion on that day; a counter
  `+` on a past day adds to that day's value only.
- `TodayDayKind` across the rollover hour.

UI test (`KadoUITests`):

- Open Today, tap yesterday's cell, tick a habit, check that the cell's
  accessibility value changes, tap **Today**, and check that the title is
  "Today".

## Out of scope

- Tasks in the ring.
- Showing archived habits or tasks on past days.
- Swiping the list itself to change days.
- Health blocks on Today (they stay on the Calendar tab).
