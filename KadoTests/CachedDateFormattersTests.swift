import Foundation
import Testing
@testable import Kado

/// A cached formatter must print exactly what a freshly built one
/// would, and must not leak one calendar's or locale's output into
/// another's.
@Suite("CachedDateFormatters") @MainActor
struct CachedDateFormattersTests {
    private func fresh(_ style: CachedDateFormatters.Style, calendar: Calendar) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = calendar.locale ?? .current
        switch style {
        case .dateStyle(let dateStyle): formatter.dateStyle = dateStyle
        case .dateFormat(let format): formatter.dateFormat = format
        }
        return formatter
    }

    private func calendar(_ identifier: Calendar.Identifier, zone: String, locale: String?) -> Calendar {
        var calendar = Calendar(identifier: identifier)
        calendar.timeZone = TimeZone(identifier: zone)!
        calendar.locale = locale.map(Locale.init(identifier:))
        return calendar
    }

    @Test("Prints what a fresh formatter prints, for every calendar, locale and style used")
    func matchesFreshFormatter() {
        let calendars = [
            calendar(.gregorian, zone: "UTC", locale: "en_US"),
            calendar(.gregorian, zone: "Europe/Paris", locale: "fr_FR"),
            calendar(.gregorian, zone: "America/Havana", locale: "de_DE"),
            calendar(.japanese, zone: "Asia/Tokyo", locale: "ja_JP"),
            calendar(.gregorian, zone: "Pacific/Chatham", locale: nil),
        ]
        let styles: [CachedDateFormatters.Style] = [
            .dateStyle(.full), .dateStyle(.medium), .dateFormat("EEE MMM d"), .dateFormat("MMMM yyyy"),
        ]
        let dates = (0..<40).map { Date(timeIntervalSince1970: 1_767_225_600 + Double($0) * 86_400 * 9.37) }
        // Interleaved, so a formatter reused across keys would show.
        for date in dates {
            for calendar in calendars {
                for style in styles {
                    let cached = CachedDateFormatters.string(from: date, style, calendar: calendar)
                    #expect(cached == fresh(style, calendar: calendar).string(from: date))
                }
            }
        }
    }

    @Test("Reuses one formatter per key")
    func reusesFormatter() {
        let utc = calendar(.gregorian, zone: "UTC", locale: "en_US")
        let first = CachedDateFormatters.formatter(.dateStyle(.medium), calendar: utc)
        let second = CachedDateFormatters.formatter(.dateStyle(.medium), calendar: utc)
        #expect(first === second)
        var paris = utc
        paris.timeZone = TimeZone(identifier: "Europe/Paris")!
        #expect(CachedDateFormatters.formatter(.dateStyle(.medium), calendar: paris) !== first)
    }
}
