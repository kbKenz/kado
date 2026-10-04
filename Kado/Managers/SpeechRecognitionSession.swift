import AVFoundation
import os
import Speech

/// One dictation: microphone in, partial transcripts out. Audio is
/// recognized on device only and is never stored.
///
/// `nonisolated` on purpose: the audio tap and the recognizer call
/// back on their own threads. Closures created in a MainActor type
/// would be MainActor-isolated and trap when those threads run them.
/// Results go straight into the stream's continuation, which is
/// thread-safe.
nonisolated final class SpeechRecognitionSession: @unchecked Sendable {
    private let recognizer: SFSpeechRecognizer
    private let continuation: AsyncThrowingStream<String, Error>.Continuation
    private let engine = AVAudioEngine()
    private let request = SFSpeechAudioBufferRecognitionRequest()
    private var task: SFSpeechRecognitionTask?
    /// Set by `stop()` from the main thread, read by recognizer
    /// callbacks on theirs.
    private let stopRequested = OSAllocatedUnfairLock(initialState: false)
    /// `stop()` and the recognizer's final callback can both tear down,
    /// from different threads; only the first one does.
    private let isTornDown = OSAllocatedUnfairLock(initialState: false)

    init(recognizer: SFSpeechRecognizer, continuation: AsyncThrowingStream<String, Error>.Continuation) {
        self.recognizer = recognizer
        self.continuation = continuation
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = true
    }

    func start() throws {
        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
        try audioSession.setActive(true, options: .notifyOthersOnDeactivation)

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        // No usable input (no microphone, or a simulator without one).
        guard format.sampleRate > 0, format.channelCount > 0 else {
            deactivateAudioSession()
            throw AssistedInputError.unavailable
        }

        let request = request
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            request.append(buffer)
        }

        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            self?.handle(result: result, error: error)
        }

        engine.prepare()
        do {
            try engine.start()
        } catch {
            tearDown()
            throw AssistedInputError.failed
        }
    }

    /// Ends listening and finishes the stream at once, without waiting
    /// for a final callback that a cancelled task may never send.
    /// Words still in flight are dropped; `AssistedInputModel` already
    /// ignores partials after a stop.
    func stop() {
        stopRequested.withLock { $0 = true }
        tearDown()
        continuation.finish()
    }

    private func handle(result: SFSpeechRecognitionResult?, error: (any Error)?) {
        if let result {
            continuation.yield(result.bestTranscription.formattedString)
        }
        let isFinal = result?.isFinal ?? false
        guard isFinal || error != nil else { return }

        let stopped = stopRequested.withLock { $0 }
        if let failure = SpeechTranscriptionEnding.failure(for: error, stopRequested: stopped) {
            continuation.finish(throwing: failure)
        } else {
            continuation.finish()
        }
        tearDown()
    }

    private func tearDown() {
        let alreadyDone = isTornDown.withLock { done in
            defer { done = true }
            return done
        }
        guard !alreadyDone else { return }
        if engine.isRunning {
            engine.stop()
        }
        engine.inputNode.removeTap(onBus: 0)
        request.endAudio()
        task?.cancel()
        task = nil
        deactivateAudioSession()
    }

    private func deactivateAudioSession() {
        // Lets music or a podcast the dictation ducked come back.
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
