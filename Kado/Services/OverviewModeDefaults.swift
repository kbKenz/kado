import Foundation

/// What the Overview tab shows: the Insights feed, the day-by-day
/// History, the habits × days grid, or the monthly reflections. Stored
/// by raw value, so the cases keep their names.
enum OverviewMode: String {
    case insights
    case history
    case grid
    case reflect
}

/// Where Overview remembers its Insights / History / Grid switch, the
/// period the Insights feed covers and how the History is sorted and
/// filtered. All live in the standard suite: no widget reads them.
enum OverviewModeDefaults {
    nonisolated static let key = "kado.overviewMode"
    /// The Week / Month / Year choice, an `InsightsPeriod` raw value.
    nonisolated static let insightsPeriodKey = "kado.insightsPeriod"
    /// All / Tasks / Habits, a `HistoryKind` raw value.
    nonisolated static let historyKindKey = "kado.historyKind"
    /// A `HistoryDayOrder` raw value.
    nonisolated static let historyDayOrderKey = "kado.historyDayOrder"
    /// A `HistoryItemOrder` raw value.
    nonisolated static let historyItemOrderKey = "kado.historyItemOrder"
}
