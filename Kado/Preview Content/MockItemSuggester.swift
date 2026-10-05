import Foundation

/// Test-/preview-only `ItemSuggesting` with a scripted answer. When
/// `holdsUntilReleased` is set, `suggest(_:)` waits for `release()`
/// (and ignores cancellation, like a slow model) so a test can act while
/// a request runs. Never calls a model.
///
/// `@unchecked Sendable` without a lock: tests and previews drive it
/// sequentially on the main actor.
final class MockItemSuggester: ItemSuggesting, @unchecked Sendable {
    var isAvailable: Bool
    var result: Result<ModelItemSuggestion, ItemSuggestionError>
    var holdsUntilReleased = false
    private(set) var requests: [ItemSuggestionRequest] = []
    private(set) var prewarmCount = 0
    /// Requests running right now, and the most ever at once.
    private(set) var running = 0
    private(set) var mostRunning = 0
    private var pending: [CheckedContinuation<Void, Never>] = []

    init(isAvailable: Bool = true, result: Result<ModelItemSuggestion, ItemSuggestionError> = .success(ModelItemSuggestion())) {
        self.isAvailable = isAvailable
        self.result = result
    }

    func prewarm() {
        prewarmCount += 1
    }

    func suggest(_ request: ItemSuggestionRequest) async throws -> ModelItemSuggestion {
        requests.append(request)
        running += 1
        mostRunning = max(mostRunning, running)
        defer { running -= 1 }
        if holdsUntilReleased {
            await withCheckedContinuation { pending.append($0) }
        }
        return try result.get()
    }

    /// Lets every held request finish.
    func release() {
        let waiting = pending
        pending.removeAll()
        waiting.forEach { $0.resume() }
    }
}
