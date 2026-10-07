import Foundation

/// Where the Reflect section keeps its settings. Standard suite: no
/// widget reads them.
enum ReflectionDefaults {
    /// The monthly check-in reminder. On unless the user turns it off.
    nonisolated static let remindersKey = "kado.reflection.reminders"
    /// Asks for Face ID (or the passcode) before showing reflections.
    nonisolated static let lockKey = "kado.reflection.lock"
    /// Months / Questions / Trends, a `ReflectArchiveMode` raw value.
    nonisolated static let archiveModeKey = "kado.reflection.archiveMode"
    /// The month (`yyyy-MM`) whose Today card the user put away.
    nonisolated static let dismissedCardKey = "kado.reflection.dismissedCard"

    static var remindersEnabled: Bool {
        UserDefaults.standard.object(forKey: remindersKey) as? Bool ?? true
    }
}

/// What the Reflect archive shows under the check-in card.
enum ReflectArchiveMode: String, CaseIterable {
    case months, questions, trends
}
