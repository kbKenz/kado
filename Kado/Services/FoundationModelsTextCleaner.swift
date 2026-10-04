import Foundation
import FoundationModels

/// `TextCleaning` on Apple's on-device language model. Needs iOS 26
/// and Apple Intelligence turned on; `TextCleanerFactory` falls back to
/// `UnavailableTextCleaner` everywhere else. Nothing leaves the device.
@available(iOS 26, *)
final class FoundationModelsTextCleaner: TextCleaning {
    private let model: SystemLanguageModel

    init(model: SystemLanguageModel = .default) {
        self.model = model
    }

    /// Read on every check: the model can become ready (or be turned
    /// off) while the app runs.
    var isAvailable: Bool {
        guard case .available = model.availability else { return false }
        return model.supportsLocale()
    }

    func clean(_ text: String) async throws -> String {
        guard isAvailable else { throw AssistedInputError.unavailable }
        // A fresh session per call: no history carries from one field
        // or note into the next.
        let session = LanguageModelSession(
            model: model,
            instructions: CleanupInstructions.make(for: text)
        )
        do {
            let response = try await session.respond(
                to: text,
                options: GenerationOptions(sampling: .greedy)
            )
            guard let cleaned = AssistedTextEditing.sanitizedCleanup(response.content) else {
                throw AssistedInputError.failed
            }
            return cleaned
        } catch let error as AssistedInputError {
            throw error
        } catch let error as LanguageModelSession.GenerationError {
            if case .unsupportedLanguageOrLocale = error { throw AssistedInputError.unavailable }
            // Guardrail, context window and other generation failures.
            throw AssistedInputError.failed
        } catch {
            throw AssistedInputError.failed
        }
    }
}
