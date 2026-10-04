import Foundation

/// Fits Health entries to the Calendar's civil day. The habit
/// "Day starts at" setting does not apply: the Calendar is civil.
nonisolated public enum HealthTimelineClipper {
    /// The day widened by 12 hours on each side, so a night that
    /// starts the evening before (or a session that ends the morning
    /// after) is fetched whole and merges correctly before clipping.
    public static func queryInterval(around day: Date, calendar: Calendar) -> DateInterval? {
        guard let dayInterval = calendar.dateInterval(of: .day, for: day),
              let start = calendar.date(byAdding: .hour, value: -12, to: dayInterval.start),
              let end = calendar.date(byAdding: .hour, value: 12, to: dayInterval.end)
        else { return nil }
        return DateInterval(start: start, end: end)
    }

    /// Entries intersecting the day, clipped to it and sorted by start.
    /// An entry that only touches the day's edge is dropped.
    public static func entries(_ entries: [HealthTimelineEntry], on day: Date, calendar: Calendar) -> [HealthTimelineEntry] {
        guard let dayInterval = calendar.dateInterval(of: .day, for: day) else { return [] }
        return entries
            .compactMap { entry -> HealthTimelineEntry? in
                guard let clipped = entry.interval.intersection(with: dayInterval), clipped.duration > 0 else { return nil }
                return HealthTimelineEntry(id: entry.id, kind: entry.kind, interval: clipped)
            }
            .sorted { $0.interval.start < $1.interval.start }
    }
}
