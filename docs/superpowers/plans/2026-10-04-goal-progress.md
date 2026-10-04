# Goal Progress Implementation Plan

> **For agentic workers:** Use superpowers:executing-plans to implement inline.

**Goal:** Optional measurable goals with manual, task, and single-habit progress and lossless portability.
**Architecture:** Pure calculator and configuration validation in KadoCore; additive V7 persistence; existing SwiftUI goal flows consume snapshots. Canonical completions are the only derived inputs.
**Tech Stack:** Swift, SwiftData, SwiftUI, Swift Testing, Xcode 26.5, iOS 18+.
**Spec:** ../specs/2026-10-04-goal-progress-design.md

## Global Constraints

- No new dependencies; preserve uncommitted task/calendar/goal work in this checkout.
- Freeze V1–V6 models; use V7 and JSON/CSV format 4.
- Preserve old imports and manual history; goal status stays manual.
- User authorized autonomous implementation and review; no intermediate approval gates.

## Review Focus

Missing sources must not look like zero. Duplicate IDs must not double-count. Legacy imports must retain measurement. Disabled modes must retain entries. Native migration must preserve owner links.

### Task 1: Domain and calculator

Files: Models/GoalMeasurement.swift, Services/GoalProgressCalculator.swift, KadoTests/GoalProgressTests.swift.
Interface: GoalMeasurement(enabled, mode, baseline, target, unit, habitID); GoalProgressEntry(id, goalID, date, amount, note, createdAt, updatedAt); GoalProgressCalculator.calculate(goalID:measurement:startDate:today:calendar:entries:tasks:habits:completions:) -> GoalProgressResult.
- [x] Write calculation/validation tests for period, duplicates, source loss, overflow, timer conversion, and reopening; watch compile failure.
- [x] Implement pure types/calculator and run tests to green.

### Task 2: Persistence and backups

Files: KadoSchemaV7.swift, KadoMigrationPlan.swift, runtime pins, GoalBackup/BackupDocument/ImportSummary, exporter/importer/CSV coder, KadoTests/GoalProgressPersistenceTests.swift.
- [x] Write V6 upgrade, safe goal deletion, JSON/CSV round-trip, old-merge preservation, malformed references tests; verify migration and persistence.
- [x] Add V7 fields, entry model, versioned backups and validation/upserts. Run targeted tests green.

### Task 3: Goal UI

Files: GoalFormView, GoalListItem, GoalRowView, GoalDetailView, new GoalMeasurementSection/GoalProgressSection/GoalProgressEntryForm, localization and accessibility IDs.
- [x] Add measurement form, mode-change confirmation, editable manual history and canonical derived navigation; retain IDs/snapshots.
- [x] Add UI test for manual create/log/edit/relaunch, invalid-input rejection, and archived edit locking; run and capture simulator screenshot.

### Task 4: Verification and review

- [x] Standard build, complete unit suite, focused UI suite, migration checks, deployment check, project/catalog lint, whitespace.
- [x] One independent source review; resolve material findings and rerun affected tests.
- [x] Update spec/plan and implementation note with evidence and limitations; preserve existing user changes and leave feature reviewable locally.
