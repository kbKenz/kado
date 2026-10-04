import SwiftUI
import Testing
@testable import Kado

/// Behaviour of the control behind `.assistedInput(_:)`: dictation,
/// cleanup, undo, and the rule that the user's text is never lost.
@MainActor
@Suite("AssistedInputModel")
struct AssistedInputModelTests {

    // MARK: - Fixtures

    /// Backing store for the `Binding` a field would pass in.
    /// `@unchecked Sendable` without a lock: the suite drives it
    /// sequentially on the main actor.
    final class TextBox: @unchecked Sendable {
        var value: String
        init(_ value: String) { self.value = value }
        var binding: Binding<String> {
            Binding(get: { self.value }, set: { self.value = $0 })
        }
    }

    /// Sleep stand-in for the undo window: suspends until `fire()`.
    final class ManualSleeper {
        private(set) var requested: [Duration] = []
        private var pending: [CheckedContinuation<Void, Never>] = []

        func sleep(_ duration: Duration) async throws {
            requested.append(duration)
            await withCheckedContinuation { pending.append($0) }
        }

        func fire() {
            pending.forEach { $0.resume() }
            pending.removeAll()
        }
    }

    let transcriber = MockSpeechTranscriber()
    let cleaner = MockTextCleaner(result: .success("Read every day."))
    let sleeper = ManualSleeper()

    func makeModel(characterLimit: Int? = nil) -> AssistedInputModel {
        AssistedInputModel(
            transcriber: transcriber,
            cleaner: cleaner,
            characterLimit: characterLimit,
            sleep: sleeper.sleep
        )
    }

    /// Lets queued main-actor work run until `condition` holds.
    func settle(until condition: () -> Bool) async {
        for _ in 0..<100 where !condition() {
            await Task.yield()
        }
    }

    // MARK: - Availability

    @Test("Mic and cleanup follow their services' availability")
    func availability() {
        transcriber.isAvailable = false
        cleaner.isAvailable = false
        let model = makeModel()
        #expect(!model.canRecord)
        #expect(!model.canClean("Some text"))
    }

    @Test("Cleanup is not offered for empty or whitespace-only text")
    func cleanupNeedsText() {
        let model = makeModel()
        #expect(!model.canClean(""))
        #expect(!model.canClean("  \n"))
        #expect(model.canClean("um read"))
    }

    // MARK: - Recording

    @Test("Partials append after the original text, each replacing the last")
    func partialsReplacePreviousPartial() async {
        let box = TextBox("Read")
        let model = makeModel()
        let task = model.toggleRecording(text: box.binding)
        #expect(model.state == .recording(base: "Read"))

        await settle { transcriber.isListening }
        transcriber.send("every")
        await settle { box.value == "Read every" }
        #expect(box.value == "Read every")

        transcriber.send("every day")
        await settle { box.value == "Read every day" }
        #expect(box.value == "Read every day")

        model.toggleRecording(text: box.binding)
        await task?.value
        #expect(box.value == "Read every day")
        #expect(model.state == .idle)
        #expect(transcriber.stopCalls >= 1)
    }

    @Test("A recognition error keeps the text received so far")
    func recordingErrorKeepsText() async {
        let box = TextBox("")
        let model = makeModel()
        let task = model.toggleRecording(text: box.binding)
        await settle { transcriber.isListening }
        transcriber.send("read more")
        await settle { box.value == "read more" }
        transcriber.fail(.failed)
        await task?.value
        #expect(box.value == "read more")
        #expect(model.state == .failed(.failed))
    }

    @Test("Permission denied leaves the text unchanged")
    func permissionDenied() async {
        transcriber.grantsAuthorization = false
        let box = TextBox("Read")
        let model = makeModel()
        await model.toggleRecording(text: box.binding)?.value
        #expect(box.value == "Read")
        #expect(model.state == .failed(.permissionDenied))
        #expect(!transcriber.isListening)
    }

    @Test("Dictation respects the character limit")
    func recordingRespectsLimit() async {
        let box = TextBox("abc")
        let model = makeModel(characterLimit: 6)
        let task = model.toggleRecording(text: box.binding)
        await settle { transcriber.isListening }
        transcriber.send("defghij")
        await settle { box.value != "abc" }
        model.toggleRecording(text: box.binding)
        await task?.value
        #expect(box.value == "abc de")
    }

    @Test("Stopping on disappear ends recording")
    func stopIfRecording() async {
        let box = TextBox("")
        let model = makeModel()
        let task = model.toggleRecording(text: box.binding)
        await settle { transcriber.isListening }
        model.stopIfRecording()
        await task?.value
        #expect(model.state == .idle)
        #expect(!transcriber.isListening)
    }

    // MARK: - Cleaning

