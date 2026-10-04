# Plan — AI-assisted text input

**Date**: 2026-10-04
**Status**: ready to build
**Research**: [research.md](./research.md)

## Summary

Add two on-device helpers to free-text fields: a mic that dictates
into the field, and a ✨ button that tidies the text (grammar,
punctuation, filler) with Apple's Foundation Models, replacing it in
place with Undo. Both come from one `.assistedInput(_:)` modifier
backed by two injected services, so any field adopts the feature with
one line. Nothing leaves the device. Each control hides itself where
its engine is not available.

## Decisions locked in

- On device only: `SFSpeechRecognizer` with
  `requiresOnDeviceRecognition`, and `FoundationModels`. No network.
- Cleanup is tidy only. It must not add content or translate.
- Cleanup replaces the text and offers Undo for about 5 s. Undo is
  dropped when the user edits the field.
- Dictation: tap to start, live partials appended after the existing
  text, tap to stop. No auto-cleanup.
- Cleaner availability = iOS 26 **and**
  `SystemLanguageModel.default.availability == .available` **and**
  `supportsLocale(.current)`. Otherwise ✨ hides.
- Mic availability = recognizer for `.current` locale exists **and**
  `supportsOnDeviceRecognition`. Otherwise the mic hides.
- Environment defaults are mocks / unavailable stand-ins (pattern:
  `notificationScheduler`). `KadoApp` injects the real services at
  scene build, so previews and tests never touch the mic or the
  model.
- Builds need Xcode 26.x (iOS 26 SDK). Deployment target stays 18.0.
- On this branch, adopted only in `NewHabitFormView` (habit name) and
  `DayEditPopover` (note, limit 500). Tasks and Goals adopt it after
  they merge.

## Task list

### Task 1: `AssistedTextEditing` pure logic (tests first) ✅

**Goal**: every text rule in one tested, UI-free type.

**Changes**:
- `Kado/Services/AssistedTextEditing.swift` — `nonisolated enum`
  (namespace, static functions; it holds no state) with:
  - `appending(_ transcript: String, to base: String) -> String` —
    one space between non-empty base and transcript, none if base is
    empty or ends in whitespace; empty transcript returns base.
  - `limited(_ text: String, to limit: Int?) -> String` — prefix to
    the limit, `nil` means no limit.
  - `sanitizedCleanup(_ output: String) -> String?` — trims
    whitespace and newlines, strips one pair of wrapping quotes
    (`"…"`, `“…”`, `«…»`), returns `nil` if the result is empty.
- `KadoTests/AssistedTextEditingTests.swift`.

**Tests / verification**:
- Append: empty base; base ending in space; base ending in newline;
  normal base; empty transcript.
- Limit: under, at, over the limit; `nil` limit; emoji and accented
  characters count as one `Character`.
- Sanitize: wrapping quotes stripped, inner quotes kept, whitespace
  only → `nil`, normal text unchanged.
- `make test` green.

**Commit message (suggested)**: `feat(ai-input): add pure text-editing rules for assisted input`

---

### Task 2: Service protocols, stand-ins, environment entries

**Goal**: the two seams exist and are injectable; nothing real yet.

**Changes**:
- `Kado/Services/SpeechTranscribing.swift` — protocol
  (`isAvailable`, `requestAuthorization() async -> Bool`,
  `transcribe() -> AsyncThrowingStream<String, Error>`, `stop()`),
  plus `AssistedInputError` enum (`permissionDenied`,
  `unavailable`, `failed`).
- `Kado/Services/TextCleaning.swift` — protocol (`isAvailable`,
  `clean(_:) async throws -> String`) and `UnavailableTextCleaner`.
- `Kado/Preview Content/MockSpeechTranscriber.swift`,
  `MockTextCleaner.swift` — scripted partials / scripted result or
  error. `@unchecked Sendable` with the one-line comment, per
  `CLAUDE.md`.
