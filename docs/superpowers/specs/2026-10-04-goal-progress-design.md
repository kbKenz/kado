# Measurable goal progress

Date: 2026-10-04
Status: Proposed for written-spec review
Scope: Fork backlog item 8. Builds on the local Tasks, Calendar, and Goals implementation.

## Intent and constraints

The user selected measurable goal progress as the next feature and approved manual logging, completed-task counting, and summing one selected habit. Goals should connect daily work to a numeric outcome while preserving canonical completion history. Existing work remains intact. Native builds and simulator verification are deferred at the user's request; portable tests must distinguish their coverage from native validation.

## Product behavior

Measurement is optional. Existing goals remain unmeasured. Enabling it adds a baseline (default zero), target, unit, and one progress mode. Existing optional start and target dates serve as the measurement period and deadline.

Current value equals baseline plus contributions. Target must exceed baseline; both must be finite and nonnegative. Progress is `(current - baseline) / (target - baseline)`. The bar is clamped to 0–100%, while the displayed value can exceed the target. Reaching the target never changes the manually selected goal status.

The measurement period includes the goal's start day when specified and runs through today. A deadline is informational and does not stop counting later progress. Future-dated contributions are excluded until their day arrives. Habit dates retain their stored logical-day semantics; task timestamps and manual entries use civil calendar days, matching their existing surfaces.

### Manual mode

Users add a dated amount with an optional note from goal detail. Amounts are finite and positive. Current value is baseline plus the sum of entries in the measurement period. Entries have stable IDs, creation/update timestamps, and an owning goal. History supports editing and confirmed deletion; correcting an amount changes the original entry instead of recording a second contribution. Archived goals show history but require restoration to change measurement or entries.

### Tasks mode

Each currently linked completed task contributes one, identified by task ID. Reopening a task removes its contribution; changing completion date moves it in history. Completed archived or remotely cancelled tasks remain counted as historical work. Unlinking, reassignment, or deletion removes that task from this goal's derived total. The UI explains that this mode reflects current assignments. Unit is fixed to tasks. Planned blocks never contribute.

### Habit mode

Select one currently linked counter or timer habit. Counter mode sums its positive completion values and uses a user-specified unit. Timer mode sums recorded seconds and displays minutes by dividing by 60; its unit is fixed to minutes. Binary and negative habits are excluded from the source picker because their values do not express the intended numeric quantity.

Completion IDs are counted once; separate genuine records retain their separate values. Off-schedule and archived-habit history still counts. Editing or deleting a canonical completion changes the derived total. No completion state is copied into a progress entry or schedule block.

If the selected habit is removed, reassigned, or changes to an unsupported type, preserve its configured ID and show source unavailable. Do not silently switch sources or represent the missing source as a reliable zero. Selecting another eligible habit explicitly restores calculation.

## Configuration changes

Switching modes retains manual entries but uses only the selected mode's contributions. Returning to manual mode restores those entries. Confirm mode/source changes when they change an existing measurement, explaining that totals will be recalculated. Changing baseline, target, or start date recalculates the display and retains history. Disabling measurement retains configuration and manual entries for later re-enabling. Goal archive retains everything; deleting a goal cascades only its manual progress entries and leaves linked tasks, habits, completions, and blocks intact.

The target is numeric configuration, not an immutable historical milestone. This iteration stores contribution history but does not create a separate audit trail of target edits. No conversion between arbitrary counter units is attempted.

## UI and architecture

Extend the existing goal form with an optional measurement section and conditional fields for mode/source/unit. Goal detail gains current/target values, progress bar, deadline context, and dated contribution history. Manual mode offers Add progress and entry edit/delete; derived history opens the existing task or habit surface for correction. Goal rows show compact progress for measured goals and an unavailable-source state where necessary.

Use snapshot values and stable IDs, resolving managed objects against the current model context before writes. Follow existing save-error reporting and rollback behavior. Calculation and validation belong in pure KadoCore services with injected Calendar and today, independent of SwiftUI and SwiftData. Derived inputs come from canonical task/completion snapshots; ScheduleBlock is never an input.

Provide contextual English/French strings and accessibility labels for progress values, source availability, and contribution actions. Preserve existing translations and mark new French drafts for review. Support large text and light/dark previews. Native rendering and VoiceOver review remain explicitly pending.

## Persistence and portability

Add schema V7, freezing V1–V6 model bodies. Add CloudKit-compatible defaulted/optional measurement fields to GoalRecord and a GoalProgressEntryRecord with nullable ownership and inverse relationship. Preserve current-schema aliases and update every app/widget/dev/preview/test container pin. Declare V6-to-V7 migration and test it with a populated V6 store once the native toolchain works. Current goals migrate with measurement disabled.

Use stable UUID source identity for the selected habit. Keep manual entries distinct from task/habit completion. All model fields must satisfy the project's CloudKit shape constraints; production CloudKit deployment remains a release step.

Advance JSON/CSV to format 4. Export measurement configuration and manual entries with IDs, goal references, dates, notes, and timestamps. Preserve formats 1–3 import. Older imports cannot express measurement changes and must retain existing measurement and manual entries when merging existing goal IDs. Format 4 imports validate finite values, mode/unit invariants, duplicate identity handling, and goal references before mutation. A missing selected habit is an explicit unavailable source, allowing backups to retain configuration after legitimate source deletion. Reject a source that exists but belongs to a different goal. Preserve the importer's existing merge/rollback policy and include manual-entry counts in previews and summaries.

## Verification and acceptance

- Pure calculation tests cover each mode, baseline, exceeding target, deadline behavior, start/today boundaries, duplicate IDs, reopening/unlinking, unsupported or missing sources, and timer conversion.
- Validation tests cover nonfinite/nonpositive amounts, invalid targets, configuration changes, and preserved manual history.
- JSON/CSV executable round trips cover configuration, entries, escaped notes, older formats, missing sources, and malformed references. Test actual production coders, with any platform shims documented.
- Native tests cover migration, persistence across relaunch, safe goal deletion, importer atomicity, and store swaps. Write them now; run when compatible Xcode is available.
- Parse changed Swift, lint project/property lists, validate localization JSON, and run diff whitespace checks. These checks do not prove the native app compiles.
- Document checks actually run and leave build/UI/CloudKit validation pending. No push, release, or CloudKit deployment is included.

## Deferred scope

Multiple habit sources, mixed manual/derived totals, decrease-oriented targets, arbitrary unit conversion, target-edit audit history, automatic goal completion, and analytics dashboards are excluded from this iteration.