    @Test("Cleanup replaces the text and keeps the original for undo")
    func cleanupReplacesAndSnapshots() async {
        let box = TextBox("um read read every day")
        let model = makeModel()
        await model.clean(text: box.binding)?.value
        #expect(box.value == "Read every day.")
        #expect(model.undoSnapshot == "um read read every day")
        #expect(model.state == .idle)
        #expect(cleaner.receivedTexts == ["um read read every day"])
    }

    @Test("A cleanup error leaves the text unchanged")
    func cleanupErrorKeepsText() async {
        cleaner.result = .failure(.failed)
        let box = TextBox("um read")
        let model = makeModel()
        await model.clean(text: box.binding)?.value
        #expect(box.value == "um read")
        #expect(model.undoSnapshot == nil)
        #expect(model.state == .failed(.failed))
    }

    @Test("An empty cleanup result leaves the text unchanged")
    func emptyCleanupKeepsText() async {
        cleaner.result = .success("  \"\" ")
        let box = TextBox("um read")
        let model = makeModel()
        await model.clean(text: box.binding)?.value
        #expect(box.value == "um read")
        #expect(model.state == .failed(.failed))
    }

    @Test("A second tap while cleaning is ignored")
    func secondTapIgnored() async {
        cleaner.holdsUntilReleased = true
        let box = TextBox("um read")
        let model = makeModel()
        let first = model.clean(text: box.binding)
        #expect(model.state == .cleaning)
        #expect(model.clean(text: box.binding) == nil)
        await settle { !cleaner.receivedTexts.isEmpty }
        cleaner.release()
        await first?.value
        #expect(cleaner.receivedTexts.count == 1)
    }

    @Test("A result is dropped if the user edited the text meanwhile")
    func editDuringCleanupWins() async {
        cleaner.holdsUntilReleased = true
        let box = TextBox("um read")
        let model = makeModel()
        let task = model.clean(text: box.binding)
        await settle { !cleaner.receivedTexts.isEmpty }
        box.value = "um read books"
        cleaner.release()
        await task?.value
        #expect(box.value == "um read books")
        #expect(model.undoSnapshot == nil)
        #expect(model.state == .idle)
    }

    @Test("Cleanup respects the character limit")
    func cleanupRespectsLimit() async {
        let box = TextBox("um read")
        let model = makeModel(characterLimit: 4)
        await model.clean(text: box.binding)?.value
        #expect(box.value == "Read")
    }

    // MARK: - Undo

    @Test("Undo restores the original text")
    func undoRestores() async {
        let box = TextBox("um read")
        let model = makeModel()
        await model.clean(text: box.binding)?.value
        model.undo(text: box.binding)
        #expect(box.value == "um read")
        #expect(model.undoSnapshot == nil)
    }

    @Test("Editing the cleaned text drops undo; the cleanup's own write does not")
    func userEditDropsUndo() async {
        let box = TextBox("um read")
        let model = makeModel()
        await model.clean(text: box.binding)?.value
        model.textDidChange(to: box.value)
        #expect(model.undoSnapshot != nil)
        model.textDidChange(to: "Read every day!")
        #expect(model.undoSnapshot == nil)
    }

    @Test("Undo expires after the undo window")
    func undoExpires() async {
        let box = TextBox("um read")
        let model = makeModel()
        await model.clean(text: box.binding)?.value
        await settle { !sleeper.requested.isEmpty }
        #expect(sleeper.requested == [AssistedInputModel.undoWindow])
        sleeper.fire()
        await settle { model.undoSnapshot == nil }
        #expect(model.undoSnapshot == nil)
        #expect(box.value == "Read every day.")
    }

    // MARK: - Exclusivity

    @Test("Cannot clean while recording, nor record while cleaning")
    func exclusive() async {
        let box = TextBox("um read")
        let model = makeModel()
        let recording = model.toggleRecording(text: box.binding)
        #expect(!model.canClean(box.value))
        #expect(model.clean(text: box.binding) == nil)
        model.toggleRecording(text: box.binding)
        await recording?.value

        cleaner.holdsUntilReleased = true
        let cleaning = model.clean(text: box.binding)
        #expect(model.toggleRecording(text: box.binding) == nil)
        await settle { !cleaner.receivedTexts.isEmpty }
        cleaner.release()
        await cleaning?.value
    }

    @Test("A new action clears a previous failure")
    func failureClearsOnNextAction() async {
        cleaner.result = .failure(.failed)
        let box = TextBox("um read")
        let model = makeModel()
        await model.clean(text: box.binding)?.value
        #expect(model.state == .failed(.failed))
        cleaner.result = .success("Read.")
        await model.clean(text: box.binding)?.value
        #expect(model.state == .idle)
        #expect(box.value == "Read.")
    }
}
