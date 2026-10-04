import OSLog

extension Logger {
    /// Health on Calendar: authorization and query failures, error type only.
    static let healthCalendar = Logger(subsystem: "dev.scastiel.kado", category: "health-calendar")
}
