import Foundation

/// `ItemSuggesting` for devices without an on-device model (iOS 18–25,
/// or Apple Intelligence off), for UI test runs, and the environment
/// default, so previews and unit tests never call the model.
final class UnavailableItemSuggester: ItemSuggesting {
    var isAvailable: Bool { false }

    func suggest(_ request: ItemSuggestionRequest) async throws -> ModelItemSuggestion {
        throw ItemSuggestionError.unavailable
    }
}
