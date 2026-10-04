import Foundation
import Testing
import KadoCore
@testable import Kado

@MainActor
@Suite("HealthTimelineLoader")
struct HealthTimelineLoaderTests {
    let calendar = TestCalendar.utc
    var day: Date { calendar.startOfDay(for: TestCalendar.referenceDate) }

    func entry(_ kind: HealthTimelineEntry.Kind, hours: ClosedRange<Int>) -> HealthTimelineEntry {
        HealthTimelineEntry(
            id: UUID(), kind: kind,
            interval: DateInterval(start: calendar.date(byAdding: .hour, value: hours.lowerBound, to: day)!,
                                   end: calendar.date(byAdding: .hour, value: hours.upperBound, to: day)!)
        )
    }

    @Test("Toggle off: provider is never called")
    func disabledSkipsProvider() async {
        let provider = StubHealthTimelineProvider()
        provider.sleep = [entry(.sleep, hours: 0...7)]
        let result = await HealthTimelineLoader(provider: provider, calendar: calendar).entries(on: day, isEnabled: false)
        #expect(result.isEmpty)
        #expect(provider.queryCount == 0)
    }

    @Test("Health unavailable: provider is never queried")
    func unavailableSkipsProvider() async {
        let provider = StubHealthTimelineProvider()
        provider.isAvailable = false
        let result = await HealthTimelineLoader(provider: provider, calendar: calendar).entries(on: day, isEnabled: true)
        #expect(result.isEmpty)
        #expect(provider.queryCount == 0)
    }

    @Test("Sleep failure keeps workouts")
    func sleepFailureKeepsWorkouts() async {
        let provider = StubHealthTimelineProvider()
        let run = entry(.workout(name: "Running"), hours: 7...8)
        provider.workouts = [run]
        provider.sleepFails = true
        let result = await HealthTimelineLoader(provider: provider, calendar: calendar).entries(on: day, isEnabled: true)
        #expect(result.map(\.id) == [run.id])
    }

    @Test("Workout failure keeps sleep")
    func workoutFailureKeepsSleep() async {
        let provider = StubHealthTimelineProvider()
        let night = entry(.sleep, hours: 0...7)
        provider.sleep = [night]
        provider.workoutsFails = true
        let result = await HealthTimelineLoader(provider: provider, calendar: calendar).entries(on: day, isEnabled: true)
        #expect(result.map(\.id) == [night.id])
    }

    @Test("Results are clipped to the day and sorted")
    func clipsAndSorts() async {
        let provider = StubHealthTimelineProvider()
        let night = entry(.sleep, hours: -2...7)
        let run = entry(.workout(name: "Running"), hours: 18...19)
        provider.sleep = [night]
        provider.workouts = [run]
        let result = await HealthTimelineLoader(provider: provider, calendar: calendar).entries(on: day, isEnabled: true)
        #expect(result.map(\.id) == [night.id, run.id])
        #expect(result.first?.interval.start == day)
    }
}
