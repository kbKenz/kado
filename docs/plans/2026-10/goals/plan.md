# Plan — Goals linked to tasks and habits

**Date:** 2026-10-04
**Status:** Implemented and validated locally
**Research:** [research.md](research.md)

## Intended result

Create goals, connect tasks and habits to them, optionally measure numeric progress, and review results from the Goals tab. Goal organization preserves task/habit history and is fully portable through the existing backup controls.

## Decisions

- One optional goal per task/habit; each goal can have many linked items.
- Status is active, paused, or completed, chosen manually.
- Start/target dates are optional civil dates; a target cannot precede its start.
- Archive is reversible. Delete removes only the goal and its assignments.
- Goal assignment on Google tasks is local metadata and survives event synchronization.
- JSON/CSV imports of old formats preserve existing goal links.
- Work stays local, preserving the current uncommitted task/calendar changes.

## Execution

- [x] Add V6 schema, GoalStatus, inverses, migration, and current-schema runtime pins.
- [x] Add Goals tab/list/form/detail and link/reassign/unlink controls.
- [x] Integrate goal selection into task/habit forms, including imported tasks.
- [x] Extend JSON/CSV to format 3 and add goal import counts.
- [x] Add contextual English/French draft strings without changing existing translations.
- [x] Review source, parse changed Swift, validate project/catalog, and document native verification limits.
- [x] Add measurable progress modes, V7 migration, JSON/CSV v4, and contribution history.
- [x] Run native unit and focused iPhone/iPad UI validation; capture screenshots and implementation notes in [compound.md](compound.md).

## Remaining release checks

Deploy the CloudKit schema before distributing this schema change. Review new French wording before release.
