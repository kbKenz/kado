# Health on Calendar Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers-extended-cc:subagent-driven-development (recommended) or superpowers-extended-cc:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Show HealthKit sleep sessions and workouts as read-only entries on the Calendar day timeline, opt-in from Settings.

**Architecture:** Pure value types and logic (`HealthTimelineEntry`, `SleepSample`, `SleepSessionBuilder`, `HealthTimelineClipper`) live in KadoCore with no HealthKit import. The app target has a `HealthTimelineProviding` protocol with a live `HealthKitTimelineProvider` and a stub default, plus a `HealthTimelineLoader` that isolates failures. `PlannerCalendarView` loads entries per day and `CalendarDayTimeline` draws sleep as a background band and workouts as read-only lane cards. Nothing is persisted.

**Tech Stack:** Swift 6, SwiftUI, HealthKit (`HKSampleQueryDescriptor`), Swift Testing, `make test`.

**Spec:** `docs/superpowers/specs/2026-10-04-health-calendar-overlay-design.md`

---

## Conventions for every task

- Work only in `/Users/bekturkenzhebaev/Documents/GitHub/kado/.worktrees/health-calendar-overlay`. Check with `git rev-parse --show-toplevel` before editing.
- All folders are Xcode file-system-synchronized groups. A new `.swift` file under `Kado/`, `KadoTests/`, or `Packages/KadoCore/Sources/KadoCore/` is compiled automatically. Do not edit `project.pbxproj` by hand except where a task says so.
- The app target uses `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`. KadoCore value types used across actors are marked `nonisolated`. The test target is not MainActor by default, so suites that touch app types are marked `@MainActor`.
- Run tests with `make test` (whole `KadoTests` bundle, quiet output). If it fails with a destination error, follow "Destination resolution flakiness" in `CLAUDE.md`. Use an iOS 26.x simulator, not 27.0.
- Every new user-facing string goes into `Kado/Resources/Localizable.xcstrings` by hand, with a `comment` and an FR translation (`tu`). FR drafts are marked for review by the native speaker in the PR. `LocalizationCoverageTests` must pass.
- Commit messages: conventional commits, ending with:

```
Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01HWT8fo21dQ2K9hgBPEj1e7
```

## File map

| File | Responsibility |
|---|---|
| `Packages/KadoCore/Sources/KadoCore/Models/HealthTimelineEntry.swift` (create) | Display-only entry: id, kind (sleep / workout name), interval |
| `Packages/KadoCore/Sources/KadoCore/Models/SleepSample.swift` (create) | HealthKit-free input for the builder: id, stage, interval |
| `Packages/KadoCore/Sources/KadoCore/Services/Health/SleepSessionBuilder.swift` (create) | Raw sleep samples → merged sessions |
| `Packages/KadoCore/Sources/KadoCore/Services/Health/HealthTimelineClipper.swift` (create) | Query window around a day; clip entries to a civil day |
| `Kado/Services/HealthTimelineProviding.swift` (create) | Protocol for reading Health entries |
| `Kado/Services/PreviewHealthTimelineProvider.swift` (create) | Stub default for the environment and previews |
| `Kado/Services/HealthTimelineLoader.swift` (create) | Toggle gate, per-kind failure isolation, clipping |
| `Kado/Services/HealthCalendarDefaults.swift` (create) | `UserDefaults` key for the opt-in toggle |
| `Kado/Services/HealthKitTimelineProvider.swift` (create) | Live HealthKit queries and sample mapping |
| `Kado/Services/HKWorkoutActivityType+DisplayName.swift` (create) | Localized workout names |
| `Kado/App/EnvironmentValues+Services.swift` (modify) | `healthTimelineProvider` entry |
| `Kado/App/KadoApp.swift` (modify) | Inject the live provider |
| `Kado/Kado.entitlements` (modify) | HealthKit entitlement |
| `Kado/Info.plist` (modify) | `NSHealthShareUsageDescription` |
| `Kado/Resources/InfoPlist.xcstrings` (create) | EN + FR usage description |
| `Kado/Views/Calendar/CalendarBlockItem.swift` (modify) | Health-backed item initializer |
| `Kado/Views/Calendar/CalendarDayTimeline.swift` (modify) | Sleep band, workout cards, agenda rows |
| `Kado/Views/Calendar/PlannerCalendarView.swift` (modify) | Load entries per day |
| `Kado/Views/Settings/HealthCalendarSection.swift` (create) | Opt-in toggle, footer, Open Health |
| `Kado/Views/Settings/SettingsView.swift` (modify) | Show the section |
| `Shared/AccessibilityID.swift` (modify) | Health identifiers |
| `Kado/Resources/Localizable.xcstrings` (modify) | New strings |
| `KadoTests/SleepSessionBuilderTests.swift` (create) | Builder rules |
| `KadoTests/HealthTimelineClippingTests.swift` (create) | Clipping and DST |
| `KadoTests/Mocks/StubHealthTimelineProvider.swift` (create) | Test double that counts calls and can throw |
| `KadoTests/HealthTimelineLoaderTests.swift` (create) | Gate and failure isolation |
| `docs/ROADMAP.md`, `PRIVACY.md` (modify) | Product and privacy notes |

---

### Task 1: Sleep session builder

**Goal:** Pure KadoCore types and the function that turns raw sleep samples into sessions.

**Files:**
- Create: `Packages/KadoCore/Sources/KadoCore/Models/HealthTimelineEntry.swift`
- Create: `Packages/KadoCore/Sources/KadoCore/Models/SleepSample.swift`
- Create: `Packages/KadoCore/Sources/KadoCore/Services/Health/SleepSessionBuilder.swift`
- Test: `KadoTests/SleepSessionBuilderTests.swift`

**Acceptance Criteria:**
- [ ] Asleep stages are the source when any exist; `inBed` is used only when no asleep sample exists.
- [ ] `awake` samples never create a session.
- [ ] Overlapping samples and gaps ≤ 30 minutes merge; longer gaps split.
- [ ] Session id is the id of its earliest sample (stable across reloads).

**Verify:** `make test` → `** TEST SUCCEEDED **`, including `SleepSessionBuilder` suite.

**Steps:**

- [ ] **Step 1: Write the failing tests**

`KadoTests/SleepSessionBuilderTests.swift`:

