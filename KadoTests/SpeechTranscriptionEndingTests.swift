import Foundation
import Testing
@testable import Kado

/// When the user taps stop, the recognizer is cut off mid-audio and
/// often reports an error ("no speech detected", "cancelled"). That is
/// the normal end of a dictation, not a failure to show.
@Suite("SpeechTranscriptionEnding")
struct SpeechTranscriptionEndingTests {
    struct SomeError: Error {}

    @Test("Finishing without an error is a normal end")
    func noError() {
        #expect(SpeechTranscriptionEnding.failure(for: nil, stopRequested: false) == nil)
        #expect(SpeechTranscriptionEnding.failure(for: nil, stopRequested: true) == nil)
    }

    @Test("An error after the user stopped is a normal end")
    func errorAfterStop() {
        #expect(SpeechTranscriptionEnding.failure(for: SomeError(), stopRequested: true) == nil)
    }

    @Test("An error while still listening is a failure")
    func errorWhileListening() {
        #expect(SpeechTranscriptionEnding.failure(for: SomeError(), stopRequested: false) == .failed)
    }

    @Test("An AssistedInputError while listening is passed through")
    func assistedErrorPassesThrough() {
        #expect(SpeechTranscriptionEnding.failure(for: AssistedInputError.unavailable, stopRequested: false) == .unavailable)
    }
}
