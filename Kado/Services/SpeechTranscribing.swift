import Foundation

/// On-device dictation for `.assistedInput(_:)`. Audio never leaves the
/// device.
protocol SpeechTranscribing: AnyObject {
    /// `false` when the device or the current locale has no on-device
    /// recognizer. The mic button hides.
    var isAvailable: Bool { get }

    /// Asks for microphone and speech recognition access if needed.
    /// Returns `true` only when both are granted.
    func requestAuthorization() async -> Bool

    /// Starts listening. Each element is the full transcript so far,
    /// not a delta. The stream finishes after `stop()`, and throws an
    /// `AssistedInputError` if recognition fails.
    func transcribe() -> AsyncThrowingStream<String, Error>

    /// Stops listening and finishes the current stream.
    func stop()
}
