import SwiftData

extension ModelContext {
    /// Whether the context's container stores `type`. A container built
    /// for a few models (tests, previews) has no table for the rest,
    /// and fetching one it lacks fails.
    func stores<T: PersistentModel>(_ type: T.Type) -> Bool {
        let name = String(describing: type)
        return container.schema.entities.contains { $0.name == name }
    }
}
