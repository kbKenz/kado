import Foundation

/// Test-/preview-only `TextCleaning` with a scripted result. When
/// `holdsUntilReleased` is set, `clean(_:)` waits for `release()` so a
/// test can act while a cleanup is still running. Never calls a model.
///
/// `@unchecked Sendable` without a lock: tests and previews drive it
/// sequentially on the main actor.
final class MockTextCleaner: TextCleaning, @unchecked Sendable {
    var isAvailable: Bool
    var result: Result<String, AssistedInputError>
    var holdsUntilReleased = false
    private(set) var receivedTexts: [String] = []
    private var pending: CheckedContinuation<Void, Never>?

    init(isAvailable: Bool = true, result: Result<String, AssistedInputError> = .success("Cleaned text.")) {
        self.isAvailable = isAvailable
        self.result = result
    }

    func clean(_ text: String) async throws -> String {
        receivedTexts.append(text)
        if holdsUntilReleased {
            await withCheckedContinuation { pending = $0 }
        }
        return try result.get()
    }

    func release() {
        pending?.resume()
        pending = nil
    }
}
