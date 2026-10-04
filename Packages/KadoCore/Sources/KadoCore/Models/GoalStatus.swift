import Foundation

/// A goal's lifecycle, separate from linked habit or task completion.
/// The raw value is the stable persistence and backup representation.
nonisolated public enum GoalStatus: String, Codable, Hashable, Sendable, CaseIterable {
    case active
    case paused
    case completed
}
