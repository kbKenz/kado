import Foundation

extension InsightsCalculator {
    /// Done and left-undone tasks.
    /// Rules: see `InsightsTasks` in InsightsReport.swift.
    static func tasks(_ scope: InsightsScope) -> InsightsTasks {
        .empty
    }
}
