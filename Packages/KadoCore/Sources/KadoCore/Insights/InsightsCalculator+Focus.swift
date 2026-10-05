import Foundation

extension InsightsCalculator {
    /// Tracked session time and the focus chart buckets.
    /// Rules: see `InsightsFocus` in InsightsReport.swift.
    static func focus(_ scope: InsightsScope) -> InsightsFocus {
        .empty
    }
}
