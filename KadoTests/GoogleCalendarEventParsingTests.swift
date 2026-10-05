import Foundation
import Testing
import KadoCore

/// `parseTimestamp` reuses its formatters instead of building one per
/// call; it must accept and reject exactly what a fresh formatter did.
@Suite("Google event timestamp parsing")
struct GoogleCalendarEventParsingTests {
    /// The implementation before the formatters were cached, verbatim.
    nonisolated private static func freshParse(_ raw: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let value = formatter.date(from: raw) { return value }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: raw)
    }

    nonisolated static let samples: [String] = [
        "2026-04-13T09:00:00Z",
        "2026-04-13T09:00:00.123Z",
        "2026-04-13T09:00:00.123456Z",
        "2026-04-13T09:00:00.1Z",
        "2026-04-13T09:00:00+05:30",
        "2026-04-13T09:00:00-07:00",
        "2026-04-13T09:00:00.250-07:00",
        "2026-04-13T09:00:00+0530",
        "2026-03-08T00:30:00-05:00",
        "2026-10-25T02:30:00+02:00",
        "2026-12-31T23:59:59Z",
        "2024-02-29T12:00:00Z",
        "2026-02-29T12:00:00Z",
        "2026-04-13",
        "2026-04-13T09:00Z",
        "2026-04-13T09:00:00",
        "2026-04-13 09:00:00Z",
        "not-a-date",
        "",
    ]

    @Test("Cached parsing agrees with a fresh formatter", arguments: samples)
    func matchesFreshFormatter(raw: String) {
        #expect(GoogleCalendarEvent.parseTimestamp(raw) == Self.freshParse(raw))
    }

    @Test("Parsing from many tasks at once agrees with a fresh formatter")
    func concurrentParsing() async {
        let samples = Self.samples
        let mismatches = await withTaskGroup(of: Int.self) { group in
            for _ in 0..<8 {
                group.addTask {
                    var mismatches = 0
                    for _ in 0..<50 {
                        for raw in samples where GoogleCalendarEvent.parseTimestamp(raw) != Self.freshParse(raw) {
                            mismatches += 1
                        }
                    }
                    return mismatches
                }
            }
            return await group.reduce(0, +)
        }
        #expect(mismatches == 0)
    }
}