```swift
import Foundation
import Testing
import KadoCore

@Suite("SleepSessionBuilder")
struct SleepSessionBuilderTests {
    /// 2026-04-13 22:00 UTC. Offsets are in minutes from here.
    let night = TestCalendar.utc.date(bySettingHour: 22, minute: 0, second: 0, of: TestCalendar.referenceDate)!

    func sample(_ stage: SleepSample.Stage, from start: Int, to end: Int, id: UUID = UUID()) -> SleepSample {
        SleepSample(
            id: id, stage: stage,
            interval: DateInterval(start: night.addingTimeInterval(TimeInterval(start * 60)),
                                   end: night.addingTimeInterval(TimeInterval(end * 60)))
        )
    }

    func minutes(_ entry: HealthTimelineEntry) -> (Int, Int) {
        (Int(entry.interval.start.timeIntervalSince(night) / 60), Int(entry.interval.end.timeIntervalSince(night) / 60))
    }

    @Test("Watch night: contiguous asleep stages give one session")
    func watchNightMerges() {
        let first = UUID()
        let sessions = SleepSessionBuilder.sessions(from: [
            sample(.asleep, from: 30, to: 120, id: first),
            sample(.asleep, from: 120, to: 300),
            sample(.asleep, from: 300, to: 510),
        ])
        #expect(sessions.count == 1)
        #expect(minutes(sessions[0]) == (30, 510))
        #expect(sessions[0].kind == .sleep)
        #expect(sessions[0].id == first)
    }

    @Test("iPhone only: inBed is the fallback source")
    func inBedFallback() {
        let sessions = SleepSessionBuilder.sessions(from: [sample(.inBed, from: 0, to: 480)])
        #expect(sessions.count == 1)
        #expect(minutes(sessions[0]) == (0, 480))
    }

    @Test("Asleep wins over inBed when both exist")
    func asleepWinsOverInBed() {
        let sessions = SleepSessionBuilder.sessions(from: [
            sample(.inBed, from: 0, to: 540),
            sample(.asleep, from: 40, to: 500),
        ])
        #expect(sessions.count == 1)
        #expect(minutes(sessions[0]) == (40, 500))
    }

    @Test("A 20-minute awake gap merges")
    func shortGapMerges() {
        let sessions = SleepSessionBuilder.sessions(from: [
            sample(.asleep, from: 0, to: 200),
            sample(.awake, from: 200, to: 220),
            sample(.asleep, from: 220, to: 480),
        ])
        #expect(sessions.count == 1)
        #expect(minutes(sessions[0]) == (0, 480))
    }

    @Test("A gap of exactly 30 minutes merges")
    func boundaryGapMerges() {
        let sessions = SleepSessionBuilder.sessions(from: [
            sample(.asleep, from: 0, to: 200),
            sample(.asleep, from: 230, to: 480),
        ])
        #expect(sessions.count == 1)
    }

    @Test("A 2-hour gap splits into two sessions")
    func longGapSplits() {
        let sessions = SleepSessionBuilder.sessions(from: [
            sample(.asleep, from: 0, to: 420),
            sample(.asleep, from: 540, to: 600),
        ])
        #expect(sessions.count == 2)
        #expect(minutes(sessions[0]) == (0, 420))
        #expect(minutes(sessions[1]) == (540, 600))
    }

    @Test("Overlapping samples from two sources give one session")
    func overlappingSourcesDeduplicate() {
        let sessions = SleepSessionBuilder.sessions(from: [
            sample(.asleep, from: 0, to: 400),
            sample(.asleep, from: 10, to: 420),
        ])
        #expect(sessions.count == 1)
        #expect(minutes(sessions[0]) == (0, 420))
    }

    @Test("Unsorted input gives the same result as sorted input")
    func orderIndependent() {
        let samples = [sample(.asleep, from: 300, to: 480), sample(.asleep, from: 0, to: 290)]
        #expect(SleepSessionBuilder.sessions(from: samples).map(minutes).map { [$0.0, $0.1] }
            == SleepSessionBuilder.sessions(from: samples.reversed()).map(minutes).map { [$0.0, $0.1] })
    }

    @Test("Awake samples alone give no session")
    func awakeOnlyIsEmpty() {
        #expect(SleepSessionBuilder.sessions(from: [sample(.awake, from: 0, to: 60)]).isEmpty)
    }

    @Test("No samples give no session")
    func emptyInput() {
        #expect(SleepSessionBuilder.sessions(from: []).isEmpty)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `make test`
Expected: build failure, `cannot find 'SleepSessionBuilder' in scope` / `cannot find type 'SleepSample'`.

- [ ] **Step 3: Write the implementation**

`Packages/KadoCore/Sources/KadoCore/Models/HealthTimelineEntry.swift`:

```swift
import Foundation

/// One Health interval shown on the Calendar timeline. Display-only:
/// never persisted to SwiftData, synced, exported, or used to
/// complete a habit or task.
nonisolated public struct HealthTimelineEntry: Hashable, Sendable, Identifiable {
    public enum Kind: Hashable, Sendable {
        case sleep
        /// `name` is already localized for display.
        case workout(name: String)
    }

    public let id: UUID
    public let kind: Kind
    public let interval: DateInterval

    public init(id: UUID, kind: Kind, interval: DateInterval) {
        self.id = id
        self.kind = kind
        self.interval = interval
    }
}
```

`Packages/KadoCore/Sources/KadoCore/Models/SleepSample.swift`:

```swift
import Foundation

/// A raw sleep-analysis sample, mapped out of HealthKit so the session
/// rules can be tested without it.
nonisolated public struct SleepSample: Hashable, Sendable {
    public enum Stage: Hashable, Sendable {
        case inBed
        /// Any asleep stage: core, deep, REM, or unspecified.
        case asleep
        case awake
    }

    public let id: UUID
    public let stage: Stage
    public let interval: DateInterval

    public init(id: UUID, stage: Stage, interval: DateInterval) {
        self.id = id
        self.stage = stage
        self.interval = interval
    }
}
```

`Packages/KadoCore/Sources/KadoCore/Services/Health/SleepSessionBuilder.swift`:

```swift
import Foundation

