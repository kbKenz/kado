import Foundation
import Testing
import KadoCore

@Suite("WorkSession")
struct WorkSessionTests {
    private let start = Date(timeIntervalSince1970: 1_000_000)

    @Test("Running: elapsed is now minus start")
    func running() {
        let session = WorkSession(startedAt: start)
        #expect(session.elapsed(at: start.addingTimeInterval(48 * 60)) == 2880.0)
        #expect(!session.isPaused)
    }

    @Test("Paused: the open pause does not count")
    func paused() {
        let session = WorkSession(startedAt: start, pausedAt: start.addingTimeInterval(600))
        #expect(session.elapsed(at: start.addingTimeInterval(900)) == 600.0)
        #expect(session.isPaused)
    }

    @Test("Resumed: finished pauses are subtracted")
    func resumed() {
        let session = WorkSession(startedAt: start, pausedSeconds: 300)
        #expect(session.elapsed(at: start.addingTimeInterval(900)) == 600.0)
    }

    @Test("Finished: elapsed stops at the end, whatever now is")
    func finished() {
        let session = WorkSession(startedAt: start, endedAt: start.addingTimeInterval(1200), pausedSeconds: 200)
        #expect(session.elapsed(at: start.addingTimeInterval(99_999)) == 1000.0)
        #expect(!session.isPaused)
        #expect(!session.isOpen)
    }

    @Test("A clock behind the start never gives negative time")
    func neverNegative() {
        let session = WorkSession(startedAt: start)
        #expect(session.elapsed(at: start.addingTimeInterval(-60)) == 0.0)
    }

    @Test("A pause still open at the end is not worked time")
    func openPauseAtEnd() {
        let session = WorkSession(
            startedAt: start,
            endedAt: start.addingTimeInterval(900),
            pausedAt: start.addingTimeInterval(600)
        )
        #expect(session.elapsed(at: start.addingTimeInterval(5000)) == 600.0)
        #expect(!session.isPaused)
    }

    @Test("Finished pauses and an open pause both count")
    func finishedAndOpenPause() {
        let session = WorkSession(startedAt: start, pausedAt: start.addingTimeInterval(600), pausedSeconds: 300)
        #expect(session.elapsed(at: start.addingTimeInterval(900)) == 300.0)
    }

    @Test("A pause recorded before the start counts from the start")
    func pauseBeforeStart() {
        let session = WorkSession(startedAt: start, pausedAt: start.addingTimeInterval(-100))
        #expect(session.elapsed(at: start.addingTimeInterval(300)) == 0.0)
    }
}
