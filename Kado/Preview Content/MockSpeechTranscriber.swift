import Foundation

/// Test-/preview-only `SpeechTranscribing` driven by hand: `send(_:)`
/// emits a partial transcript, `fail(_:)` ends the stream with an
/// error. Never touches the microphone.
///
/// `@unchecked Sendable` without a lock: tests and previews drive it
/// sequentially on the main actor.
final class MockSpeechTranscriber: SpeechTranscribing, @unchecked Sendable {
    var isAvailable: Bool
    var grantsAuthorization: Bool
    private(set) var stopCalls = 0
    private var continuation: AsyncThrowingStream<String, Error>.Continuation?

    init(isAvailable: Bool = true, grantsAuthorization: Bool = true) {
        self.isAvailable = isAvailable
        self.grantsAuthorization = grantsAuthorization
    }

    var isListening: Bool { continuation != nil }

    func requestAuthorization() async -> Bool { grantsAuthorization }

    func transcribe() -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { self.continuation = $0 }
    }

    func stop() {
        stopCalls += 1
        continuation?.finish()
        continuation = nil
    }

    func send(_ partial: String) {
        continuation?.yield(partial)
    }

    func fail(_ error: AssistedInputError) {
        continuation?.finish(throwing: error)
        continuation = nil
    }
}
