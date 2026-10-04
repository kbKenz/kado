import Foundation

/// `SpeechTranscribing` for contexts with no microphone access: the
/// environment default, so previews and tests never record audio.
/// `KadoApp` injects the real transcriber at scene build.
final class UnavailableSpeechTranscriber: SpeechTranscribing {
    var isAvailable: Bool { false }

    func requestAuthorization() async -> Bool { false }

    func transcribe() -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { $0.finish(throwing: AssistedInputError.unavailable) }
    }

    func stop() {}
}
