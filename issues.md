# Personal Planning App Backlog

This backlog evolves the Kadō fork (`kbKenz/kado`) into a personal planning and life-tracking app. The app is native iOS using SwiftUI, SwiftData, CloudKit, WidgetKit, and App Intents. The existing persistent model is primarily `HabitRecord` + `CompletionRecord`; SwiftData/SQLite is the live store, and JSON/CSV are portability formats.

## Implementation principles

- Habit and task completion records remain the source of truth.
- `ScheduleBlock` represents planned time only; it does not duplicate completion state.
- `TimeEntry` represents actual time separately from planned time.
- Build the internal calendar first; Apple Calendar integration comes much later.
- Preserve strong export/import, migrations, retrospective history, and privacy architecture.
- Suggested phases: core tasks/Today/calendar (1–6), goals/retrospective (7–10, 14), time tracking/analytics (11–13), then export/search/tags/integrations (15–18).

## 1. Rename fork infrastructure for independent app identity

**Description and scope:** Give the fork an independent product identity while preserving provenance and existing data continuity. Update display name, bundle identifiers, URL schemes, assets, and target/project names where appropriate. Review CloudKit container, entitlements, App Group, widget, and App Intents identifiers to avoid collisions with upstream. Document Apple Developer/CloudKit setup and define a migration or compatibility path where identifiers affect storage.

**Acceptance criteria:** App, widgets, and intents use the new identity consistently; runtime identifiers do not unintentionally collide with upstream Kadō; CloudKit/App Group setup is documented; existing local data remains readable or has a documented migration path.

## 2. Add one-off Task model and task persistence

**Description and scope:** Add a SwiftData `Task` model alongside recurring habits, with stable identity, title, optional notes, due date, priority/status, and created/updated timestamps. Support create, edit, complete, reopen, and delete. Keep task completion distinct from habit completions and plan schema migration/CloudKit compatibility.

**Acceptance criteria:** Tasks persist across relaunch and sync through configured persistence; CRUD and completion state remain consistent after edits/relaunch; existing habit data is unaffected; migration from current stores is defined.

## 3. Build a unified Today view for habits and tasks

**Description and scope:** Show today's habits and due tasks together with clear type-specific controls and completion state. Add quick completion, task creation, and detail navigation. Handle empty states, overdue tasks, and local calendar boundaries. Do not create a separate Today completion store.

**Acceptance criteria:** Today's habits and tasks appear together and remain distinguishable; completion updates canonical records and persists; overdue/empty states are clear; the selected local calendar day is respected.

## 4. Add ScheduleBlock model for planned time blocks

**Description and scope:** Add a SwiftData `ScheduleBlock` with stable identity, start/end, optional title/notes, and optional habit/task link. Support standalone and linked blocks, editing, moving, and deletion. Define range validation, overlap behavior, migrations, and CloudKit compatibility.

**Acceptance criteria:** Blocks persist and can be edited independently of completion; they may link to a habit/task or stand alone; completing or missing a linked item never mutates plan state; invalid ranges are prevented and existing data remains intact.

## 5. Add Calendar tab with day timeline

**Description and scope:** Add an internal calendar tab with date navigation and a time-scaled day timeline. Show planned blocks and due items while distinguishing plan from completion. Support creating, editing, and moving blocks. Build this internal calendar before external providers.

**Acceptance criteria:** Users can navigate dates and see that day's blocks on a readable timeline; blocks can be created/edited from the calendar; linked completion is read from canonical records; empty days, all-day/untimed items, and time-zone changes behave predictably.

## 6. Connect calendar completion with habit/task completion

**Description and scope:** Add completion actions for linked items in calendar surfaces and reflect changes made elsewhere. Define behavior for multiple blocks linked to one item and repeated habit occurrences. Never store duplicate completion state on a ScheduleBlock.

**Acceptance criteria:** Calendar completion updates canonical habit/task data; changes made elsewhere appear without stale duplicate state; a block remains planned when its item is completed, missed, or reopened; multiple blocks do not create duplicate completion events.

## 7. Add Goals and link tasks/habits to goals

**Description and scope:** Add a persistent `Goal` model with name, description, status, dates, and timestamps. Allow optional task/habit links with explicit relationship semantics. Provide goal create/edit/archive and detail views; preserve relationships through migration and export/import.

**Acceptance criteria:** Goals persist and can be created, edited, and archived; users can link/unlink tasks and habits; goal detail accurately lists linked items and status; deletion has documented, non-destructive relationship behavior.

## 8. Add measurable goal progress

**Description and scope:** Support numeric targets, units, optional baselines/deadlines, manual progress, and derived progress from linked canonical records where appropriate. Show current progress/history and prevent double-counting.

**Acceptance criteria:** Measurable goals store unit/target and display progress; manual and derived rules are explicit; multiple links or schedule blocks do not double-count completions; invalid values and target changes are handled consistently.

