import Foundation

/// `TextCleaning` for devices without an on-device model (iOS 18–25,
/// or Apple Intelligence off), and the environment default so previews
/// and tests never call the model.
final class UnavailableTextCleaner: TextCleaning {
    var isAvailable: Bool { false }

    func clean(_ text: String) async throws -> String {
        throw AssistedInputError.unavailable
    }
}
