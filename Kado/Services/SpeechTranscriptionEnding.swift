import Foundation

/// Decides how a dictation ended. Stopping cuts the recognizer off
/// mid-audio, and it often answers with an error ("no speech
/// detected", "cancelled"); after a stop that is the normal end.
nonisolated enum SpeechTranscriptionEnding {
    /// The failure to report, or `nil` for a normal end.
    static func failure(for error: (any Error)?, stopRequested: Bool) -> AssistedInputError? {
        guard let error, !stopRequested else { return nil }
        return error as? AssistedInputError ?? .failed
    }
}
