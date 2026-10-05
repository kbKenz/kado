import Foundation
import Testing
import KadoCore
@testable import Kado

@MainActor
@Suite("InsightsHealthLoader")
struct InsightsHealthLoaderTests {
    let calendar = TestCalendar.utc

    /// `hour:minute` on the day `offset` days from Monday 2026-04-13.
    func time(_ offset: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        InsightsTestSupport.time(offset, hour, minute, calendar: calendar)
    }

    func sample(_ stage: SleepSample.Stage, _ start: Date, _ end: Date) -> SleepSample {
        SleepSample(id: UUID(), stage: stage, interval: DateInterval(start: start, end: end))
    }

    var window: DateInterval { DateInterval(start: time(-61, 12), end: time(0, 18)) }

    func load(_ provider: StubHealthTimelineProvider, isEnabled: Bool = true) async -> InsightsHealth {
        do {
            return try await InsightsHealthLoader(provider: provider, calendar: calendar).health(in: window, isEnabled: isEnabled)
        } catch {
            Issue.record("The loader threw although the task was not cancelled")
            return .disconnected
        }
    }

    // MARK: - Opt-in

    @Test("Off: disconnected, and Health is never queried")
    func disabledSkipsProvider() async {
        let provider = StubHealthTimelineProvider()
        provider.sleepSamples = [sample(.asleep, time(-1, 23), time(0, 7))]
        let health = await load(provider, isEnabled: false)
        #expect(health == .disconnected)
        #expect(provider.queryCount == 0)
    }

    @Test("No Health on the device: disconnected, and Health is never queried")
    func unavailableSkipsProvider() async {
        let provider = StubHealthTimelineProvider()
        provider.isAvailable = false
        let health = await load(provider)
        #expect(health == .disconnected)
        #expect(provider.queryCount == 0)
    }

    @Test("On with nothing recorded: connected and empty, both reads cover the window")
    func connectedButEmpty() async {
        let provider = StubHealthTimelineProvider()
        let health = await load(provider)
        #expect(health == InsightsHealth(isConnected: true))
        #expect(provider.queriedIntervals == [window, window])
    }

    // MARK: - Sleep

    @Test("A month with a Watch on some nights and only an iPhone on others keeps every night")
    func mixedWatchAndPhoneMonth() async {
        let provider = StubHealthTimelineProvider()
        var expected: [DateInterval] = []
        for night in 1...30 {
            let bed = -night
            let wake = bed + 1
            if night.isMultiple(of: 2) {
                // The iPhone's time in bed, and the Watch's stages around a short wake-up.
                provider.sleepSamples += [
                    sample(.inBed, time(bed, 22, 45), time(wake, 7, 15)),
                    sample(.asleep, time(bed, 23, 10), time(wake, 2)),
                    sample(.awake, time(wake, 2), time(wake, 2, 10)),
                    sample(.asleep, time(wake, 2, 10), time(wake, 6, 50)),
                ]
                expected.append(DateInterval(start: time(bed, 23, 10), end: time(wake, 6, 50)))
            } else {
                provider.sleepSamples.append(sample(.inBed, time(bed, 23, 30), time(wake, 7)))
                expected.append(DateInterval(start: time(bed, 23, 30), end: time(wake, 7)))
            }
        }

        let health = await load(provider)

        #expect(health.isConnected)
        #expect(health.sleep == expected.sorted { $0.start < $1.start })
        // Built in one go, the fifteen iPhone-only nights would be lost.
        #expect(SleepSessionBuilder.sessions(from: provider.sleepSamples).count == 15)
    }

    @Test("Noon splits the nights: a sample from noon on belongs to the next night")
    func noonSplitsNights() async {
        let provider = StubHealthTimelineProvider()
        let lateMorning = sample(.inBed, time(-1, 1), time(-1, 11, 59))
        let nap = sample(.asleep, time(-1, 12), time(-1, 13))
        provider.sleepSamples = [nap, lateMorning]

        let health = await load(provider)

        // Separate nights, so the nap's asleep stage does not hide the
        // morning's time in bed.
        #expect(health.sleep == [lateMorning.interval, nap.interval])
        #expect(InsightsHealthLoader.night(of: time(-1, 11, 59), calendar: calendar) == InsightsTestSupport.day(-1))
        #expect(InsightsHealthLoader.night(of: time(-1, 12), calendar: calendar) == InsightsTestSupport.day(0))
    }

    @Test("Awake samples never make a night")
    func awakeOnly() async {
        let provider = StubHealthTimelineProvider()
        provider.sleepSamples = [sample(.awake, time(-1, 3), time(-1, 4))]
        let health = await load(provider)
        #expect(health.isConnected)
        #expect(health.sleep.isEmpty)
    }

