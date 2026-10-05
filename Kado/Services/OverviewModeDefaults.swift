import Foundation

/// What the Overview tab shows: the Insights feed or the habits × days
/// grid. Stored by raw value, so the cases keep their names.
enum OverviewMode: String {
    case insights
    case grid
}

/// Where Overview remembers its Insights / Grid switch and the period
/// the Insights feed covers. Both live in the standard suite: no widget
/// reads them.
enum OverviewModeDefaults {
    nonisolated static let key = "kado.overviewMode"
    /// The Week / Month / Year choice, an `InsightsPeriod` raw value.
    nonisolated static let insightsPeriodKey = "kado.insightsPeriod"
}
