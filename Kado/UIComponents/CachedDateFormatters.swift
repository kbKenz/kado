import Foundation

/// Reused `DateFormatter`s for views that format a date per cell or per
/// row. Building one costs about 0.1 ms; the habit detail screen built
/// one per calendar day and two per history row on every render.
///
/// Keyed on everything that changes the output — the calendar (zone,
/// identifier, week rules), the resolved locale, the process time
/// zone a formatter defaults to, and the style — so a cached formatter
/// prints exactly what a freshly built one would.
enum CachedDateFormatters {
    enum Style: Hashable {
        case dateStyle(DateFormatter.Style)
        case dateFormat(String)
    }

    private struct Key: Hashable {
        let calendar: Calendar
        let locale: Locale
        let timeZone: TimeZone
        let style: Style
    }

    private static var cache: [Key: DateFormatter] = [:]

    /// A formatter set up the way these views always built theirs:
    /// the given calendar, its locale (or the current one), and
    /// either a date style or a fixed format.
    static func formatter(_ style: Style, calendar: Calendar) -> DateFormatter {
        let locale = calendar.locale ?? .current
        let key = Key(calendar: calendar, locale: locale, timeZone: .current, style: style)
        if let cached = cache[key] { return cached }
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = locale
        switch style {
        case .dateStyle(let dateStyle): formatter.dateStyle = dateStyle
        case .dateFormat(let format): formatter.dateFormat = format
        }
        cache[key] = formatter
        return formatter
    }

    static func string(from date: Date, _ style: Style, calendar: Calendar) -> String {
        formatter(style, calendar: calendar).string(from: date)
    }
}
