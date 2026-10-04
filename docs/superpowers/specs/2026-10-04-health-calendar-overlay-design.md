# Health on Calendar: sleep and workout overlay

Date: 2026-10-04
Status: Approved design, not implemented
Scope: Show HealthKit sleep and workouts on the Calendar day timeline. Builds on the local Tasks and Calendar implementation.

## Intent and constraints

The user wants to see where their time went: when they slept and when they trained, next to their planned tasks. The feature is for reflection only. It does not change tasks, habits, completions, scores, or goals.

Screen Time is out of scope. The Screen Time API (`FamilyControls` + `DeviceActivity`) gives no raw session times, only coarse threshold events, and it needs the Family Controls distribution entitlement from Apple. It gets its own spec later if needed.

The roadmap descoped HealthKit auto-completion on 2026-09-05 ("you decide what counts", an unwanted permission prompt, and the support questions that come from scores that change by themselves). This feature does not reverse that decision. It is display-only and opt-in, and no score or completion changes because of Health data.

## Product behavior

### Opt-in

The feature is off by default. Settings has a "Health on Calendar" row with a toggle, stored in `UserDefaults` on this device only. When the user turns the toggle on, Kadō requests read-only authorization for `HKCategoryType(.sleepAnalysis)` and `HKObjectType.workoutType()`. Kadō never writes to Health.

If `HKHealthStore.isHealthDataAvailable()` is false, the row is hidden and the feature is unavailable.

HealthKit does not tell an app that read access was denied; it returns no samples. So an empty day shows no error. The row footer says: "No data showing? Check Settings → Health → Data Access → Kadō." A button opens the Health app.

When the toggle is off, Kadō never queries HealthKit.

### Timeline display

On each Calendar day, with the toggle on:

- **Sleep** shows as a full-width, muted band behind the task cards. It takes no lane, so a long sleep does not make task cards narrow. The band has a "Sleep" label and its time range.
- **Workouts** show as cards in the normal lanes, in a style different from task cards, with the activity name (for example "Running") and a "Health" caption, the same way imported events show "Google Calendar". Workout cards are read-only. Tapping one does nothing.
- Entries that cross midnight are clipped to the civil day, the same way cross-midnight blocks are. Sleep from 23:30 to 07:00 shows 23:30–24:00 on the first day and 00:00–07:00 on the next day.
- The accessible agenda (accessibility text sizes, or more than three overlapping lanes) lists sleep and workout entries as rows, ordered by start time with the task blocks.

The Calendar uses civil days. The habit "Day starts at" setting does not apply to Health entries.

### Sleep sessions

Raw sleep samples become sessions with these rules:

1. Asleep samples (`asleepCore`, `asleepDeep`, `asleepREM`, `asleepUnspecified`) are the source when any exist in the query window.
2. If there are no asleep samples, `inBed` samples are the source. This is the usual case for an iPhone without an Apple Watch.
3. `awake` samples are never a source.
4. Overlapping intervals from different sources (for example Watch and iPhone) merge into one interval.
5. Intervals separated by a gap of 30 minutes or less merge into one session. A longer gap starts a new session, so a nap shows on its own.

### Errors

If a HealthKit query throws, Kadō logs the error type only, never sample data, and shows the day without that kind of entry. The sleep query and the workout query fail on their own: if one fails, the other still shows. A Health failure never prevents the Calendar from showing task blocks.

## Architecture

### KadoCore

- `HealthTimelineEntry`: a `nonisolated` value type (`Hashable`, `Sendable`) with `id: UUID`, `kind` (`.sleep` or `.workout(name: String)`), and `interval: DateInterval`.
- `SleepSessionBuilder`: a pure function that turns raw sleep intervals with their stage into `HealthTimelineEntry` sessions with the rules above. It has no HealthKit import, so its tests do not need HealthKit.
- A pure clipping function that clips entries to a civil-day `DateInterval` and drops entries that do not intersect it. The day interval comes from `calendar.dateInterval(of: .day, for:)`, never from raw seconds.

### App target

