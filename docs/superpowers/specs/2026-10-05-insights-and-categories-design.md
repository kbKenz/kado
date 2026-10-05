# Insights and categories — design

Date: 2026-10-05
Status: Approved by the owner's brief (autonomous build, no review round)
Branch: `feature/insights`

## Goal

Two features that make Kadō easier to read and easier to fill in:

1. **Insights**: a long, scrolling feed of metric cards inside the
   Overview tab, in the spirit of Whoop and Ultrahuman. It answers "how
   consistent am I?" with numbers the user did not have to type.
2. **Categories with suggestions**: every task, habit and goal gets a
   category (with an icon). While the user types a title, Kadō fills
   in the category, the habit icon and the goal, on device. Example:
   with a goal "Get into Cambridge", the task "Contact professors at
   Cambridge" gets the Study category and that goal by itself.

```
OVERVIEW                    [ Insights | Grid ]
[ Week | Month | Year ]           Last 30 days

 ◔ 82%        ◔ 64%        ◔ 90%
 Habits       Tasks        Active days
 ▲ 6 pts      ▼ 3 pts      =

✦ Highlights
  • Meditate: 23 days, your best streak ever
  • Errands are most often left undone (3 of 8)
  • Mornings are your focus time (62%)

Activity        ▢▢▣▣▣▢▣  (heat map)
Focus 12 h 40 min   ▁▃▅▂▇▄▆  (bars by category)
Categories      Study 6 h · 12 done · 80%
Sleep           7 h 12 min avg · 78% consistent
Movement        12 workouts · avg 42 min
Habits          Read: 42 times · 18 h
Tasks           31 done · 9 left undone
Goals           Get into Cambridge  ▓▓▓░░ on track
Rhythm          Best day: Tuesday
All time        214 days · 1,240 times done
```

## Decisions

