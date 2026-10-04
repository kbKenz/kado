# Tasks, Calendar, and Google import — local implementation

## Current state

Source changes are saved locally in `/Users/bekturkenzhebaev/Documents/Codex/kado`, the checkout of `kbKenz/kado`. Nothing has been pushed. The earlier root `issues.md` backlog remains available.

The implementation is ready for native build and device review once a compatible Xcode/runtime is available. A native app build, simulator UI review, SwiftData migration execution, and live Google account connection have **not** been verified in this environment.

## What changed

### Tasks and Today

- Today's **+** menu offers New task and New habit.
- Tasks have a title, optional notes, an optional day, and independently optional start/end times. Both, either, or neither time can be selected. Removing the day returns the task to the inbox.
- A task with no day appears in the Today inbox. Today also displays due/overdue tasks and tasks completed on the current civil day.
- A paired end time must follow its start. Invalid daylight saving clock times are rejected instead of silently shifting the appointment.
- Completion is stored only on `TaskRecord.completedAt`; Today and Calendar edit that same value.
- Existing habit scheduling and the custom habit day boundary remain supported. Task appointments follow civil days, including foreground returns after midnight.

### Calendar tab

- The tab bar now contains Today, Calendar, Overview, and Settings.
- Calendar has a date picker, a week strip, previous/next week controls, a Today shortcut, and task creation for the selected day.
- Timed tasks appear on an hourly day timeline. Overlapping appointments use separate columns; overnight Google events appear on each day they overlap.
- Untimed and end-only tasks appear under **Any time** with their available timing information.
- Start-only tasks have a visual card height for readability; no end time is invented in persistence.
- Tap a task to open it. Long-press a timed task for completion/removal actions; untimed rows have a completion control. VoiceOver actions are provided.
- The timeline uses actual day duration for daylight saving changes, and a readable list for accessibility text sizes or crowded overlapping appointments.

### Google Calendar

- Uses the official Google Sign-In iOS SDK 10.0.0 for authentication and its branded SwiftUI button. A small Swift REST adapter reads Calendar events.
- Connection is available from Settings and the Calendar toolbar, and stays disabled until valid local OAuth configuration is supplied.
- The connected account's **primary** calendar imports events from 30 days before today through 180 days ahead, inclusive. Recurring occurrences are expanded by Google and become separate tasks.
- “Meeting with Thomas” becomes a task with its Google title, description, and planned time after a successful sync.
- Sync runs after connecting, on foreground with a one-minute throttle, roughly every minute while active, and on manual refresh. The loop waits one minute after each request. The app does not receive realtime events while closed.
- This first integration imports Google changes. Locally created tasks are not sent to Google, and task completion does not alter a Google event.
- Google owns imported titles/details/time; the app preserves local completion and archive choices. Imported details are read-only with a link to the source event.
- Identity uses account + calendar + Google event ID. Repeated import updates existing records; unchanged snapshots preserve timestamps and avoid unnecessary saves.
- All pages must succeed before reconciliation. Remote cancellation is separate metadata, and history stays stored. Failed or partial responses do not reconcile missing events.
- Disconnect clears this device's SDK credentials while retaining imported task history. Imports pause in dev mode, and cancelled or stale requests cannot update a swapped store.

### Persistence, export, and privacy

- Added SwiftData schema V5, `TaskRecord`, and `ScheduleBlockRecord`, with a lightweight V4 → V5 migration. Earlier schema model definitions remain frozen.
- Planned blocks store planned time only and link to their owner. They have no completion or actual-time state.
- JSON and CSV format 2 retain tasks, blocks, completion, source identity, cancellation metadata, and relationships. Older habit-only files remain readable.
- Backup import confirmations and summaries count tasks and planned blocks.
- Google credentials are managed by the SDK in Keychain; no access/refresh token is stored in SwiftData, CloudKit, JSON, or CSV.
- Updated the privacy policy for the optional Google SDK. Existing 328 localization entries were preserved; 101 new English/French entries were added, with French drafts marked `needs_review`.

## Research decision

Google's official Sign-In SDK removes the OAuth/browser/token work. Google's generated REST Objective-C client is also available, but adds a broad API surface for the single endpoint needed here. The initial combination uses the official auth SDK with a small paginated Swift `events.list` client.

EventKit is another option for calendars already configured on the device. It is documented as a future integration alongside the direct Google connection. A webhook/server design would be needed for Google push notifications while the app is closed.

The research notes contain the official sources and tradeoffs: [Google Calendar research](google-calendar-research.md).

## Checks performed

| Check | Result |
|---|---|
| Swift syntax for 57 changed/new source files | Passed |
| Xcode project and Info.plist validation | Passed |
| Existing catalog preservation and new EN/FR entries | Passed |
| `git diff --check` | Passed |
| Calendar event decoding and REST adapter executable checks | Passed: timestamps/time zones, all-day exclusive dates, daylight saving, Gregorian API dates under Buddhist settings, query shape, pagination, repeated page tokens, partial response failure, authorization failure, empty calendar |
| Portable core executable | 20 production files compiled; 33 assertions passed for JSON/CSV fields and relationship IDs, legacy files, escaped text, duplicate/future CSV handling, optional times, schedule errors, and date edges |
| Native app build | Blocked: Xcode 16.0 asset compiler cannot launch `AssetCatalogSimulatorAgent`; both simulator and generic device attempts failed there |
| Native SwiftData/migration/importer tests | Not run successfully: installed SwiftData macro/SwiftSyntax and Swift Testing macro/runtime versions are incompatible with the newer CLI compiler |
| Native UI and live Google account | Pending: usable native runtime and owner OAuth configuration required |

Portable checks compile actual source files. The core harness substitutes only the raw-case `HabitColor` presentation enum to exclude UIKit, and does not validate SwiftData, CloudKit, or SwiftUI behavior. Native persistence/import/UI regression coverage is saved in the repo for a compatible Xcode.

Local build logs are in the repo's ignored `work/` folder. Portable core harness logs are in the chat workspace's `work/PureCoreValidation/` and native harness limitations in `work/CoreValidation/README.md`.

## Next local steps

1. Open `Kado.xcodeproj` with a compatible Swift toolchain and working iOS runtime; choose your signing team and run the app.
2. Create the owner's iOS OAuth client with Calendar API enabled. Add its client ID and reversed ID to the ignored `Config/GoogleCalendar.local.xcconfig` file. Follow [Google setup](google-calendar-setup.md).
3. Review the native task/Calendar screens and migration using existing data. Follow the setup checklist for a real Meeting with Thomas, edits, completion, cancellation, all-day events, and recurring occurrences.
4. Before release, complete independent app identity/signing/CloudKit configuration, deploy the new CloudKit schema, and review the French drafts and optional Google SDK privacy disclosures.

The execution order and initial sync rules are preserved in [the implementation plan](task-calendar-plan.md).