- `HealthTimelineProviding` protocol: `sleepEntries(in:)` and `workoutEntries(in:)` (separate, so one can fail without hiding the other), plus `requestAuthorization()` and `isAvailable`.
- `HealthTimelineLoader`: gates on the opt-in and availability, calls both queries, catches each failure on its own, and clips the result to the day.
- `HealthKitTimelineProvider`: the live implementation. It uses `HKHealthStore` with async sample queries for sleep and workouts, maps samples to the inputs of `SleepSessionBuilder`, and maps `HKWorkoutActivityType` to a localized activity name.
- `MockHealthTimelineProvider`: returns fixed entries or throws. It is the default `@Entry` in `EnvironmentValues+Services.swift`, so previews and unit tests never touch HealthKit. `KadoApp` injects the live provider at scene build, following the `notificationScheduler` pattern.
- `PlannerCalendarView` loads entries with `.task(id:)` keyed on the selected day and on the scene becoming active. It queries the day's interval extended by 12 hours on each side (`calendar.date(byAdding: .hour, ...)`), because sleep crosses midnight, then clips to the day.
- `CalendarDayTimeline` gets a new `healthEntries: [HealthTimelineEntry]` parameter. Sleep bands are drawn after the hour grid and before the lane cards, and they do not take taps, so the task cards above them stay tappable. Workout cards join the lane layout. Colors use existing semantic Kadō tokens (for example `kadoBackgroundSecondary` for the band); a new palette color needs discussion first.
- Accessibility: each sleep band and workout card is one VoiceOver element with a label such as "Sleep, 23:30 to 07:00" or "Running workout, 07:10 to 07:52, from Health". Labels and time ranges support Dynamic Type.
- Settings gets a `HealthCalendarSettingsView` row next to the Google Calendar row.

### Project configuration

- Add the `com.apple.developer.healthkit` entitlement to the app target only. Widgets and the Watch app do not change.
- Add `NSHealthShareUsageDescription` to `Kado/Info.plist`: "Kadō shows your sleep and workouts on your Calendar. This data stays on your device." Localize it in EN and FR (FR uses `tu`), with the native speaker as final reviewer. New UI strings go into `Localizable.xcstrings` by hand with a `comment`, and `LocalizationCoverageTests` must pass.
- No `NSHealthUpdateUsageDescription`, because Kadō does not write.
- No SwiftData schema change. Health data is never written to SwiftData, CloudKit, JSON/CSV backups, or widgets.

### Documentation

- `ROADMAP.md`: add a note under "HealthKit auto-completion — descoped" that the Health on Calendar overlay is display-only and does not change that decision.
- `PRIVACY.md`: state that Kadō reads sleep and workout data only to draw the Calendar, only on the device, and only after the user opts in, and that it never stores, syncs, or exports that data.

## Out of scope

Screen Time, HealthKit background delivery, Health entries on Today or in widgets, "Save as task" from a Health entry, habit or goal auto-completion, other Health types (steps, mindfulness), and tapping a workout for detail.

## Testing

All tests use the existing `KadoTests` style and run with `make test`.

`SleepSessionBuilderTests`:
- Watch night: core, deep, and REM stages give one session.
- iPhone only: `inBed` samples are the fallback.
- `inBed` and asleep samples together: asleep is the source, `inBed` is ignored.
- A 20-minute gap merges; a 2-hour gap gives two sessions.
- Overlapping samples from two sources give one session.
- `awake` samples alone give no session.
- No samples give no session.

`HealthTimelineClippingTests`:
- Sleep 23:30–07:00 clips to both days correctly.
- Spring-forward and fall-back days clip correctly in `Europe/Paris`, and a day with no midnight clips correctly in `America/Havana` (`TestCalendar.havana`).
- Entries outside the day are dropped.

Provider and view wiring, with `MockHealthTimelineProvider` in `KadoTests/Mocks/`:
- Toggle off: the provider is never called.
- Provider throws: the Calendar still shows task blocks.
- Only workouts return: workout cards show and no sleep band shows.

Manual verification: add sleep and workout samples in the simulator's Health app, turn on the toggle, open Calendar, and capture `make shot` in light and dark mode. Check iPhone and iPad, Dynamic Type XXXL, and VoiceOver. Run `make deployment-check` because the entitlement change touches the project file.
