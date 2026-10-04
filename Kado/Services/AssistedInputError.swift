import Foundation

/// Why a dictation or cleanup did not complete. In every case the
/// user's text is left as it was before the action.
nonisolated enum AssistedInputError: Error, Equatable, Sendable {
    /// The user refused microphone or speech recognition access.
    case permissionDenied
    /// The engine is not available on this device, OS or locale.
    case unavailable
    /// The engine started but could not produce a result.
    case failed
}
