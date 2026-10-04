# Research — AI-assisted text input

**Date**: 2026-10-04
**Status**: ready for plan
**Branch**: `feature/ai-assisted-input`

## Problem

Writing in Kadō is all typing. Two helpers, asked for explicitly:

1. **Voice input**: speak into a text field instead of typing it.
2. **Clean up**: one tap turns a rough, typed or dictated idea into
   tidy text.

They must work in every free-text field, now and in future forms,
without copying code into each form.

"Done" from the user's side: in any supported field, tap the mic,
talk, see the words appear; tap ✨, see the same words with fixed
grammar and no "um"; tap Undo if they do not like it.

## Constraints

- **Privacy-first, zero third-party dependencies** (`CLAUDE.md`). No
  cloud model, no API key, no backend. Everything runs on device.
- **Deployment floor is iOS 18.0** for every target.
- **Foundation Models** (Apple's on-device LLM) needs iOS 26 and a
  device with Apple Intelligence turned on. Elsewhere it is not
  available, and the feature must hide, not fail.
- **Speech** (`SFSpeechRecognizer`) works on iOS 18 with
  `requiresOnDeviceRecognition = true`. On-device support depends on
  the locale; if it is not supported, the mic hides.
- **Build needs the iOS 26 SDK.** FoundationModels is not in the
  iOS 18 SDK (Xcode 16). Verified 2026-10-04 against the Xcode 26.5
  SDK's `FoundationModels.swiftinterface`:
  `LanguageModelSession(model:tools:instructions:)`,
  `SystemLanguageModel.availability` with `.unavailable` reasons
  `deviceNotEligible`, `appleIntelligenceNotEnabled`, `modelNotReady`.
  The deployment target stays 18.0; only the SDK moves.

## Decisions

| Question | Decision |
|---|---|
| Where it runs | On device only: Speech + Foundation Models |
| What cleanup does | Tidy only: grammar, punctuation, remove filler and repeats. Keep the user's words, meaning and language. No restructuring, no new content |
| How cleanup applies | Replace in place, with an Undo chip for about 5 s |
| How dictation works | Tap to start, live partial text, tap to stop. Text is appended after existing text. No auto-cleanup |
| Shape of the code | One view modifier + two injected services |

## Design

### 1. Services (`Kado/Services/`)

Both are protocols, injected through `EnvironmentValues+Services.swift`
and mocked in tests and previews, the same as the other services.

```swift
protocol SpeechTranscribing {
    var isAvailable: Bool { get }
    /// Each element is the full partial transcript so far.
    func transcribe() -> AsyncThrowingStream<String, Error>
    func stop()
}

protocol TextCleaning {
    var isAvailable: Bool { get }
    func clean(_ text: String) async throws -> String
}
```

- `DefaultSpeechTranscriber`: `SFSpeechRecognizer` +
  `AVAudioEngine`, `requiresOnDeviceRecognition = true`, current
  locale. Asks for microphone and speech permission on first use.
- `FoundationModelsTextCleaner`: `@available(iOS 26, *)`. Uses a
  `LanguageModelSession` with fixed instructions:
  *"Fix grammar and punctuation. Remove filler words and repeated
  words. Keep the user's words, meaning and language. Do not add
  information. Return only the corrected text."* `isAvailable` reads
  `SystemLanguageModel.default.availability`.
- `UnavailableTextCleaner`: used on iOS 18–25. `isAvailable` is
  `false`.
- A factory selects the cleaner at runtime with `#available`.

### 2. Merge logic (pure, tested)

`AssistedTextEditing`, a free struct with no UI and no system calls:

- `appending(transcript:to:)`: joins existing text and the partial
  transcript with one space, and does not add a space when the
  existing text is empty or already ends in whitespace.
- `applyingLimit(_:)`: truncates to the field's optional character
  limit (for example the 500 for day notes).
- The undo snapshot: the text before cleanup, kept until the user
  edits the field or 5 s pass.

### 3. `AssistedInputModifier` (`Kado/UIComponents/`)

```swift
TextField("Habit name", text: $model.name)
    .assistedInput($model.name)                 // no limit

TextField("Add a note...", text: $noteText, axis: .vertical)
    .assistedInput($noteText, characterLimit: 500)
```

- Adds a small trailing control with a **mic** button and a **✨**
  button.
- The mic shows only if `SpeechTranscribing.isAvailable`. While
  recording, it shows a recording state and each partial transcript
  replaces the previous partial (not the original text).
- ✨ shows only if `TextCleaning.isAvailable` and the text is not
  empty. While cleanup runs, it shows progress and the field is
  read-only.
- After cleanup, an **Undo** chip shows. It restores the snapshot.
- Both buttons have VoiceOver labels and respect Dynamic Type.
- Recording stops when the field disappears.

### 4. Where it is adopted on this branch

Every free-text field on `main` (updated 2026-10-04, after Tasks and
Goals merged in `72fab6c`):

- `NewHabitFormView` → habit name
- `DayEditPopover` → completion note (limit 500)
- `TaskFormView` → title, notes
- `GoalFormView` → name, "Why this matters"
- `GoalProgressEntryForm` → note

Numeric fields (amount, baseline, target) and the unit field are left
alone. Disabled fields (imported tasks, archived goals) hide the
controls.

### 5. Error handling

| Case | Result |
|---|---|
| Permission denied (mic or speech) | Inline message with a link to Settings. Text unchanged |
| Transcription fails mid-recording | Stop recording, keep text received so far, short message |
| Cleanup fails or model unavailable at call time | Text unchanged, short message |
| Cleanup returns empty text | Treated as failure. Text unchanged |

The user's text is never lost.

### 6. Info.plist and strings

- `Kado/Info.plist`: `NSMicrophoneUsageDescription`,
  `NSSpeechRecognitionUsageDescription`.
- `Kado/Resources/Localizable.xcstrings`: all new strings in EN and
  FR.

### 7. Tests

- `AssistedTextEditing`: append spacing, character limit, undo
  snapshot rules.
- Modifier-driving view model with `MockSpeechTranscriber` and
  `MockTextCleaner`: availability hides buttons, failure keeps text,
  cleanup sets the undo snapshot.
- `FoundationModelsTextCleaner`: output trimming (whitespace, quotes
  the model may add). No real model calls in CI.

## Out of scope

- Cloud models or any fallback for devices without Apple
  Intelligence.
- Auto-cleanup after dictation.
- Title suggestions, restructuring, summarising.
- `SpeechAnalyzer` (iOS 26). It can replace `SFSpeechRecognizer`
  behind the same protocol later.