    @Test("A night across a DST change stays one night", arguments: [
        TestCalendar.paris, TestCalendar.havana,
    ])
    func nightAcrossDST(calendar: Calendar) {
        // Paris skips 02:00-03:00 on 2026-03-29; Havana skips 00:00-01:00 on 2026-03-08.
        let isParis = calendar.timeZone.identifier == "Europe/Paris"
        let (month, day) = isParis ? (3, 28) : (3, 7)
        let inBed = sample(
            .inBed,
            TestCalendar.instant(calendar, 2026, month, day, 22, 30),
            TestCalendar.instant(calendar, 2026, month, day + 1, 4)
        )
        let asleep = sample(
            .asleep,
            TestCalendar.instant(calendar, 2026, month, day + 1, 4, 30),
            TestCalendar.instant(calendar, 2026, month, day + 1, 7)
        )

        let sessions = InsightsHealthLoader.sleepSessions(from: [inBed, asleep], calendar: calendar)

        // One window, so the asleep stage wins over the time in bed.
        #expect(sessions == [asleep.interval])
        #expect(
            InsightsHealthLoader.night(of: inBed.interval.start, calendar: calendar)
                == InsightsHealthLoader.night(of: asleep.interval.start, calendar: calendar)
        )
    }

    // MARK: - Workouts

    @Test("Workouts keep their name and interval; anything else is dropped")
    func workouts() async {
        let provider = StubHealthTimelineProvider()
        let run = DateInterval(start: time(-2, 7), end: time(-2, 7, 45))
        provider.workouts = [
            HealthTimelineEntry(id: UUID(), kind: .workout(name: "Running"), interval: run),
            HealthTimelineEntry(id: UUID(), kind: .sleep, interval: DateInterval(start: time(-3, 23), end: time(-2, 6))),
        ]
        let health = await load(provider)
        #expect(health.workouts == [InsightsWorkout(name: "Running", interval: run)])
    }

    // MARK: - Failures

    @Test("A sleep failure keeps the workouts, and stays connected")
    func sleepFailureKeepsWorkouts() async {
        let provider = StubHealthTimelineProvider()
        let run = DateInterval(start: time(-2, 7), end: time(-2, 8))
        provider.sleepSamples = [sample(.asleep, time(-1, 23), time(0, 7))]
        provider.workouts = [HealthTimelineEntry(id: UUID(), kind: .workout(name: "Running"), interval: run)]
        provider.sleepFails = true

        let health = await load(provider)

        #expect(health.isConnected)
        #expect(health.sleep.isEmpty)
        #expect(health.workouts.map(\.interval) == [run])
    }

    @Test("A workout failure keeps the sleep, and stays connected")
    func workoutFailureKeepsSleep() async {
        let provider = StubHealthTimelineProvider()
        let night = sample(.asleep, time(-1, 23), time(0, 7))
        provider.sleepSamples = [night]
        provider.workoutsFails = true

        let health = await load(provider)

        #expect(health.isConnected)
        #expect(health.sleep == [night.interval])
        #expect(health.workouts.isEmpty)
    }

    @Test("Cancelled during the reads: throws, so the caller keeps its previous value")
    func cancelledThrows() async {
        let provider = StubHealthTimelineProvider()
        provider.sleepSamples = [sample(.asleep, time(-1, 23), time(0, 7))]
        let loader = InsightsHealthLoader(provider: provider, calendar: calendar)
        let window = window
        // The task inherits the main actor, so it cannot start before cancel().
        let task = Task { try await loader.health(in: window, isEnabled: true) }
        task.cancel()

        let result = await task.result

        #expect(throws: CancellationError.self) { try result.get() }
    }

    // MARK: - Query window

    @Test("The query starts at noon before the previous period's first day", arguments: InsightsPeriod.allCases)
    func queryInterval(period: InsightsPeriod) {
        let now = time(0, 18)
        let interval = InsightsHealthLoader.queryInterval(
            for: period, today: InsightsTestSupport.day(0), now: now, calendar: calendar
        )
        #expect(interval.start == time(-2 * period.dayCount, 12))
        #expect(interval.end == now)
    }

    @Test("The query window starts on a real noon in a zone whose day can start at 01:00")
    func queryIntervalHavana() {
        let havana = TestCalendar.havana
        let today = havana.startOfDay(for: TestCalendar.instant(havana, 2026, 3, 9, 12))
        let now = TestCalendar.instant(havana, 2026, 3, 9, 18)
        let interval = InsightsHealthLoader.queryInterval(for: .week, today: today, now: now, calendar: havana)
        #expect(interval.start == TestCalendar.instant(havana, 2026, 2, 23, 12))
        #expect(interval.end == now)
    }
}
