import Foundation

extension InsightsCalculator {
    /// One row per category with activity in the period.
    /// Rules: see `[InsightsCategoryRow]` in InsightsReport.swift.
    static func categories(_ scope: InsightsScope) -> [InsightsCategoryRow] {
        []
    }
}
