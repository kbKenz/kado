# Goals implementation

**Date:** 2026-10-04
**Repository:** `kbKenz/kado`
**State:** Prepared on `feature/goal-progress` for push.
**Scope:** Backlog feature 7, Goals linked to tasks and habits. Selected as the next phase after Tasks, Today, and Calendar.

## What changed

- Added a Goals tab between Calendar and Overview. Goals are grouped by active, paused, completed, and archived status.
- Added goal creation and editing with name, description, manual status, and optional start/target dates. Target dates cannot precede start dates.
- Added goal details with linked task and habit history, canonical completion controls, and navigation to item details.
- Added goal selection to task and habit forms. A task or habit can belong to one goal; a goal can contain many items. The picker can create a new goal directly.
- Added linking, reassignment, and unlinking from goal details. Reassignment confirms the source goal and rejects a changed assignment while the dialog is open.
- Added reversible goal archive/restore. Deleting a goal requires confirmation and removes its links while preserving tasks, habits, completions, and planned blocks.
- Enabled local goal assignment on Google Calendar tasks. Event details and times remain managed by Google, and synchronization preserves the local goal link.
- Added V6 persistence models and a lightweight V5 → V6 migration. Historical schema bodies remain frozen; current app, widget, preview, and support containers use V6.
- Extended JSON and CSV backups to format 3 with goal records and owner-to-goal IDs. Import previews now include goal counts.
- Added contextual English/French catalog entries. Existing translations were preserved; new French text is marked for native review.
- Extended goals with optional manual, completed-task, and single-habit numeric progress, dated manual history, and progress presentation on goal list/detail screens.
- Added V7 schema and V6 → V7 migration; JSON/CSV format 4 preserves measurement settings and manual entries through export/import.

## Persistence and completion

`GoalRecord` stores its ID, name, description, status, optional dates, creation/update timestamps, completion timestamp, and archive timestamp. Nullable inverse relationships connect it to tasks and habits, with nullify deletion rules compatible with the existing CloudKit model constraints.

Goal status is chosen by the user. Task completion remains `TaskRecord.completedAt`; habit completion remains completion history. Planned blocks and goal status do not manufacture completions. Archived and cancelled linked items remain visible as history, with task completion disabled for those items.

Views retain IDs or value snapshots. Saves resolve records from the current store, report missing records, and roll back failed persistence writes. The habit form now follows this same pattern instead of retaining its editing SwiftData record.

## Backup compatibility

- JSON writes format 3 with a `goals` collection and optional `goalID` on tasks/habits.
- Formats 1 and 2 remain readable. Merging those older files preserves existing goal assignments because their format cannot express an assignment change.
- CSV writes 43 columns, including goal entities and linked goal IDs. Its decoder accepts the exact historical 16-column and 36-column headers as well as the current header.
- Current-format imports validate goal data and owner references before mutation, merge goals by ID, and then restore item links. Failed saves roll back the import.

## Checks performed

| Check | Result and scope |
| --- | --- |
| Independent source review | No remaining definite issues in the Goals scope. Covered schema relationships, navigation/API call sites, reassignment, archive/delete, backup compatibility, and Google link preservation. |
| Native tests | 808 tests in 83 suites passed on Xcode 26.5 / iOS 26.5 simulator, with one pre-existing known SwiftData observation issue. Focused manual-progress UI test passed on iPhone 16 Pro and iPad Pro 13-inch. |
| Deployment and project checks | iOS 18 deployment check and `plutil -lint` passed. |
| Portable Swift 6 library compilation | Passed for 18 production domain/backup source files plus a wire-compatible `HabitColor` shim. Covers the actual goal/domain and JSON/CSV DTO/coder sources. Existing redundant `public` warnings in `Weekday` remain. |
| Project/property lists | `plutil -lint` passed for the project and app Info.plist. |
| Localization catalog | JSON parsed; 79 additions retain contextual metadata and French review state; earlier catalog entries were preserved. |
| Diff whitespace | `git diff --check` passed. |

Native simulator validation is complete for the combined change. Production CloudKit schema deployment remains a release step; the new French wording still needs review.

## Remaining release checks

Production CloudKit schema deployment is required before distributing this schema change. Local simulator tests do not establish production CloudKit synchronization. Review the new French wording before release.

## Source map

- UI: `Kado/Views/Goals/`, `Kado/Views/ContentView.swift`
- Item forms: `Kado/Views/Tasks/TaskFormView.swift`, `Kado/Views/NewHabit/NewHabitFormView.swift`, `Kado/ViewModels/NewHabitFormModel.swift`
- Persistence: `Packages/KadoCore/Sources/KadoCore/Models/Persistence/KadoSchemaV7.swift`, `KadoMigrationPlan.swift`
- Domain: `Packages/KadoCore/Sources/KadoCore/Models/GoalStatus.swift`, `Habit.swift`
- Backup: `Packages/KadoCore/Sources/KadoCore/Backup/`, `Kado/Views/Settings/BackupSection.swift`
- Navigation/accessibility: `Shared/AccessibilityID.swift`
- Planning: [research.md](research.md), [plan.md](plan.md)