/// Turns raw sleep samples into the sessions the Calendar draws.
///
/// Asleep stages are the source when any exist. `inBed` is the
/// fallback for an iPhone without a Watch, which records only time in
/// bed. `awake` never forms a session. Overlaps (Watch and iPhone
/// recording the same night) and short wake-ups merge, so one night
/// reads as one band; a gap longer than ``mergeGap`` starts a new
/// session, so a nap stands on its own.
nonisolated public enum SleepSessionBuilder {
    /// A duration, not day arithmetic, so raw seconds are correct here.
    public static let mergeGap: TimeInterval = 30 * 60

    public static func sessions(from samples: [SleepSample]) -> [HealthTimelineEntry] {
        let asleep = samples.filter { $0.stage == .asleep }
        let source = asleep.isEmpty ? samples.filter { $0.stage == .inBed } : asleep
        let sorted = source.sorted { $0.interval.start < $1.interval.start }

        var sessions: [HealthTimelineEntry] = []
        for sample in sorted {
            if let last = sessions.last,
               sample.interval.start.timeIntervalSince(last.interval.end) <= mergeGap {
                let end = max(last.interval.end, sample.interval.end)
                sessions[sessions.count - 1] = HealthTimelineEntry(
                    id: last.id, kind: .sleep,
                    interval: DateInterval(start: last.interval.start, end: end)
                )
            } else {
                sessions.append(HealthTimelineEntry(id: sample.id, kind: .sleep, interval: sample.interval))
            }
        }
        return sessions
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `make test`
Expected: `** TEST SUCCEEDED **`

- [ ] **Step 5: Commit**

```bash
git add Packages/KadoCore/Sources/KadoCore/Models/HealthTimelineEntry.swift \
  Packages/KadoCore/Sources/KadoCore/Models/SleepSample.swift \
  Packages/KadoCore/Sources/KadoCore/Services/Health/SleepSessionBuilder.swift \
  KadoTests/SleepSessionBuilderTests.swift
git commit -m "feat(health): build sleep sessions from raw samples"
```

---

### Task 2: Civil-day clipping

**Goal:** Compute the query window around a day and clip entries to the civil day, correct across DST.

**Files:**
- Create: `Packages/KadoCore/Sources/KadoCore/Services/Health/HealthTimelineClipper.swift`
- Test: `KadoTests/HealthTimelineClippingTests.swift`

**Acceptance Criteria:**
- [ ] Sleep 23:30–07:00 shows 23:30–24:00 on day 1 and 00:00–07:00 on day 2.
- [ ] Entries outside the day, or touching only its edge, are dropped.
- [ ] Output is sorted by start.
- [ ] Clipping is correct on Paris spring-forward / fall-back and on Havana's midnight-less day.

**Verify:** `make test` → `** TEST SUCCEEDED **`

**Steps:**

- [ ] **Step 1: Write the failing tests**

`KadoTests/HealthTimelineClippingTests.swift`:

```swift
import Foundation
import Testing
import KadoCore

@Suite("HealthTimelineClipper")
struct HealthTimelineClippingTests {
    func date(_ calendar: Calendar, _ y: Int, _ m: Int, _ d: Int, _ h: Int, _ min: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }

    func entry(_ start: Date, _ end: Date) -> HealthTimelineEntry {
        HealthTimelineEntry(id: UUID(), kind: .sleep, interval: DateInterval(start: start, end: end))
    }

    @Test("Overnight sleep is split across both days")
    func overnightSplits() {
        let cal = TestCalendar.utc
        let sleep = entry(date(cal, 2026, 4, 13, 23, 30), date(cal, 2026, 4, 14, 7))
        let dayOne = HealthTimelineClipper.entries([sleep], on: date(cal, 2026, 4, 13, 12), calendar: cal)
        let dayTwo = HealthTimelineClipper.entries([sleep], on: date(cal, 2026, 4, 14, 12), calendar: cal)
        #expect(dayOne.map(\.interval) == [DateInterval(start: date(cal, 2026, 4, 13, 23, 30), end: date(cal, 2026, 4, 14, 0))])
        #expect(dayTwo.map(\.interval) == [DateInterval(start: date(cal, 2026, 4, 14, 0), end: date(cal, 2026, 4, 14, 7))])
        #expect(dayTwo.first?.id == sleep.id)
    }

    @Test("Entries outside the day or touching only its edge are dropped")
    func outsideDropped() {
        let cal = TestCalendar.utc
        let before = entry(date(cal, 2026, 4, 12, 22), date(cal, 2026, 4, 13, 0))
        let after = entry(date(cal, 2026, 4, 15, 1), date(cal, 2026, 4, 15, 2))
        #expect(HealthTimelineClipper.entries([before, after], on: date(cal, 2026, 4, 13, 12), calendar: cal).isEmpty)
    }

    @Test("Output is sorted by start")
    func sorted() {
        let cal = TestCalendar.utc
        let late = entry(date(cal, 2026, 4, 13, 18), date(cal, 2026, 4, 13, 19))
        let early = entry(date(cal, 2026, 4, 13, 7), date(cal, 2026, 4, 13, 8))
        let result = HealthTimelineClipper.entries([late, early], on: date(cal, 2026, 4, 13, 12), calendar: cal)
        #expect(result.map(\.id) == [early.id, late.id])
    }

    @Test("Query window reaches 12 hours past each edge of the day")
    func queryWindow() {
        let cal = TestCalendar.utc
        let window = HealthTimelineClipper.queryInterval(around: date(cal, 2026, 4, 13, 12), calendar: cal)
        #expect(window == DateInterval(start: date(cal, 2026, 4, 12, 12), end: date(cal, 2026, 4, 14, 12)))
    }

    @Test("Clipped entries stay inside the civil day across DST shapes",
          arguments: [
            (TestCalendar.paris, 2026, 3, 29),   // 23-hour day
            (TestCalendar.paris, 2026, 10, 25),  // 25-hour day
            (TestCalendar.havana, 2026, 3, 8),   // day starts at 01:00
          ])
    func dstInvariant(calendar: Calendar, year: Int, month: Int, day: Int) {
        let noon = date(calendar, year, month, day, 12)
        let dayInterval = calendar.dateInterval(of: .day, for: noon)!
        let spanning = entry(calendar.date(byAdding: .hour, value: -6, to: dayInterval.start)!,
                             calendar.date(byAdding: .hour, value: 6, to: dayInterval.end)!)
        let result = HealthTimelineClipper.entries([spanning], on: noon, calendar: calendar)
        #expect(result.count == 1)
        #expect(result.first?.interval == dayInterval)
        let window = HealthTimelineClipper.queryInterval(around: noon, calendar: calendar)!
        #expect(window.start < dayInterval.start && window.end > dayInterval.end)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `make test`
Expected: build failure, `cannot find 'HealthTimelineClipper' in scope`.

- [ ] **Step 3: Write the implementation**

`Packages/KadoCore/Sources/KadoCore/Services/Health/HealthTimelineClipper.swift`:

```swift
import Foundation

/// Fits Health entries to the Calendar's civil day. The habit
/// "Day starts at" setting does not apply: the Calendar is civil.
nonisolated public enum HealthTimelineClipper {
    /// The day widened by 12 hours on each side, so a night that
    /// starts the evening before (or a session that ends the morning
    /// after) is fetched whole and merges correctly before clipping.
    public static func queryInterval(around day: Date, calendar: Calendar) -> DateInterval? {
        guard let dayInterval = calendar.dateInterval(of: .day, for: day),
              let start = calendar.date(byAdding: .hour, value: -12, to: dayInterval.start),
              let end = calendar.date(byAdding: .hour, value: 12, to: dayInterval.end)
        else { return nil }
        return DateInterval(start: start, end: end)
    }

    /// Entries intersecting the day, clipped to it and sorted by start.
    /// An entry that only touches the day's edge is dropped.
    public static func entries(_ entries: [HealthTimelineEntry], on day: Date, calendar: Calendar) -> [HealthTimelineEntry] {
        guard let dayInterval = calendar.dateInterval(of: .day, for: day) else { return [] }
        return entries
            .compactMap { entry -> HealthTimelineEntry? in
                guard let clipped = entry.interval.intersection(with: dayInterval), clipped.duration > 0 else { return nil }
                return HealthTimelineEntry(id: entry.id, kind: entry.kind, interval: clipped)
            }
            .sorted { $0.interval.start < $1.interval.start }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `make test`
Expected: `** TEST SUCCEEDED **`

- [ ] **Step 5: Commit**

```bash
git add Packages/KadoCore/Sources/KadoCore/Services/Health/HealthTimelineClipper.swift KadoTests/HealthTimelineClippingTests.swift
git commit -m "feat(health): clip health entries to the civil day"
```

---

### Task 3: Provider protocol, stub, and loader

**Goal:** The app-side seam for reading Health data, the opt-in key, and a loader that gates on the toggle and isolates per-kind failures.

**Files:**
- Create: `Kado/Services/HealthTimelineProviding.swift`
- Create: `Kado/Services/PreviewHealthTimelineProvider.swift`
- Create: `Kado/Services/HealthTimelineLoader.swift`
- Create: `Kado/Services/HealthCalendarDefaults.swift`
- Modify: `Kado/App/EnvironmentValues+Services.swift` (add entry at the end of the `EnvironmentValues` extension)
- Create: `KadoTests/Mocks/StubHealthTimelineProvider.swift`
- Test: `KadoTests/HealthTimelineLoaderTests.swift`

**Acceptance Criteria:**
- [ ] Toggle off or Health unavailable: the provider is never called and the result is empty.
- [ ] Sleep query throws: workouts still return. Workout query throws: sleep still returns.
- [ ] Results are clipped to the day.
- [ ] Errors are logged by type name only.

**Verify:** `make test` → `** TEST SUCCEEDED **`

**Steps:**

- [ ] **Step 1: Write the test double and failing tests**

`KadoTests/Mocks/StubHealthTimelineProvider.swift`:

```swift
import Foundation
import KadoCore
@testable import Kado

/// Driven sequentially by one test at a time, so plain stored state
/// is enough.
@MainActor
final class StubHealthTimelineProvider: HealthTimelineProviding {
    struct Failure: Error {}

    var isAvailable = true
    var sleep: [HealthTimelineEntry] = []
    var workouts: [HealthTimelineEntry] = []
    var sleepFails = false
    var workoutsFails = false
    private(set) var queryCount = 0

    func requestAuthorization() async throws {}

    func sleepEntries(in interval: DateInterval) async throws -> [HealthTimelineEntry] {
        queryCount += 1
        if sleepFails { throw Failure() }
        return sleep
    }

    func workoutEntries(in interval: DateInterval) async throws -> [HealthTimelineEntry] {
        queryCount += 1
        if workoutsFails { throw Failure() }
        return workouts
    }
}
```

`KadoTests/HealthTimelineLoaderTests.swift`:

```swift
import Foundation
import Testing
import KadoCore
@testable import Kado

@MainActor
@Suite("HealthTimelineLoader")
struct HealthTimelineLoaderTests {
    let calendar = TestCalendar.utc
    var day: Date { calendar.startOfDay(for: TestCalendar.referenceDate) }

    func entry(_ kind: HealthTimelineEntry.Kind, hours: ClosedRange<Int>) -> HealthTimelineEntry {
        HealthTimelineEntry(
            id: UUID(), kind: kind,
            interval: DateInterval(start: calendar.date(byAdding: .hour, value: hours.lowerBound, to: day)!,
                                   end: calendar.date(byAdding: .hour, value: hours.upperBound, to: day)!)
        )
    }

    @Test("Toggle off: provider is never called")
    func disabledSkipsProvider() async {
        let provider = StubHealthTimelineProvider()
        provider.sleep = [entry(.sleep, hours: 0...7)]
        let result = await HealthTimelineLoader(provider: provider, calendar: calendar).entries(on: day, isEnabled: false)
        #expect(result.isEmpty)
        #expect(provider.queryCount == 0)
    }

    @Test("Health unavailable: provider is never queried")
    func unavailableSkipsProvider() async {
        let provider = StubHealthTimelineProvider()
        provider.isAvailable = false
        let result = await HealthTimelineLoader(provider: provider, calendar: calendar).entries(on: day, isEnabled: true)
        #expect(result.isEmpty)
        #expect(provider.queryCount == 0)
    }

    @Test("Sleep failure keeps workouts")
    func sleepFailureKeepsWorkouts() async {
        let provider = StubHealthTimelineProvider()
        let run = entry(.workout(name: "Running"), hours: 7...8)
        provider.workouts = [run]
        provider.sleepFails = true
        let result = await HealthTimelineLoader(provider: provider, calendar: calendar).entries(on: day, isEnabled: true)
        #expect(result.map(\.id) == [run.id])
    }

    @Test("Workout failure keeps sleep")
    func workoutFailureKeepsSleep() async {
        let provider = StubHealthTimelineProvider()
        let night = entry(.sleep, hours: 0...7)
        provider.sleep = [night]
        provider.workoutsFails = true
        let result = await HealthTimelineLoader(provider: provider, calendar: calendar).entries(on: day, isEnabled: true)
        #expect(result.map(\.id) == [night.id])
    }

    @Test("Results are clipped to the day and sorted")
    func clipsAndSorts() async {
        let provider = StubHealthTimelineProvider()
        let night = entry(.sleep, hours: -2...7)
        let run = entry(.workout(name: "Running"), hours: 18...19)
        provider.sleep = [night]
        provider.workouts = [run]
        let result = await HealthTimelineLoader(provider: provider, calendar: calendar).entries(on: day, isEnabled: true)
        #expect(result.map(\.id) == [night.id, run.id])
        #expect(result.first?.interval.start == day)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `make test`
Expected: build failure, `cannot find type 'HealthTimelineProviding' in scope`.

- [ ] **Step 3: Write the implementation**

`Kado/Services/HealthTimelineProviding.swift`:

```swift
import Foundation
import KadoCore

/// Reads the Health intervals the Calendar overlays. Read-only: Kadō
/// never writes to Health. Sleep and workouts are separate calls so
/// one failing never hides the other.
protocol HealthTimelineProviding {
    /// False on devices without Health (some iPads). The Settings row
    /// is hidden and nothing is queried.
    var isAvailable: Bool { get }
    func requestAuthorization() async throws
    func sleepEntries(in interval: DateInterval) async throws -> [HealthTimelineEntry]
    func workoutEntries(in interval: DateInterval) async throws -> [HealthTimelineEntry]
}
```

`Kado/Services/PreviewHealthTimelineProvider.swift`:

```swift
import Foundation
import KadoCore

/// Environment default and preview fixture. Never touches HealthKit,
/// so previews and unit tests that forget to inject stay offline.
struct PreviewHealthTimelineProvider: HealthTimelineProviding {
    var isAvailable = true
    var sleep: [HealthTimelineEntry] = []
    var workouts: [HealthTimelineEntry] = []

    func requestAuthorization() async throws {}
    func sleepEntries(in interval: DateInterval) async throws -> [HealthTimelineEntry] { sleep }
    func workoutEntries(in interval: DateInterval) async throws -> [HealthTimelineEntry] { workouts }
}
```

`Kado/Services/HealthCalendarDefaults.swift`:

```swift
import Foundation

/// The "Health on Calendar" opt-in. Device-local `UserDefaults.standard`,
/// deliberately not synced: Health authorization is per device too.
enum HealthCalendarDefaults {
    static let key = "kado.healthOnCalendar"
}
```

`Kado/Services/HealthTimelineLoader.swift`:

```swift
import Foundation
import KadoCore
import OSLog

/// Loads one Calendar day's Health entries. Gated on the opt-in, so
/// a user who never enabled the feature never triggers a HealthKit
/// query. Each kind fails on its own and a failure never reaches the
/// Calendar: the day still renders its tasks.
struct HealthTimelineLoader {
    let provider: any HealthTimelineProviding
    let calendar: Calendar

    private static let logger = Logger(subsystem: "dev.scastiel.kado", category: "health-calendar")

    func entries(on day: Date, isEnabled: Bool) async -> [HealthTimelineEntry] {
        guard isEnabled, provider.isAvailable,
              let window = HealthTimelineClipper.queryInterval(around: day, calendar: calendar)
        else { return [] }
        let sleep = await attempt("sleep") { try await provider.sleepEntries(in: window) }
        let workouts = await attempt("workouts") { try await provider.workoutEntries(in: window) }
        return HealthTimelineClipper.entries(sleep + workouts, on: day, calendar: calendar)
    }

    /// Logs the error's type only: a description could carry Health data.
    private func attempt(_ kind: String, _ load: () async throws -> [HealthTimelineEntry]) async -> [HealthTimelineEntry] {
        do {
            return try await load()
        } catch {
            Self.logger.error("Health \(kind, privacy: .public) query failed: \(String(describing: type(of: error)), privacy: .public)")
            return []
        }
    }
}
```

Append inside the `extension EnvironmentValues { ... }` in `Kado/App/EnvironmentValues+Services.swift`, after `dayCompletionCelebration`:

```swift

    /// Reads sleep and workouts for the Calendar overlay. Default is a
    /// stub so previews and unit tests never touch HealthKit; the main
    /// app injects `HealthKitTimelineProvider()` at scene build.
    @Entry var healthTimelineProvider: any HealthTimelineProviding = PreviewHealthTimelineProvider()
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `make test`
Expected: `** TEST SUCCEEDED **`

- [ ] **Step 5: Commit**

```bash
git add Kado/Services/HealthTimelineProviding.swift Kado/Services/PreviewHealthTimelineProvider.swift \
  Kado/Services/HealthTimelineLoader.swift Kado/Services/HealthCalendarDefaults.swift \
  Kado/App/EnvironmentValues+Services.swift KadoTests/Mocks/StubHealthTimelineProvider.swift \
  KadoTests/HealthTimelineLoaderTests.swift
git commit -m "feat(health): add health timeline provider seam and loader"
```

---

### Task 4: Live HealthKit provider and project configuration

**Goal:** Real HealthKit reads, the entitlement, the localized usage description, and injection at scene build.

**Files:**
- Create: `Kado/Services/HealthKitTimelineProvider.swift`
- Create: `Kado/Services/HKWorkoutActivityType+DisplayName.swift`
- Create: `Kado/Resources/InfoPlist.xcstrings`
- Modify: `Kado/Kado.entitlements`
- Modify: `Kado/Info.plist`
- Modify: `Kado/App/KadoApp.swift:187-203` (environment chain)
- Modify: `Kado/Resources/Localizable.xcstrings` (workout names)

**Acceptance Criteria:**
- [ ] App target builds with HealthKit; widget and Watch targets unchanged.
- [ ] `NSHealthShareUsageDescription` present in EN and FR; no `NSHealthUpdateUsageDescription`.
- [ ] `make deployment-check` passes.
- [ ] `LocalizationCoverageTests` passes.

**Verify:** `make build && make deployment-check && make test` → all succeed.

**Steps:**

- [ ] **Step 1: Add the entitlement**

In `Kado/Kado.entitlements`, inside the top `<dict>`, after the `com.apple.security.application-groups` array:

```xml
	<key>com.apple.developer.healthkit</key>
	<true/>
	<key>com.apple.developer.healthkit.access</key>
	<array/>
```

Do not add `UIRequiredDeviceCapabilities` → `healthkit`: that would block install on iPads without Health, where the feature is simply hidden.

- [ ] **Step 2: Add the usage description**

In `Kado/Info.plist`, inside the top `<dict>`, after the `CFBundleSpokenName` entry:

```xml
	<key>NSHealthShareUsageDescription</key>
	<string>Kadō shows your sleep and workouts on your Calendar. This data stays on your device.</string>
```

Create `Kado/Resources/InfoPlist.xcstrings`:

```json
{
  "sourceLanguage" : "en",
  "strings" : {
    "NSHealthShareUsageDescription" : {
      "comment" : "Health permission prompt: why Kadō reads sleep and workouts.",
      "extractionState" : "manual",
      "localizations" : {
        "en" : { "stringUnit" : { "state" : "translated", "value" : "Kadō shows your sleep and workouts on your Calendar. This data stays on your device." } },
        "fr" : { "stringUnit" : { "state" : "translated", "value" : "Kadō affiche ton sommeil et tes entraînements dans ton Calendrier. Ces données restent sur ton appareil." } }
      }
    }
  },
  "version" : "1.0"
}
```

Before writing the file, check how `Localizable.xcstrings` spells its top-level `version` and `extractionState`, and match it.

- [ ] **Step 3: Write the workout display names**

`Kado/Services/HKWorkoutActivityType+DisplayName.swift`:

```swift
import HealthKit

extension HKWorkoutActivityType {
    /// HealthKit has no public localized name for an activity type.
    /// The common ones get a name; everything else reads "Workout".
    var displayName: String {
        switch self {
        case .running: String(localized: "Running", comment: "Workout type shown on the Calendar timeline.")
        case .walking: String(localized: "Walking", comment: "Workout type shown on the Calendar timeline.")
        case .cycling: String(localized: "Cycling", comment: "Workout type shown on the Calendar timeline.")
        case .swimming: String(localized: "Swimming", comment: "Workout type shown on the Calendar timeline.")
        case .hiking: String(localized: "Hiking", comment: "Workout type shown on the Calendar timeline.")
        case .yoga: String(localized: "Yoga", comment: "Workout type shown on the Calendar timeline.")
        case .traditionalStrengthTraining, .functionalStrengthTraining:
            String(localized: "Strength training", comment: "Workout type shown on the Calendar timeline.")
        case .highIntensityIntervalTraining: String(localized: "HIIT", comment: "Workout type shown on the Calendar timeline.")
        case .rowing: String(localized: "Rowing", comment: "Workout type shown on the Calendar timeline.")
        case .elliptical: String(localized: "Elliptical", comment: "Workout type shown on the Calendar timeline.")
        default: String(localized: "Workout", comment: "Generic workout name shown on the Calendar timeline.")
        }
    }
}
```

Add each key to `Kado/Resources/Localizable.xcstrings` with the comment above and FR values: Running → Course, Walking → Marche, Cycling → Vélo, Swimming → Natation, Hiking → Randonnée, Yoga → Yoga, Strength training → Renforcement musculaire, HIIT → HIIT, Rowing → Aviron, Elliptical → Elliptique, Workout → Entraînement. Match the JSON shape of a neighbouring entry exactly.

- [ ] **Step 4: Write the live provider**

`Kado/Services/HealthKitTimelineProvider.swift`:

```swift
import Foundation
import HealthKit
import KadoCore

/// Live HealthKit reads for the Calendar overlay. Read-only; nothing
/// it returns is stored, synced, or exported.
final class HealthKitTimelineProvider: HealthTimelineProviding {
    private let store = HKHealthStore()
    private let sleepType = HKCategoryType(.sleepAnalysis)

    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    func requestAuthorization() async throws {
        try await store.requestAuthorization(toShare: [], read: [sleepType, HKObjectType.workoutType()])
    }

    func sleepEntries(in interval: DateInterval) async throws -> [HealthTimelineEntry] {
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.categorySample(type: sleepType, predicate: Self.overlapping(interval))],
            sortDescriptors: [SortDescriptor(\.startDate)]
        )
        let samples = try await descriptor.result(for: store)
        return SleepSessionBuilder.sessions(from: samples.compactMap(Self.sleepSample))
    }

    func workoutEntries(in interval: DateInterval) async throws -> [HealthTimelineEntry] {
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.workout(Self.overlapping(interval))],
            sortDescriptors: [SortDescriptor(\.startDate)]
        )
        let workouts = try await descriptor.result(for: store)
        return workouts.map { workout in
            HealthTimelineEntry(
                id: workout.uuid,
                kind: .workout(name: workout.workoutActivityType.displayName),
                interval: DateInterval(start: workout.startDate, end: max(workout.startDate, workout.endDate))
            )
        }
    }

    /// Samples that overlap the window at all, not only ones inside it.
    private static func overlapping(_ interval: DateInterval) -> NSPredicate {
        HKQuery.predicateForSamples(withStart: interval.start, end: interval.end, options: [])
    }

    private static func sleepSample(_ sample: HKCategorySample) -> SleepSample? {
        guard let value = HKCategoryValueSleepAnalysis(rawValue: sample.value) else { return nil }
        let stage: SleepSample.Stage
        switch value {
        case .inBed: stage = .inBed
        case .awake: stage = .awake
        case .asleepUnspecified, .asleepCore, .asleepDeep, .asleepREM: stage = .asleep
        @unknown default: return nil
        }
        return SleepSample(id: sample.uuid, stage: stage,
                           interval: DateInterval(start: sample.startDate, end: max(sample.startDate, sample.endDate)))
    }
}
```

- [ ] **Step 5: Inject at scene build**

In `Kado/App/KadoApp.swift`, add a stored property next to `googleCalendarConnection` (line 20):

```swift
    @State private var healthTimelineProvider = HealthKitTimelineProvider()
```

In the environment chain, after `.environment(\.googleCalendarConnection, googleCalendarConnection)` (line 188):

```swift
        .environment(\.healthTimelineProvider, healthTimelineProvider)
```

- [ ] **Step 6: Build and check**

Run: `make build`
Expected: `** BUILD SUCCEEDED **` with no new warnings. If signing fails because the provisioning profile lacks HealthKit, stop and ask the user to enable the HealthKit capability for the App ID in Xcode → Signing & Capabilities.

Run: `make deployment-check`
Expected: success, no target listed.

Run: `make test`
Expected: `** TEST SUCCEEDED **` (including `LocalizationCoverageTests`).

- [ ] **Step 7: Commit**

```bash
git add Kado/Services/HealthKitTimelineProvider.swift "Kado/Services/HKWorkoutActivityType+DisplayName.swift" \
  Kado/Resources/InfoPlist.xcstrings Kado/Resources/Localizable.xcstrings Kado/Kado.entitlements Kado/Info.plist Kado/App/KadoApp.swift
git commit -m "feat(health): read sleep and workouts from HealthKit"
```

---

### Task 5: Draw Health entries on the Calendar timeline

**Goal:** Sleep as a background band, workouts as read-only lane cards, both in the accessible agenda; the Calendar loads entries per day.

**Files:**
- Modify: `Kado/Views/Calendar/CalendarBlockItem.swift`
- Modify: `Kado/Views/Calendar/CalendarDayTimeline.swift`
- Modify: `Kado/Views/Calendar/PlannerCalendarView.swift`
- Modify: `Shared/AccessibilityID.swift` (`enum Calendar`)
- Modify: `Kado/Resources/Localizable.xcstrings`

**Acceptance Criteria:**
- [ ] Sleep band spans the content width behind cards, takes no lane, and passes taps through.
- [ ] Workout cards sit in lanes, show name, time range, and "Health", and have no tap, menu, or completion action.
- [ ] Accessible agenda lists sleep and workout rows in start order with task blocks.
- [ ] VoiceOver reads "Sleep, <range>" and "<name> workout, <range>, from Health".
- [ ] Entries reload on day change, on toggle change, and when the scene becomes active.

**Verify:** `make build && make test` succeed; previews "Health overlay" and "Dark" render; `make run` + `make shot` shows the band and a workout card.

**Steps:**

- [ ] **Step 1: Health-backed block item**

In `Kado/Views/Calendar/CalendarBlockItem.swift`, add a stored property after `isComplete`:

```swift
    /// Non-nil for a read-only Health entry (sleep or workout).
    let healthKind: HealthTimelineEntry.Kind?

    var isFromHealth: Bool { healthKind != nil }
```

Set `healthKind = nil` at the end of `init(_ record:on:calendar:)`, and add `healthKind: HealthTimelineEntry.Kind? = nil` as the last parameter of the memberwise-style `init(id:title:schedule:task:habitID:isComplete:)` with `self.healthKind = healthKind`. Then add:

```swift
    init(_ entry: HealthTimelineEntry) {
        id = entry.id
        switch entry.kind {
        case .sleep: title = String(localized: "Sleep", comment: "Calendar timeline: a sleep session read from Health.")
        case .workout(let name): title = name
        }
        schedule = TaskScheduleItem(id: entry.id, plannedDay: entry.interval.start,
                                    startAt: entry.interval.start, endAt: entry.interval.end)
        task = nil
        habitID = nil
        isComplete = false
        healthKind = entry.kind
    }
```

- [ ] **Step 2: Accessibility identifiers**

In `Shared/AccessibilityID.swift`, inside `enum Calendar`, after `completeMenuItem`:

```swift
        static let healthPrefix = "calendar.health."
        static func health(_ id: UUID) -> String { healthPrefix + id.uuidString }
```

- [ ] **Step 3: Timeline input and derived lists**

In `Kado/Views/Calendar/CalendarDayTimeline.swift`, add after `let blocks: [CalendarBlockItem]`:

```swift
    /// Already clipped to `day`. Defaults to empty so existing call
    /// sites and previews compile unchanged.
    var healthEntries: [HealthTimelineEntry] = []
```

Add these computed properties after `dayInterval`:

```swift
    private var sleepItems: [CalendarBlockItem] {
        healthEntries.filter { $0.kind == .sleep }.map(CalendarBlockItem.init)
    }

    /// Workouts share lanes with planned blocks; sleep never takes a lane.
    private var laneBlocks: [CalendarBlockItem] {
        blocks + healthEntries.filter { $0.kind != .sleep }.map(CalendarBlockItem.init)
    }

    private var agendaItems: [CalendarBlockItem] {
        (blocks + healthEntries.map(CalendarBlockItem.init))
            .sorted { ($0.schedule.startAt ?? $0.schedule.plannedDay) < ($1.schedule.startAt ?? $1.schedule.plannedDay) }
    }
```

In `placements(in:)`, replace `let sorted = blocks.sorted {` with `let sorted = laneBlocks.sorted {`.

- [ ] **Step 4: Sleep band layer and lane card dispatch**

In `timeline`, replace the `ZStack` body with:

```swift
            ZStack(alignment: .topLeading) {
                hourGrid(in: interval, width: geometry.size.width)
                ForEach(sleepItems) { item in
                    let frame = bandFrame(item, in: interval)
                    sleepBand(item)
                        .frame(width: max(80, geometry.size.width - labelWidth - 8), height: frame.height)
                        .offset(x: labelWidth, y: frame.y)
                }
                ForEach(layout) { placement in
                    let lanes = max(1, placement.laneCount)
                    let available = max(80, geometry.size.width - labelWidth - 8)
                    let laneWidth = available / CGFloat(lanes)
                    laneCard(placement.block)
                        .frame(width: max(44, laneWidth - 6), height: placement.height, alignment: .topLeading)
                        .offset(x: labelWidth + CGFloat(placement.lane) * laneWidth, y: placement.y)
                }
            }
```

Add after `hourGrid(in:width:)`:

```swift
    private func bandFrame(_ item: CalendarBlockItem, in interval: DateInterval) -> (y: CGFloat, height: CGFloat) {
        let start = max(item.schedule.startAt ?? interval.start, interval.start)
        let end = min(item.schedule.endAt ?? interval.end, interval.end)
        let y = CGFloat(start.timeIntervalSince(interval.start) / 60) * pointsPerMinute
        return (y, max(24, CGFloat(end.timeIntervalSince(start) / 60) * pointsPerMinute))
    }

    /// Behind the cards and blind to taps, so planned blocks on top
    /// stay fully interactive.
    private func sleepBand(_ item: CalendarBlockItem) -> some View {
        RoundedRectangle(cornerRadius: KadoRadius.sm)
            .fill(Color.kadoBackgroundSecondary)
            .overlay(alignment: .topTrailing) {
                Label(item.title, systemImage: "bed.double.fill")
                    .font(.caption2)
                    .lineLimit(1)
                    .foregroundStyle(Color.kadoForegroundSecondary)
                    .padding(6)
            }
            .allowsHitTesting(false)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(item.title)
            .accessibilityValue(item.schedule.timeLabel)
            .accessibilityIdentifier(AccessibilityID.Calendar.health(item.id))
    }

    @ViewBuilder
    private func laneCard(_ block: CalendarBlockItem) -> some View {
        if block.isFromHealth { workoutCard(block) } else { timelineCard(block) }
    }

    /// Read-only: no button, no menu, no completion.
    private func workoutCard(_ block: CalendarBlockItem) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Label(block.title, systemImage: "figure.run")
                .font(.caption.weight(.semibold))
                .lineLimit(2)
            Text(block.schedule.timeLabel)
                .font(.caption2)
                .lineLimit(2)
            Text("Health", comment: "Calendar timeline caption: this entry comes from Apple Health.")
                .font(.caption2)
                .lineLimit(1)
        }
        .foregroundStyle(Color.kadoForegroundSecondary)
        .padding(8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.kadoBackgroundSecondary, in: RoundedRectangle(cornerRadius: KadoRadius.sm))
        .overlay(RoundedRectangle(cornerRadius: KadoRadius.sm).strokeBorder(Color.kadoHairline))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(block.title) workout", comment: "VoiceOver label for a Health workout on the Calendar, e.g. 'Running workout'."))
        .accessibilityValue(Text("\(block.schedule.timeLabel), from Health", comment: "VoiceOver value for a Health workout: its time range and source."))
        .accessibilityIdentifier(AccessibilityID.Calendar.health(block.id))
    }
```

- [ ] **Step 5: Accessible agenda**

In `accessibleAgenda`, replace the `ForEach(blocks.sorted { ... }) { block in` line with `ForEach(agendaItems) { block in`, and make the first branch:

```swift
                if block.isFromHealth {
                    VStack(alignment: .leading) {
                        Label(block.title, systemImage: block.healthKind == .sleep ? "bed.double.fill" : "figure.run")
                        Text(block.schedule.timeLabel).font(.caption)
                    }
                    .foregroundStyle(Color.kadoForegroundSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(Color.kadoBackgroundSecondary, in: RoundedRectangle(cornerRadius: KadoRadius.card))
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier(AccessibilityID.Calendar.health(block.id))
                } else if let task = block.task {
```

(the existing `if let task = block.task {` becomes `} else if let task = block.task {`; the rest is unchanged).

- [ ] **Step 6: Preview with Health entries**

Add to `CalendarTimelinePreview`:

```swift
    static let health = [
        HealthTimelineEntry(id: UUID(), kind: .sleep,
            interval: DateInterval(start: day, end: calendar.date(bySettingHour: 7, minute: 10, second: 0, of: day)!)),
        HealthTimelineEntry(id: UUID(), kind: .workout(name: "Running"),
            interval: DateInterval(start: calendar.date(bySettingHour: 7, minute: 30, second: 0, of: day)!,
                                   end: calendar.date(bySettingHour: 8, minute: 15, second: 0, of: day)!)),
    ]
```

Add a preview, and pass `healthEntries: CalendarTimelinePreview.health` to the existing `"Dark"` preview so the demanding state is dark:

```swift
#Preview("Health overlay") {
    ScrollView {
        CalendarDayTimeline(day: CalendarTimelinePreview.day, blocks: CalendarTimelinePreview.blocks,
            healthEntries: CalendarTimelinePreview.health,
            onToggle: { _ in }, onEdit: { _ in }, onDelete: { _ in })
            .padding()
    }
    .background(Color.kadoBackground)
    .kadoTheme()
}
```

- [ ] **Step 7: Load entries in the Calendar**

In `Kado/Views/Calendar/PlannerCalendarView.swift`, add properties after `isDevMode`:

```swift
    @Environment(\.healthTimelineProvider) private var healthProvider
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(HealthCalendarDefaults.key) private var showsHealth = false
    @State private var healthEntries: [HealthTimelineEntry] = []

    /// Reload when the day, the opt-in, or foreground state changes.
    private struct HealthReloadKey: Hashable {
        let day: Date
        let isEnabled: Bool
        let isActive: Bool
    }
```

Pass the entries to the timeline:

```swift
                    CalendarDayTimeline(
                        day: day, blocks: timed, healthEntries: healthEntries,
                        onToggle: { if let taskID = $0.task?.id { toggleTask(taskID) } },
                        onEdit: openBlock,
                        onDelete: { deletingTaskID = $0.task?.id }
                    )
```

Add after `.onAppear { if selectedDay == nil { ... } }` in `body`:

```swift
            .task(id: HealthReloadKey(day: day, isEnabled: showsHealth, isActive: scenePhase == .active)) {
                guard scenePhase == .active else { return }
                let loaded = await HealthTimelineLoader(provider: healthProvider, calendar: calendar)
                    .entries(on: day, isEnabled: showsHealth)
                // A superseded load (the user moved to another day) must not
                // overwrite the newer day's entries.
                guard !Task.isCancelled else { return }
                healthEntries = loaded
            }
```

The "Your day is open" empty state stays keyed on tasks only: it invites planning, and Health entries are not planned work.

- [ ] **Step 8: Strings**

Add to `Kado/Resources/Localizable.xcstrings` (EN key → FR): `Sleep` → `Sommeil`; `Health` → `Santé`; `%@ workout` → `Entraînement : %@`; `%@, from Health` → `%@, depuis Santé`. Use the comments from the code.

- [ ] **Step 9: Build, test, and look**

Run: `make build && make test`
Expected: both succeed, no new warnings.

Open the "Health overlay" and "Dark" previews and check: band behind cards, label not covering card text, workout card distinct from task cards.

Run: `make run`, add a sleep sample and a workout in the simulator's Health app (Browse → Sleep / Workouts → Add Data), enable the toggle (Task 6 adds it; until then set it with `xcrun simctl spawn booted defaults write dev.scastiel.kado kado.healthOnCalendar -bool YES`), open Calendar, then `make shot`. Inspect `build/screenshot.png`.

- [ ] **Step 10: Commit**

```bash
git add Kado/Views/Calendar/CalendarBlockItem.swift Kado/Views/Calendar/CalendarDayTimeline.swift \
  Kado/Views/Calendar/PlannerCalendarView.swift Shared/AccessibilityID.swift Kado/Resources/Localizable.xcstrings
git commit -m "feat(calendar): overlay health sleep and workouts on the timeline"
```

---

### Task 6: Settings opt-in

**Goal:** A Settings section that turns the overlay on with a read-only authorization request, explains empty data, and opens Health.

**Files:**
- Create: `Kado/Views/Settings/HealthCalendarSection.swift`
- Modify: `Kado/Views/Settings/SettingsView.swift` (after the Google Calendar `Section`)
- Modify: `Shared/AccessibilityID.swift` (`enum Settings`)
- Modify: `Kado/Resources/Localizable.xcstrings`

**Acceptance Criteria:**
- [ ] Section hidden when Health is unavailable.
- [ ] Turning on requests authorization once, then stores `true`; a thrown request leaves it off.
- [ ] Turning off stores `false` and the Calendar stops querying.
- [ ] A double tap cannot start two requests.
- [ ] Footer explains how to check access; "Open Health" button shown when on.

**Verify:** `make build && make test` succeed; manual toggle in simulator shows the system Health sheet once.

**Steps:**

- [ ] **Step 1: Identifier**

In `Shared/AccessibilityID.swift`, inside `enum Settings`, after `devModeToggle`:

```swift
        static let healthOnCalendarToggle = "settings.healthOnCalendar.toggle"
```

- [ ] **Step 2: The section**

`Kado/Views/Settings/HealthCalendarSection.swift`:

```swift
import OSLog
import SwiftUI

/// Opt-in for the Calendar's Health overlay. HealthKit never reports
/// a denied read, so the footer tells the user where to check instead
/// of the app guessing at an error.
struct HealthCalendarSection: View {
    @Environment(\.healthTimelineProvider) private var provider
    @Environment(\.openURL) private var openURL
    @AppStorage(HealthCalendarDefaults.key) private var showsHealth = false
    @State private var isRequesting = false

    private static let logger = Logger(subsystem: "dev.scastiel.kado", category: "health-calendar")

    var body: some View {
        if provider.isAvailable {
            Section {
                Toggle(isOn: toggleBinding) {
                    Label("Health on Calendar", systemImage: "heart.text.square")
                }
                .disabled(isRequesting)
                .accessibilityIdentifier(AccessibilityID.Settings.healthOnCalendarToggle)
                if showsHealth {
                    Button("Open Health") {
                        // Undocumented but long-stable scheme; a failure
                        // simply does nothing, and the footer still guides.
                        if let url = URL(string: "x-apple-health://") { openURL(url) }
                    }
                }
            } footer: {
                if showsHealth {
                    Text("No data showing? Check Settings → Privacy & Security → Health → Kadō.")
                } else {
                    Text("Show your sleep and workouts on the Calendar. Read-only, and the data stays on your device.")
                }
            }
        }
    }

    /// The disabling flag is set synchronously before the Task, so two
    /// taps in one runloop tick cannot both request.
    private var toggleBinding: Binding<Bool> {
        Binding(
            get: { showsHealth },
            set: { isOn in
                guard isOn else { showsHealth = false; return }
                guard !isRequesting else { return }
                isRequesting = true
                Task {
                    defer { isRequesting = false }
                    do {
                        try await provider.requestAuthorization()
                        showsHealth = true
                    } catch {
                        Self.logger.error("Health authorization failed: \(String(describing: type(of: error)), privacy: .public)")
                        showsHealth = false
                    }
                }
            }
        )
    }
}

#Preview("Off") {
    Form { HealthCalendarSection() }
        .environment(\.healthTimelineProvider, PreviewHealthTimelineProvider())
        .kadoTheme()
}

#Preview("Dark") {
    Form { HealthCalendarSection() }
        .environment(\.healthTimelineProvider, PreviewHealthTimelineProvider())
        .kadoTheme()
        .preferredColorScheme(.dark)
}
```

- [ ] **Step 3: Place it**

In `Kado/Views/Settings/SettingsView.swift`, right after the `Section { NavigationLink { GoogleCalendarSettingsView() } ... }` block:

```swift
                HealthCalendarSection()
```

- [ ] **Step 4: Strings**

Add to `Kado/Resources/Localizable.xcstrings` with comments (EN → FR):
- `Health on Calendar` → `Santé dans le Calendrier`
- `Open Health` → `Ouvrir Santé`
- `No data showing? Check Settings → Privacy & Security → Health → Kadō.` → `Aucune donnée ? Vérifie Réglages → Confidentialité et sécurité → Santé → Kadō.`
- `Show your sleep and workouts on the Calendar. Read-only, and the data stays on your device.` → `Affiche ton sommeil et tes entraînements dans le Calendrier. Lecture seule, et les données restent sur ton appareil.`

- [ ] **Step 5: Build, test, check by hand**

Run: `make build && make test`
Expected: both succeed.

Run: `make run`. In Settings, turn on "Health on Calendar": the Health permission sheet appears with Sleep and Workouts under "read". Allow, open Calendar, confirm entries. Turn off: entries disappear. Capture `make shot`.

- [ ] **Step 6: Commit**

```bash
git add Kado/Views/Settings/HealthCalendarSection.swift Kado/Views/Settings/SettingsView.swift \
  Shared/AccessibilityID.swift Kado/Resources/Localizable.xcstrings
git commit -m "feat(settings): add health on calendar opt-in"
```

---

### Task 7: Roadmap and privacy notes

**Goal:** Record that this is display-only and does not reverse the auto-completion descope; document the data handling.

**Files:**
- Modify: `docs/ROADMAP.md` (section "HealthKit auto-completion — descoped 2026-09-05")
- Modify: `PRIVACY.md`

**Acceptance Criteria:**
- [ ] ROADMAP note says the overlay is display-only, opt-in, and changes no score or completion.
- [ ] PRIVACY says what is read, when, and that it is never stored, synced, or exported.

**Verify:** `git diff --stat` shows only the two files; read both sections back.

**Steps:**

- [ ] **Step 1: ROADMAP**

At the end of the "HealthKit auto-completion — descoped 2026-09-05" section, before the next heading, add:

```markdown
**Not reversed by Health on Calendar (2026-10).** The Calendar can
show sleep and workouts read from Health, opt-in from Settings. It
is display-only: nothing completes, no score moves, and you still
decide what counts. Spec:
`docs/superpowers/specs/2026-10-04-health-calendar-overlay-design.md`.
```

- [ ] **Step 2: PRIVACY**

Read `PRIVACY.md` first and add a section in its existing style:

```markdown
## Apple Health

If you turn on **Health on Calendar** in Settings, Kadō asks for
read-only access to your sleep and workouts. It reads them only to
draw them on the Calendar, on your device. Kadō never writes to
Health, and never stores, syncs to iCloud, exports, or sends this
data anywhere. Turn the setting off, or remove access in
Settings → Privacy & Security → Health → Kadō, at any time.
```

- [ ] **Step 3: Commit**

```bash
git add docs/ROADMAP.md PRIVACY.md
git commit -m "docs(health): note calendar overlay in roadmap and privacy"
```

---

## Final verification (after Task 7)

- `make build`, `make test`, `make deployment-check` all succeed.
- Manual on iPhone 17 Pro (iOS 26.x) and iPad Air simulator: light and dark, Dynamic Type XXXL (agenda layout lists Health rows), VoiceOver reads sleep and workout labels.
- PR "Next steps": FR strings need native-speaker review; HealthKit capability must be on the App ID before TestFlight.
