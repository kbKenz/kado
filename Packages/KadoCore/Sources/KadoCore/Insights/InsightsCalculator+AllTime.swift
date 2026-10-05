import Foundation

extension InsightsCalculator {
    /// Totals since the first record.
    /// Rules: see `InsightsAllTime` in InsightsReport.swift.
    static func allTime(_ scope: InsightsScope) -> InsightsAllTime {
        .empty
    }
}