## 9. Add Areas of Life

**Description and scope:** Add a persistent `Area` model with name, optional description/color/icon, and ordering. Allow goals, habits, and tasks to be assigned/reassigned and browsed by area. Define safe archive/deletion behavior and include areas in migration and export/import.

**Acceptance criteria:** Areas can be created, renamed, reordered, and safely archived/deleted; supported records can be assigned and filtered; unassigned records remain valid; relationships survive relaunch and migration.

## 10. Add daily retrospective / day history screen

**Description and scope:** Review what was planned and what happened on a selected day. Show historical habit/task completion from canonical records, planned blocks separately, and related notes/time entries when available. Navigate past dates and respect local-day boundaries without rewriting history.

**Acceptance criteria:** A past date shows its historical habit/task outcomes; planned blocks are distinct from outcomes; empty/partial history is handled; reviewing a day does not mutate records.

## 11. Add TimeEntry model for actual time tracking

**Description and scope:** Add `TimeEntry` with start/end or duration, optional note, and optional task/habit link. Support manual entry, edit, and delete, including entries spanning midnight. Define overlap/duration validation and include migration/export/import support.

**Acceptance criteria:** Actual entries persist independently from planned blocks; entries can be linked or standalone; cross-midnight durations and local-day summaries are consistent; editing/deleting an entry never changes blocks or completion state.

## 12. Add start/stop timer for tasks

**Description and scope:** Start/stop timing from task surfaces, show elapsed time, and persist running state across app termination/restart. Define behavior for starting another timer, task edits, and midnight. Make resulting entries reviewable and editable.

**Acceptance criteria:** Start/stop creates one accurate linked TimeEntry; a running timer resumes after relaunch; conflicting timers follow a clear single-timer policy; timer activity never completes a task automatically.

## 13. Add weekly/monthly/yearly analytics

**Description and scope:** Summarize habit/task completion, planned time, and actual tracked time for weeks, months, and years. Derive completion from canonical records, planned time from ScheduleBlocks, and actual time from TimeEntries. Provide drill-down; handle incomplete history, time zones, and archived records. Keep analytics local and privacy-preserving.

**Acceptance criteria:** Week/month/year summaries use correct calendar boundaries; planned and actual time are separate; completion rates use canonical records; metrics can be traced to records and empty periods render clearly.

## 14. Add standalone Day Note / journal

**Description and scope:** Add a private `DayNote`, independent of habits/tasks/time tracking, keyed by local calendar day with editable text and timestamps. Provide entry from Today and day history. Define time-zone/device behavior and preserve notes in migrations and full export/import.

**Acceptance criteria:** Users can create/edit/reopen one daily note per local day; notes are accessible from Today/history; day-key behavior across time-zone changes is consistent and documented; notes survive relaunch and export/import round trips.

## 15. Extend JSON and CSV export/import for all new entities

**Description and scope:** Extend versioned JSON export/import for tasks, blocks, goals/progress, areas, day notes, time entries, tags, and relationships as implemented. Define CSV schemas for tabular entities with stable IDs/references. Preserve existing HabitRecord/CompletionRecord formats, validate input, report partial failures, and preserve atomicity/privacy guarantees.

**Acceptance criteria:** Existing JSON/CSV exports remain importable; JSON round trips preserve supported entities, IDs, links, and history; CSV schemas document columns and contain identifiers for supported relationships; invalid input produces actionable errors without corrupting the live store.

## 16. Add global search

**Description and scope:** Add local search across habits, tasks, goals, areas, blocks, notes, and time-entry notes as implemented. Provide type-aware results and navigation to details/date context, sensible matching, and clear empty/no-match states. Avoid unnecessary duplicate indexes.

**Acceptance criteria:** Search finds records across supported types; selecting a result opens the correct detail/context; empty/no-match states are clear; search uses local persistence and exposes no data externally.

## 17. Add tags and filtering

**Description and scope:** Add reusable persistent tags and many-to-many relationships for relevant habits, tasks, goals, blocks, and notes. Support tag creation, rename, color, removal, and filtering in Today/history/search. Define deletion, migration, and export/import behavior.

**Acceptance criteria:** Tags are reusable and centrally editable; filtering by one or more tags has predictable combination rules; removing a tag never deletes records; links survive relaunch and full export/import round trips.

## 18. Explore optional Apple Calendar integration

**Description and scope:** After the internal calendar is established, evaluate EventKit read-only and write/sync use cases, authorization UX, privacy, conflicts, and platform requirements. Recommend importing external events, exporting ScheduleBlocks, or both. Define deduplication/mapping without making Apple Calendar the completion source of truth.

**Acceptance criteria:** A design note compares modes and tradeoffs; it defines permissions, conflict/deduplication behavior, and user controls; the internal calendar and canonical completion remain authoritative; no production EventKit sync ships before review of the proposal.
