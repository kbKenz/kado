import Foundation
import Testing
import KadoCore

@Suite("SleepSessionBuilder")
struct SleepSessionBuilderTests {
    /// 2026-04-13 22:00 UTC. Offsets are in minutes from here.
    let night = TestCalendar.utc.date(bySettingHour: 22, minute: 0, second: 0, of: TestCalendar.referenceDate)!

    func sample(_ stage: SleepSample.Stage, from start: Int, to end: Int, id: UUID = UUID()) -> SleepSample {
        SleepSample(
            id: id, stage: stage,
            interval: DateInterval(start: night.addingTimeInterval(TimeInterval(start * 60)),
                                   end: night.addingTimeInterval(TimeInterval(end * 60)))
        )
    }

    func minutes(_ entry: HealthTimelineEntry) -> (Int, Int) {
        (Int(entry.interval.start.timeIntervalSince(night) / 60), Int(entry.interval.end.timeIntervalSince(night) / 60))
    }

    @Test("Watch night: contiguous asleep stages give one session")
    func watchNightMerges() {
        let first = UUID()
        let sessions = SleepSessionBuilder.sessions(from: [
            sample(.asleep, from: 30, to: 120, id: first),
            sample(.asleep, from: 120, to: 300),
            sample(.asleep, from: 300, to: 510),
        ])
        #expect(sessions.count == 1)
        #expect(minutes(sessions[0]) == (30, 510))
        #expect(sessions[0].kind == .sleep)
        #expect(sessions[0].id == first)
    }

    @Test("iPhone only: inBed is the fallback source")
    func inBedFallback() {
        let sessions = SleepSessionBuilder.sessions(from: [sample(.inBed, from: 0, to: 480)])
        #expect(sessions.count == 1)
        #expect(minutes(sessions[0]) == (0, 480))
    }

    @Test("Asleep wins over inBed when both exist")
    func asleepWinsOverInBed() {
        let sessions = SleepSessionBuilder.sessions(from: [
            sample(.inBed, from: 0, to: 540),
            sample(.asleep, from: 40, to: 500),
        ])
        #expect(sessions.count == 1)
        #expect(minutes(sessions[0]) == (40, 500))
    }

    @Test("A 20-minute awake gap merges")
    func shortGapMerges() {
        let sessions = SleepSessionBuilder.sessions(from: [
            sample(.asleep, from: 0, to: 200),
            sample(.awake, from: 200, to: 220),
            sample(.asleep, from: 220, to: 480),
        ])
        #expect(sessions.count == 1)
        #expect(minutes(sessions[0]) == (0, 480))
    }

    @Test("A gap of exactly 30 minutes merges")
    func boundaryGapMerges() {
        let sessions = SleepSessionBuilder.sessions(from: [
            sample(.asleep, from: 0, to: 200),
            sample(.asleep, from: 230, to: 480),
        ])
        #expect(sessions.count == 1)
    }

    @Test("A 2-hour gap splits into two sessions")
    func longGapSplits() {
        let sessions = SleepSessionBuilder.sessions(from: [
            sample(.asleep, from: 0, to: 420),
            sample(.asleep, from: 540, to: 600),
        ])
        #expect(sessions.count == 2)
        #expect(minutes(sessions[0]) == (0, 420))
        #expect(minutes(sessions[1]) == (540, 600))
    }

    @Test("Overlapping samples from two sources give one session")
    func overlappingSourcesDeduplicate() {
        let sessions = SleepSessionBuilder.sessions(from: [
            sample(.asleep, from: 0, to: 400),
            sample(.asleep, from: 10, to: 420),
        ])
        #expect(sessions.count == 1)
        #expect(minutes(sessions[0]) == (0, 420))
    }

    @Test("Unsorted input gives the same result as sorted input")
    func orderIndependent() {
        let samples = [sample(.asleep, from: 300, to: 480), sample(.asleep, from: 0, to: 290)]
        #expect(SleepSessionBuilder.sessions(from: samples).map(minutes).map { [$0.0, $0.1] }
            == SleepSessionBuilder.sessions(from: samples.reversed()).map(minutes).map { [$0.0, $0.1] })
    }

    @Test("Awake samples alone give no session")
    func awakeOnlyIsEmpty() {
        #expect(SleepSessionBuilder.sessions(from: [sample(.awake, from: 0, to: 60)]).isEmpty)
    }

    @Test("No samples give no session")
    func emptyInput() {
        #expect(SleepSessionBuilder.sessions(from: []).isEmpty)
    }
}
