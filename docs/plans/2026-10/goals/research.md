# Research — Goals linked to tasks and habits

**Date:** 2026-10-04
**Status:** Implemented; numeric progress added in feature 8
**Related:** Fork backlog, feature 7 in `issues.md`; task/calendar implementation.

## Problem

The local fork now has habits, tasks, Today, and a Calendar timeline. It needs a way to connect that daily work to longer-term goals, while retaining the canonical task/habit completion records and full export.

The user's fork direction supersedes upstream PRODUCT.md's habit-only scope. The next phase in the fork backlog starts with Goals. Numeric targets and measurable progress were added as feature 8.

## Codebase findings

- The initial Goals implementation used V6; measurable progress adds V7, with HabitRecord, CompletionRecord, TaskRecord, and ScheduleBlockRecord. Production, dev, widgets, and previews need the same current schema.
- JSON/CSV format 2 retains planning entities and reads earlier habit-only files.
- Task forms use UUIDs and draft values, and imported Google event fields remain source-owned.
- Habit forms currently retain a managed editing record. Adding goal linking should also resolve the edited habit by UUID from the current store.
- Five standard SwiftUI tabs can expose Goals directly between Calendar and Overview.

## Chosen relationship semantics

Each task or habit has one optional goal. A goal can contain many tasks and habits. This provides a clear assignment/reassignment flow and leaves room for richer relationships if requested later.

Both inverse relationship sides are optional for CloudKit. Goal deletion nullifies those links and preserves items, completion history, and planned blocks. Archiving a goal preserves its links and is reversible. Goal status is chosen manually; completing a linked task does not complete its goal.

## Implementation

- Schema V6 copies V5's model bodies and adds GoalRecord plus optional owner links, with a lightweight V5 → V6 migration.
- Goals contain name, details, active/paused/completed status, optional start/target dates, completion/archive dates, and created/updated timestamps.
- A Goals list, form, and detail screen support creation, edits, linking/reassignment, archive/restore, and confirmed safe deletion.
- Task and habit forms include the same goal picker. Imported Google tasks can edit this local assignment while their source fields remain read-only.
- JSON/CSV format 3 carries goals and owner UUID references. Older imports preserve already-existing goal assignments because those formats had no goal field.

## Alternatives

Many-to-many links were considered, but would add assignment and future progress aggregation rules before they are needed. A Settings-only Goals list would be less discoverable for the planning app's next main workflow.

## Native verification constraint

Native migration, persistence, and UI tests passed on Xcode 26.5 simulators. Production CloudKit schema deployment and French wording review remain release checks.
