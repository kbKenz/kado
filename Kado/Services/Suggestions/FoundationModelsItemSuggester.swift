import Foundation
import FoundationModels
import KadoCore
import OSLog

/// `ItemSuggesting` on Apple's on-device language model. Needs iOS 26
/// and Apple Intelligence turned on; `ItemSuggesterFactory` falls back
/// to `UnavailableItemSuggester` everywhere else.
///
/// The request carries the title and the active goals' names and
/// details, nothing else, and nothing leaves the device. Guided output
/// limits every answer to a closed list, and
/// `ItemSuggestionSchema.validate` checks it again.
@available(iOS 26, *)
final class FoundationModelsItemSuggester: ItemSuggesting {
    private let model: SystemLanguageModel
    private let logger = Logger(subsystem: "dev.scastiel.kado", category: "suggestions")

    init(model: SystemLanguageModel = .default) {
        self.model = model
    }

    /// Read on every check: the model can become ready (or be turned
    /// off) while the app runs.
    var isAvailable: Bool {
        guard case .available = model.availability else { return false }
        return model.supportsLocale()
    }

    func prewarm() {
        guard isAvailable else { return }
        LanguageModelSession(model: model, instructions: ItemSuggestionSchema.instructions).prewarm()
    }

    func suggest(_ request: ItemSuggestionRequest) async throws -> ModelItemSuggestion {
        guard isAvailable else { throw ItemSuggestionError.unavailable }
        // A fresh session per request: no history carries from one
        // title to the next.
        let session = LanguageModelSession(model: model, instructions: ItemSuggestionSchema.instructions)
        do {
            let response = try await session.respond(
                to: ItemSuggestionSchema.prompt(for: request),
                schema: try Self.schema(for: request),
                options: GenerationOptions(sampling: .greedy)
            )
            let content = response.content
            return ItemSuggestionSchema.validate(
                category: try? content.value(String.self, forProperty: "category"),
                goal: request.kind == .goal ? nil : try? content.value(String.self, forProperty: "goal"),
                icon: request.kind == .habit ? try? content.value(String.self, forProperty: "icon") : nil,
                for: request
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            // The error's type only: never the title or a goal name.
            logger.error("Suggestion request failed: \(String(describing: type(of: error)), privacy: .public)")
            throw ItemSuggestionError.failed
        }
    }

    /// An object with "category", and "goal" (tasks and habits) and
    /// "icon" (habits), each one of a closed list of strings.
    static func schema(for request: ItemSuggestionRequest) throws -> GenerationSchema {
        var properties = [
            DynamicGenerationSchema.Property(
                name: "category",
                schema: DynamicGenerationSchema(name: "Category", anyOf: ItemSuggestionSchema.categoryChoices)
            )
        ]
        if request.kind != .goal {
            properties.append(DynamicGenerationSchema.Property(
                name: "goal",
                schema: DynamicGenerationSchema(name: "Goal", anyOf: ItemSuggestionSchema.goalChoices(for: request))
            ))
        }
        if request.kind == .habit {
            properties.append(DynamicGenerationSchema.Property(
                name: "icon",
                schema: DynamicGenerationSchema(name: "Icon", anyOf: ItemSuggestionSchema.iconChoices)
            ))
        }
        let root = DynamicGenerationSchema(name: "ItemSuggestion", properties: properties)
        return try GenerationSchema(root: root, dependencies: [])
    }
}
