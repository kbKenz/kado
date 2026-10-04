import AVFoundation
import Speech

/// `SpeechTranscribing` on Apple's on-device speech recognizer, for the
/// current locale or its base language (`SpeechLocaleSelection`).
/// Audio never leaves the device: when on-device recognition is not
/// supported, the mic is not offered at all rather than falling back
/// to Apple's servers.
final class SpeechTranscriptionManager: SpeechTranscribing {
    private let recognizer: SFSpeechRecognizer?
    private var session: SpeechRecognitionSession?

    init(locale: Locale = .current) {
        let picked = SpeechLocaleSelection.locale(for: locale) {
            SFSpeechRecognizer(locale: $0)?.supportsOnDeviceRecognition ?? false
        }
        recognizer = picked.flatMap { SFSpeechRecognizer(locale: $0) }
    }

    var isAvailable: Bool {
        recognizer?.supportsOnDeviceRecognition ?? false
    }

    func requestAuthorization() async -> Bool {
        guard await AVAudioApplication.requestRecordPermission() else { return false }
        let status = await withCheckedContinuation { (continuation: CheckedContinuation<SFSpeechRecognizerAuthorizationStatus, Never>) in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
        return status == .authorized
    }

    func transcribe() -> AsyncThrowingStream<String, Error> {
        session?.stop()
        session = nil

        let (stream, continuation) = AsyncThrowingStream<String, Error>.makeStream()
        guard let recognizer, isAvailable else {
            continuation.finish(throwing: AssistedInputError.unavailable)
            return stream
        }
        let session = SpeechRecognitionSession(recognizer: recognizer, continuation: continuation)
        do {
            try session.start()
            self.session = session
        } catch {
            continuation.finish(throwing: error as? AssistedInputError ?? .failed)
        }
        return stream
    }

    func stop() {
        session?.stop()
        session = nil
    }
}