| Question | Decision |
|---|---|
| Where Insights live | Inside Overview, behind a segmented **Insights / Grid** switch (the Today List / Calendar pattern). The grid stays as it is. Default: Insights. Kept in `@AppStorage("kado.overviewMode")`. |
| Time window | One segmented **Week / Month / Year** picker for the whole feed: the last 7, 30 or 365 logical days, compared with the run just before. Default Month. Kept in `@AppStorage("kado.insightsPeriod")`. |
| What a category is | A fixed set of 12 (`ItemCategory`): Work, Study, Fitness, Health, Sleep, Mind, People, Home, Money, Creative, Errands, Other. Each has an SF Symbol and a palette slot. No user-made categories in this version (backlog #9 "Areas of life" stays open). |
| Who has a category | Tasks, habits and goals. Stored as `categoryRaw: String = ""` (schema V9); empty means "not set". |
| Category for an item without one | `CategoryResolver`: stored value, else the linked goal's category, else the keyword classifier on the title, else Other. Reads never write. |
| Icons | Tasks and goals show their category's symbol. Habits keep their own icon; a new habit starts with the suggested one. Five category icons join `HabitIcon.curated`. |
| Suggestions | Typing a title fills the category, the goal (tasks and habits) and the icon (new habits), unless the user already chose that field. A small "Suggested" mark with sparkles shows what the app filled in. |
| Suggestion engine | `KeywordItemSuggester` (deterministic, EN + FR keywords, title-to-goal word overlap) always runs. `FoundationModelsItemSuggester` (iOS 26, Apple Intelligence, on device) refines it when available. Only listed categories, curated icons and existing goal IDs are accepted. No network, no cloud fallback. |
| Apple Health in Insights | Sleep and workouts are read live for the Sleep and Movement cards, behind the same opt-in as the Calendar (`kado.healthOnCalendar`). Never stored, synced or exported. Without it, the cards use Sleep and Fitness habits and offer "Connect Apple Health". |
| Wording | Neutral: "left undone", never "failed" or "dropped". No badges, no confetti, no ranking against others. |
| AI suggestions vs. ROADMAP | ROADMAP lists "AI-assisted habit suggestions" under "do not do without proof of real need". The owner asked for this feature, which is that proof. ROADMAP and PRIVACY.md change on this branch. |

### Approaches not used

- **Free tags** (backlog #17): more flexible, but every insight then
  needs a tag picker and the user has to type. A fixed set needs zero
  setup and lets the app suggest.
- **A sixth tab**: the tab bar is full on iPhone.
- **Per-card time pickers**: more input for little gain.

## Insights feed

A `ScrollView` with a `LazyVStack` of cards, 640 pt wide at most. Each
card: a title row (SF Symbol + title), content, and a one-sentence
VoiceOver summary. Cards with nothing to say hide, except Focus, Sleep
and Movement, which explain how to get data (start a session, connect
Health, add a habit with one tap).

| # | Card | Shows |
|---|---|---|
| 1 | Pulse | Three rings: habit consistency, task follow-through, active days, each with the change against the previous period. |
| 2 | Highlights | Up to 4 facts, picked by rules (`InsightsHighlight`). |
| 3 | Activity | Heat map of the period in week columns; perfect days and the longest perfect run. |
| 4 | Focus | Total tracked time and change; bars per day (or month) stacked by category; sessions, average, longest; time against plan. |
| 5 | Categories | One row per category: focus time, times done, consistency, tasks left undone. |
| 6 | Sleep | Health: average sleep, 7 h+ nights, bedtime consistency (within 45 min of the median), nightly bars. Sleep habits' consistency. |
| 7 | Movement | Health workouts: count, average length, most frequent type. Fitness habits and tasks: times done, average time. |
| 8 | Habits | Each active habit: consistency, times done, total amount (hours for timers, units for counters), streak. Tap opens the habit. |
| 9 | Tasks | Done, left undone, on time, average days to finish, categories most often left undone, open overdue tasks. |
| 10 | Goals | Each active goal: progress, linked tasks done, pace (ahead / on track / behind), days left. Tap opens the goal. |
| 11 | Rhythm | Consistency by weekday (best day marked); focus by part of the day. |
| 12 | All time | Days since the first record, times done, tasks done, focus hours, best streak ever. |

Every number's exact rule is a doc comment on its field in
`Packages/KadoCore/Sources/KadoCore/Insights/InsightsReport.swift`.
The rules that matter most:

- **Habit days are logical days** (the "Day starts at" hour); tasks
  and Health use civil days; a session belongs to the logical day it
  started on.
- **Consistency** = due habit-days done / due habit-days.
  `FrequencyEvaluating.isCounted` decides "due"; `DailyValue >= 1`
  decides "done" (full target for counters and timers, no slip for
  negative habits). Today counts only once it is done (grace day),
  and never for a negative habit.
- **Left undone** = a task with no completion whose last planned day
  (else due day) is in the period and before today.
- **Focus time** comes only from work sessions. Timer completion
  seconds are never added on top, because finishing a timer-habit
  session already writes them.

## Categories and suggestions

### Forms

- **Task form**: a Category row in its own section after Schedule
  (also editable on imported tasks, like the goal).
- **Habit form**: a Category row next to the goal picker (below
  Reminder, so the App Store screenshot keeps its layout).
- **Goal form**: a Category row after Details.
- The goal picker gets a "Suggested" footer with sparkles when the app
  chose the goal.

### Behavior

1. On each title change, after 400 ms without typing, the form asks
   the suggester (`ItemSuggesting`) with the title, the kind of item
   and the active goals.
2. The keyword result is applied at once; the on-device model result,
   when it arrives, replaces it if the title has not changed since.
3. A field the user set by hand is never changed again
   (`SuggestionOrigin.user`). Fields filled by the app stay
   `.suggested` and follow the title.
4. An existing item without a category shows the resolved category as
   suggested; saving stores it.
5. A form opened from a goal never changes that goal.

### Keyword suggester

- Category: word lists in English and French, matched on whole words
  after folding case and accents ("Contact professors at Cambridge" →
  Study via "professor").
- Goal: words of 4 letters or more that the title shares with a goal
  name, after dropping common words; the best goal wins if it shares
  at least one such word ("Cambridge"). Ties → no suggestion.
- Habit icon: keyword → curated icon ("read" → `book.fill`), else the
  category's default icon.

### On-device model

`FoundationModelsItemSuggester` (iOS 26, `@available`) sends only the
title and the numbered list of active goal names. It answers with a
`@Generable` value: a category (closed list), a goal number (0 = none)
and, for habits, an icon (closed list). Answers outside the lists are
dropped. Unavailable model, unsupported language or any error → the
keyword result.

## Data

`KadoSchemaV9` adds one attribute to three models:

```swift
public var categoryRaw: String = ""   // TaskRecord, HabitRecord, GoalRecord
public var category: ItemCategory? {   // typed accessor, same 3 models
    get { ItemCategory(storedRaw: categoryRaw) }
    set { categoryRaw = newValue?.rawValue ?? "" }
}
```

- Lightweight migration V8 → V9. All V8 typealiases move to V9.
- `Habit.category`, `TaskListItem.category`, `GoalListItem.category`.
- Backup format 6: `category` in JSON (habits, tasks, goals) and a new
  CSV column. Older files import with no category and never erase one.
- **CloudKit**: deploy the V9 schema to Production before the next
  TestFlight or App Store build. V8 is not deployed yet either; one
  deploy covers both.

## Units

| Unit | Layer | Job |
|---|---|---|
| `ItemCategory` | KadoCore value | The 12 categories: symbol, palette slot, default habit icon, name. |
| `CategoryClassifier` | KadoCore, pure | Title → category by keywords (EN + FR). |
| `CategoryResolver` | KadoCore, pure | Stored → goal → keywords → Other. |
| `GoalMatcher` | KadoCore, pure | Title + goals → best goal by shared words. |
| `HabitIconSuggester` | KadoCore, pure | Title + category → curated icon. |
| `ItemSuggesting` | App protocol | `KeywordItemSuggester`, `FoundationModelsItemSuggester`, `UnavailableItemSuggester` (environment default). |
| `InsightsCalculator` | KadoCore, pure | `InsightsInput` + `InsightsContext` → `InsightsReport`, one file per section. |
| `InsightsInputBuilder` | App, SwiftData | Fetches records and Health, resolves categories, builds `InsightsInput`. |
| `InsightsView` + cards | App UI | Renders a report. Never computes a number. |

## Accessibility and localization

- Each card is one VoiceOver element with a full sentence ("Habits,
  82 percent consistent, up 6 points").
- Text uses text styles; rings and heat-map cells use `@ScaledMetric`.
  Heat-map cells keep a visible outline for "nothing due", so color is
  never the only signal.
- All new strings in `Localizable.xcstrings`, FR with `tu`,
  `needs_review` for the native speaker. Durations, percents and dates
  use system formatters.
- Identifiers: `AccessibilityID.Insights` and
  `AccessibilityID.Suggestion`.

## Privacy

- Suggestions run on device. The model receives the title being typed
  and the names of active goals, nothing else.
- Health data in Insights is read live, shown, and dropped.
  PRIVACY.md says so. The system permission text
  (`NSHealthShareUsageDescription`) still names only the Calendar; it
  changes in a follow-up because `InfoPlist.xcstrings` has local edits
  on the owner's machine.

## Out of scope

- User-made categories, tags, filters by category in Today.
- Editing past sessions, planned-vs-actual per block.
- Widgets for Insights.
- AI-written summaries or advice.

## Testing

| Level | Covers |
|---|---|
| Unit, per section | Pulse, Activity, Focus, Categories, Sleep, Movement, Habits, Tasks, Goals, Rhythm, All time, Highlights: rules, empty input, today grace, period edges, DST (Havana), day start hour. |
| Unit | `CategoryClassifier` (EN, FR, accents, whole words), `GoalMatcher` (Cambridge case, ties, stop words), `HabitIconSuggester`, `CategoryResolver`. |
| Unit | Suggestion origin rules in the form models; FoundationModels answer validation. |
| Migration + backup | V8 → V9 keeps data; categories survive JSON and CSV round trips; format 5 files still import. |
| UI | Overview opens on Insights, switches to Grid; the period picker; a task titled "Contact professors at Cambridge" gets the Study category and the "Get into Cambridge" goal by itself. |

## Changes during build

- (filled in during the build)
