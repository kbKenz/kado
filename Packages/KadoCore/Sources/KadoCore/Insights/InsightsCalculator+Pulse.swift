import Foundation

extension InsightsCalculator {
    /// The three dials, for the period and the previous one.
    /// Rules: see `InsightsPulse` in InsightsReport.swift.
    static func pulse(_ scope: InsightsScope) -> InsightsPulse {
        .empty
    }
}
