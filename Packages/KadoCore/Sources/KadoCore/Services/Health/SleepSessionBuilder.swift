import Foundation

/// Turns raw sleep samples into the sessions the Calendar draws.
///
/// Asleep stages are the source when any exist. `inBed` is the
/// fallback for an iPhone without a Watch, which records only time in
/// bed. `awake` never forms a session. Overlaps (Watch and iPhone
/// recording the same night) and short wake-ups merge, so one night
/// reads as one band; a gap longer than ``mergeGap`` starts a new
/// session, so a nap stands on its own.
nonisolated public enum SleepSessionBuilder {
    /// A duration, not day arithmetic, so raw seconds are correct here.
    public static let mergeGap: TimeInterval = 30 * 60

    public static func sessions(from samples: [SleepSample]) -> [HealthTimelineEntry] {
        let asleep = samples.filter { $0.stage == .asleep }
        let source = asleep.isEmpty ? samples.filter { $0.stage == .inBed } : asleep
        let sorted = source.sorted { $0.interval.start < $1.interval.start }

        var sessions: [HealthTimelineEntry] = []
        for sample in sorted {
            if let last = sessions.last,
               sample.interval.start.timeIntervalSince(last.interval.end) <= mergeGap {
                let end = max(last.interval.end, sample.interval.end)
                sessions[sessions.count - 1] = HealthTimelineEntry(
                    id: last.id, kind: .sleep,
                    interval: DateInterval(start: last.interval.start, end: end)
                )
            } else {
                sessions.append(HealthTimelineEntry(id: sample.id, kind: .sleep, interval: sample.interval))
            }
        }
        return sessions
    }
}
