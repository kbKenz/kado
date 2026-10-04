# Measurable goal progress

Implemented locally on `feature/goal-progress` in `Documents/GitHub/kado`.

Goals now optionally measure manual amounts, completed linked tasks, or one linked counter/timer habit. Detail shows current/target, a progress bar, baseline, and contribution history. Manual entries can be added, edited, and deleted; derived entries open their task or habit. Goal status remains manually controlled.

V7 adds measurement configuration and goal-owned manual entries. JSON/CSV format 4 includes both, while older imports preserve existing measurement/history. Tests cover populated V6 migration, round trips, invalid owners, duplicate IDs, atomic rejection, and deletion ownership.

## Decisions

- Missing or reassigned habit sources show unavailable and retain their source ID through backup round trips.
- Custom units remain stored across mode changes; tasks and timer modes render fixed tasks/minutes units.
- Numeric draft text must fully parse before save; invalid text cannot silently reuse the last number.
- Archived goals lock measurement periods and manual entry edits.
- Existing uncommitted task/calendar work is preserved. No remote push or merge was performed.

## Verification

- Xcode 26.5 / iOS 26.5 simulator: 808 unit tests in 83 suites passed. One existing SwiftData observation test reports its declared known issue.
- iPhone 16 Pro focused UI test passed: create goal, invalid amount rejected, log/edit, relaunch persistence, archived date locking.
- iPad Pro 13-inch focused UI test passed the same workflow.
- Deployment check passed for the iOS 18 minimum. Project lint and whitespace checks passed.
- Independent source review completed; its numeric-draft and archived-edit findings were resolved and tested.

Screenshots: `screenshots/iphone-manual-progress.png`, `screenshots/iphone-archived-form.png`, and `screenshots/ipad-manual-progress.png`.

Production CloudKit schema deployment is still required before distributing this schema change. New French strings remain marked for translation review. Local simulator validation does not establish production CloudKit synchronization.
