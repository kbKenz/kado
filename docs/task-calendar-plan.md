# Task scheduling and Google Calendar implementation plan

## Intended result

Add Calendar to the tab bar. Create one-off tasks from Today or Calendar, choose an optional day and independently optional start/end times, and see planned work in a day timeline. Google Calendar events such as “Meeting with Thomas” become linked local tasks on sync.

## Order of work

1. Add SwiftData schema V5 with TaskRecord and ScheduleBlockRecord and a lightweight migration from V4. Completion lives on the task; planned time lives on blocks.
2. Extend versioned JSON/CSV portability to retain the new records and relationships while reading previous backups.
3. Add task create/edit/completion, an inbox and due tasks in Today, and Calendar date navigation/timeline. Use civil calendar days for appointments while preserving the existing habit day-boundary setting.
4. Add official Google Sign-In to the app target and a small read-only Calendar REST client. Persist credentials through the SDK's Keychain handling, not SwiftData or exports.
5. Import the primary Google calendar over a rolling 30-day past / 180-day future window. Expand recurring events, paginate responses, and reconcile by account + calendar + event ID. Preserve local completion and archives when event title/time changes. Record remote cancellation separately and retain historical tasks.
6. Sync after connection, launch, foreground (throttled), each minute while active, and manual refresh. A complete snapshot is required before marking missing imported events. Preserve unchanged record timestamps to avoid unnecessary CloudKit writes. Document that immediate background push needs additional infrastructure.
7. Add regression coverage for optional times, migration, legacy and new backups, event decoding, pagination, duplicate import, cancellation/restoration, all-day/multi-day dates, and completion preservation.
8. Build and run available checks. Document any local toolchain limitations and the exact setup needed to enable live OAuth.

## Google setup boundary

An iOS OAuth client must be created in the owner's Google Cloud project with Calendar API enabled, the correct bundle ID, OAuth consent/test-user settings, GIDClientID, and its reversed-client-ID URL scheme. The local app should remain fully usable without that configuration. No client secret is needed in the app.

## Initial sync rules

- Google controls imported title, description, and event schedule. Kadō controls task completion and local archive.
- Completing a task does not change or delete a Google event.
- Locally created tasks stay local in this version; outbound event creation is a later explicit feature.
- Recurring occurrences have distinct Google event IDs and distinct task completion.
- An all-day event uses untimed block(s); timed events use absolute instants and render in the device calendar time zone.
- Credentials, transient access tokens, and account sync status are device-local. Backups include imported event identity/data so restored tasks do not duplicate on reconnect, but never authentication secrets.

## Validation environment

The installed Xcode is 16.0; the existing repository uses newer Swift language features and a project object format from newer Xcode. Native build/simulator availability will be checked separately. Pure Foundation Calendar API behavior can be compiled and checked using the installed Swift 6.3 command-line toolchain.