- `Kado/App/EnvironmentValues+Services.swift` — `@Entry var
  speechTranscriber` (default: unavailable mock) and `@Entry var
  textCleaner` (default: `UnavailableTextCleaner()`).
- `KadoTests/EnvironmentValuesServicesTests.swift` — defaults are
  the unavailable stand-ins.

**Tests / verification**:
- Default environment reports both services unavailable.
- `make test` and `make build` green.

**Commit message (suggested)**: `feat(ai-input): add speech and cleanup service seams`

---

### Task 3: `AssistedInputModel` state machine (tests first)

**Goal**: all behaviour of the control, testable without a view.

**Changes**:
- `Kado/ViewModels/AssistedInputModel.swift` — `@Observable` class
  owning:
  - `state: State` enum — `.idle`, `.recording(base: String)`,
    `.cleaning`, `.failed(AssistedInputError)`.
  - `undoSnapshot: String?`.
  - `toggleRecording(text: Binding)`, `clean(text: Binding)`,
    `undo(text: Binding)`, `textDidChangeByUser()`.
  - Guard flags set synchronously before spawning a `Task` (the
    `TipJarView` double-tap rule in `CLAUDE.md`).
  - Undo expiry through an injected `Clock` so tests do not sleep.
- `KadoTests/AssistedInputModelTests.swift`.

**Tests / verification**:
- Recording: partials replace the previous partial, not the base;
  stop keeps the last partial; stream error keeps received text and
  sets `.failed`; permission denied sets `.failed(.permissionDenied)`
  and text unchanged.
- Cleaning: success replaces text and sets the snapshot; error or
  `nil` sanitize result leaves text unchanged; second tap while
  cleaning is ignored; character limit applied to the result.
- Undo restores the snapshot; user edit clears it; clock advance of
  5 s clears it.
- Cannot clean while recording and the reverse.
- `make test` green.

**Commit message (suggested)**: `feat(ai-input): add assisted input state model`

---

### Task 4: `FoundationModelsTextCleaner`

**Goal**: real cleanup on iOS 26 devices with Apple Intelligence.

**Changes**:
- `Kado/Services/FoundationModelsTextCleaner.swift` —
  `@available(iOS 26, *)`; new `LanguageModelSession(instructions:)`
  per call (no history leaks between fields); maps
  `GenerationError` (`guardrailViolation`,
  `exceededContextWindowSize`, `unsupportedLanguageOrLocale`) to
  `AssistedInputError.failed`; output goes through
  `AssistedTextEditing.sanitizedCleanup`.
- `Kado/Services/TextCleanerFactory.swift` — `#available(iOS 26, *)`
  → Foundation Models, else `UnavailableTextCleaner`.
- `Kado/App/KadoApp.swift` — inject `\.textCleaner` at scene build.

**Tests / verification**:
- Build with Xcode 26.x, no new warnings.
- Manual: on an Apple Intelligence Mac's simulator (or device), clean
  "um so i want to like read more books books every day" → tidy text,
  same meaning. French sample too.
- Manual: with Apple Intelligence off, ✨ is hidden.

**Commit message (suggested)**: `feat(ai-input): clean up text with on-device Foundation Models`

---

### Task 5: `DefaultSpeechTranscriber` and permission strings

**Goal**: real on-device dictation, with honest permission prompts.

**Changes**:
- `Kado/Managers/SpeechTranscriptionManager.swift` (stateful system
  wrapper, so it is a Manager per `CLAUDE.md`) —
  `SFSpeechRecognizer(locale: .current)`, `AVAudioEngine`,
  `SFSpeechAudioBufferRecognitionRequest` with
  `requiresOnDeviceRecognition = true` and
  `shouldReportPartialResults = true`; audio session `.record`, mode
  `.measurement`, deactivated with `.notifyOthersOnDeactivation` on
  stop.
- `Kado/Info.plist` — `NSMicrophoneUsageDescription`,
  `NSSpeechRecognitionUsageDescription`.
- `Kado/Resources/InfoPlist.xcstrings` (new) — EN + FR for both
  keys. FR drafted with `tu`, flagged for native review.
