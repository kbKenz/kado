import Foundation

/// The "Health on Calendar" opt-in. Device-local `UserDefaults.standard`,
/// deliberately not synced: Health authorization is per device too.
enum HealthCalendarDefaults {
    static let key = "kado.healthOnCalendar"
}
