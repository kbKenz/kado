import Foundation

extension InsightsCalculator {
    /// Consistency by weekday and focus by part of the day.
    /// Rules: see `InsightsRhythm` in InsightsReport.swift.
    static func rhythm(_ scope: InsightsScope) -> InsightsRhythm {
        .empty
    }
}
