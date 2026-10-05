import Foundation

extension InsightsCalculator {
    /// Up to four facts, picked from the finished sections.
    /// Rules: see `InsightsHighlight` in InsightsReport.swift.
    static func highlights(_ report: InsightsReport, _ scope: InsightsScope) -> [InsightsHighlight] {
        []
    }
}