- `Kado/App/KadoApp.swift` — inject `\.speechTranscriber`.

**Tests / verification**:
- Build green.
- Manual on simulator / device: first tap shows both prompts with
  the right text (EN and FR); deny → inline message, field unchanged;
  allow → words stream in; stopping restores other audio.

**Commit message (suggested)**: `feat(ai-input): add on-device speech transcription`

---

### Task 6: `AssistedInputModifier` view

**Goal**: the one-line UI that every field uses.

**Changes**:
- `Kado/UIComponents/AssistedInputModifier.swift` —
  `View.assistedInput(_ text: Binding<String>, characterLimit: Int? = nil)`;
  trailing `HStack` with mic (`mic` / `stop.circle.fill`) and ✨
  (`sparkles`, `ProgressView` while cleaning, `.tint` set per the
  `CLAUDE.md` spinner rule); Undo chip; inline failure text with
  "Open Settings" for `permissionDenied`; stops recording
  `.onDisappear`.
- Accessibility labels and identifiers on each button (leaves only).
- `Kado/Resources/Localizable.xcstrings` — new keys with comments,
  EN + FR.
- Previews: idle, recording, cleaning, undo visible, failure; one
  `#Preview("Dark")`.

**Tests / verification**:
- `LocalizationCoverageTests` green.
- Previews render; screenshot light + dark.
- Dynamic Type XXXL: buttons do not clip the text.

**Commit message (suggested)**: `feat(ai-input): add assistedInput modifier`

---

### Task 7: Adopt in habit name and day note

**Goal**: the feature is live in the two fields `main` has.

**Changes**:
- `Kado/Views/NewHabit/NewHabitFormView.swift` —
  `.assistedInput($model.name)`.
- `Kado/UIComponents/DayEditPopover.swift` —
  `.assistedInput($noteText, characterLimit: noteCharLimit)`.

**Tests / verification**:
- `make test`, `make build` green; `make e2e` green (existing name
  and note UI tests still pass).
- Screenshots of both fields, light + dark, iPhone + iPad.
- VoiceOver walk-through of both fields.

**Commit message (suggested)**: `feat(ai-input): offer voice input and cleanup in habit name and day note`

---

### Task 8: Docs

**Goal**: privacy and roadmap say what the app now does.

**Changes**:
- `PRIVACY.md` — microphone and speech recognition: optional,
  on-device only, audio not stored or sent; cleanup runs on device.
- `docs/ROADMAP.md` — entry for the feature.

**Commit message (suggested)**: `docs: describe on-device voice input and text cleanup`

## Risks and mitigation

| Risk | Mitigation |
|---|---|
| Wrong Xcode (16.0 in `/Applications`) | All builds via Xcode 26.5; set `DEVELOPER_DIR` or `xcode-select` before Task 4 |
| Simulator cannot run Foundation Models | Verify on a device or on a simulator hosted by a Mac with Apple Intelligence on; logic is covered by mocks in Task 3 |
| On-device speech missing for a locale (FR, etc.) | Mic hides; documented, not a failure |
| Model rewrites meaning or translates | Strict instructions + Undo; manual EN + FR samples in Task 4 |
| Audio session conflicts (music, timers) | `.notifyOthersOnDeactivation` on stop; manual check with music playing |
| Trailing buttons crowd the compact popover | Previews + XXXL check in Task 6; fall back to a row below the field in the popover if needed |

## Open questions

- [x] Should Settings have a switch to turn the AI helpers off?
      **Decided 2026-10-04: no switch.** Each control hides when
      unavailable.
- [ ] FR strings need review by a native speaker before merge
      (`CLAUDE.md` localisation rule).

## Out of scope

- Tasks and Goals forms (not on `main`).
- Cloud models or fallbacks.
- Auto-cleanup, title suggestions, restructuring.
- `SpeechAnalyzer` (iOS 26) — can replace the manager behind the
  same protocol later.
