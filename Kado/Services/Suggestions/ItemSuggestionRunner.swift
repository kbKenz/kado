import Foundation

/// Runs one form's model requests: one at a time, each with a time
/// limit. A new request cancels the one before it and waits for it to
/// end. Any error, the time limit and cancellation all give `nil`, so
/// the form keeps its word suggestions without a message.
@MainActor
final class ItemSuggestionRunner {
    typealias Sleep = (Duration) async throws -> Void

    /// How long a request may take before the form stops waiting.
    nonisolated static let defaultTimeout: Duration = .milliseconds(2500)

    private let suggester: any ItemSuggesting
    private let timeout: Duration
    private let sleep: Sleep
    private var inFlight: Task<ModelItemSuggestion?, Never>?

    init(
        suggester: any ItemSuggesting,
        timeout: Duration = ItemSuggestionRunner.defaultTimeout,
        sleep: @escaping Sleep = { try await Task.sleep(for: $0) }
    ) {
        self.suggester = suggester
        self.timeout = timeout
        self.sleep = sleep
    }

    /// The model's answer for `request`, or `nil`.
    func suggestion(for request: ItemSuggestionRequest) async -> ModelItemSuggestion? {
        // One request at a time: stop the last one and wait for it to
        // end. If it is still running after the time limit, skip this
        // request rather than run two at once.
        if let previous = inFlight {
            previous.cancel()
            guard case .finished = await race(previous) else { return nil }
        }
        guard !Task.isCancelled else { return nil }
        let suggester = self.suggester
        let work = Task { try? await suggester.suggest(request) }
        inFlight = work
        let outcome = await withTaskCancellationHandler {
            await race(work)
        } onCancel: {
            work.cancel()
        }
        switch outcome {
        case .finished(let suggestion):
            return Task.isCancelled ? nil : suggestion
        case .timedOut:
            work.cancel()
            return nil
        }
    }

    /// Waits for `task`, or for the time limit, whichever comes first.
    private func race(_ task: Task<ModelItemSuggestion?, Never>) async -> Outcome {
        let sleep = self.sleep
        let timeout = self.timeout
        return await withCheckedContinuation { continuation in
            let gate = ResumeGate(continuation)
            let timer = Task {
                do { try await sleep(timeout) } catch { return }
                gate.resume(with: .timedOut)
            }
            Task {
                let suggestion = await task.value
                timer.cancel()
                gate.resume(with: .finished(suggestion))
            }
        }
    }

    nonisolated fileprivate enum Outcome: Sendable {
        case finished(ModelItemSuggestion?)
        case timedOut
    }
}

/// Resumes a continuation once, whichever of the answer and the time
/// limit comes first.
@MainActor
private final class ResumeGate {
    private var continuation: CheckedContinuation<ItemSuggestionRunner.Outcome, Never>?

    init(_ continuation: CheckedContinuation<ItemSuggestionRunner.Outcome, Never>) {
        self.continuation = continuation
    }

    func resume(with outcome: ItemSuggestionRunner.Outcome) {
        continuation?.resume(returning: outcome)
        continuation = nil
    }
}
