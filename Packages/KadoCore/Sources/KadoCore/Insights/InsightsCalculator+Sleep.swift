import Foundation

extension InsightsCalculator {
    /// Apple Health nights and Sleep-category habits.
    /// Rules: see `InsightsSleep` in InsightsReport.swift.
    static func sleep(_ scope: InsightsScope) -> InsightsSleep {
        .empty
    }
}
