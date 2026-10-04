import SwiftUI

/// State behind `.assistedInput(_:)`: one per field. Owns dictation,
/// cleanup and the undo window; the field's text stays with the field
/// and is passed in as a `Binding` on each action.
///
/// The rule every path keeps: the user's text is never lost. A failed
/// dictation keeps what was heard so far, a failed cleanup changes
/// nothing, and a cleanup result never overwrites text the user edited
/// while it ran.
///
/// Actions return the `Task` they start (or `nil` when the action is
/// not allowed right now) so tests can await them; views ignore it.
@Observable
final class AssistedInputModel {
    enum State: Equatable {
        case idle
        /// Dictating. `base` is the text before recording started;
        /// each partial transcript is appended to it afresh.
        case recording(base: String)
        case cleaning
        /// The last action failed. Cleared by the next action or
        /// `dismissFailure()`.
        case failed(AssistedInputError)
    }

    typealias Sleep = (Duration) async throws -> Void

    /// How long Undo stays offered after a cleanup.
    static let undoWindow: Duration = .seconds(5)

    private(set) var state: State = .idle
    /// The text before the last cleanup, while Undo is offered.
    private(set) var undoSnapshot: String?

    private let transcriber: any SpeechTranscribing
    private let cleaner: any TextCleaning
    private let characterLimit: Int?
    private let sleep: Sleep
    /// The text the last cleanup wrote, to tell that write apart from
    /// a user edit in `textDidChange(to:)`.
    private var lastCleanedText: String?
    private var undoExpiry: Task<Void, Never>?

    init(
        transcriber: any SpeechTranscribing,
        cleaner: any TextCleaning,
        characterLimit: Int? = nil,
        sleep: @escaping Sleep = AssistedInputModel.defaultSleep
    ) {
        self.transcriber = transcriber
        self.cleaner = cleaner
        self.characterLimit = characterLimit
        self.sleep = sleep
    }

    nonisolated static func defaultSleep(_ duration: Duration) async throws {
        try await Task.sleep(for: duration)
    }

    // MARK: - What the view may offer

    var canRecord: Bool {
        transcriber.isAvailable && (isReady || isRecording)
    }

    func canClean(_ text: String) -> Bool {
        cleaner.isAvailable
            && isReady
            && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var isRecording: Bool {
        if case .recording = state { return true }
        return false
    }

    /// No action is running; a past failure does not block a new one.
    private var isReady: Bool {
        switch state {
        case .idle, .failed: return true
        case .recording, .cleaning: return false
        }
    }

    // MARK: - Dictation

    /// Starts dictation, or stops it if it is running.
    @discardableResult
    func toggleRecording(text: Binding<String>) -> Task<Void, Never>? {
        if isRecording {
            stopIfRecording()
            return nil
        }
        guard transcriber.isAvailable, isReady else { return nil }

        // Set before the Task so a second tap in the same runloop tick
        // sees `.recording` and stops instead of starting twice.
        let base = text.wrappedValue
        state = .recording(base: base)
        clearUndo()

        return Task {
            guard await transcriber.requestAuthorization() else {
                if isRecording { state = .failed(.permissionDenied) }
                return
            }
            // Stopped while the permission prompt was up.
            guard isRecording else { return }

            do {
                for try await partial in transcriber.transcribe() {
                    guard isRecording else { break }
                    text.wrappedValue = AssistedTextEditing.limited(
                        AssistedTextEditing.appending(partial, to: base),
                        to: characterLimit
                    )
                }
                if isRecording { state = .idle }
            } catch {
                state = .failed(error as? AssistedInputError ?? .failed)
            }
        }
    }

    /// Ends dictation, keeping what was heard. Safe to call anytime;
    /// the view calls it when the field disappears.
    func stopIfRecording() {
        guard isRecording else { return }
        state = .idle
        transcriber.stop()
    }

    // MARK: - Cleanup

    @discardableResult
    func clean(text: Binding<String>) -> Task<Void, Never>? {
        let original = text.wrappedValue
        guard canClean(original) else { return nil }

        // Set before the Task: blocks a double tap from cleaning twice.
        state = .cleaning
        clearUndo()

        return Task {
            do {
                let output = try await cleaner.clean(original)
                guard let cleaned = AssistedTextEditing.sanitizedCleanup(output) else {
                    throw AssistedInputError.failed
                }
                // The user kept typing while the model ran: their text wins.
                guard text.wrappedValue == original else {
                    state = .idle
                    return
                }
                let result = AssistedTextEditing.limited(cleaned, to: characterLimit)
                text.wrappedValue = result
                lastCleanedText = result
                undoSnapshot = original
                state = .idle
                scheduleUndoExpiry()
            } catch {
                state = .failed(error as? AssistedInputError ?? .failed)
            }
        }
    }

    // MARK: - Undo

    func undo(text: Binding<String>) {
        guard let snapshot = undoSnapshot else { return }
        clearUndo()
        text.wrappedValue = snapshot
    }

    /// Call on every change of the field's text. A change that is not
    /// the cleanup's own write means the user moved on: Undo goes away.
    func textDidChange(to newValue: String) {
        guard undoSnapshot != nil, newValue != lastCleanedText else { return }
        clearUndo()
    }

    func dismissFailure() {
        if case .failed = state { state = .idle }
    }

    private func scheduleUndoExpiry() {
        undoExpiry?.cancel()
        undoExpiry = Task {
            try? await sleep(Self.undoWindow)
            guard !Task.isCancelled else { return }
            undoSnapshot = nil
            lastCleanedText = nil
        }
    }

    private func clearUndo() {
        undoExpiry?.cancel()
        undoExpiry = nil
        undoSnapshot = nil
        lastCleanedText = nil
    }
}
