import Foundation
import Testing
import KadoCore

@Suite("NowResolver")
struct NowResolverTests {
    private let calendar = TestCalendar.utc
    private var boundary: DayBoundary { DayBoundary(calendar: calendar, startHour: 0) }

    private func at(_ hour: Int, _ minute: Int = 0, day: Int = 13) -> Date {
        TestCalendar.instant(calendar, 2026, 4, day, hour, minute)
    }

    private func block(_ title: String, _ start: Date, _ end: Date?, created: Date? = nil) -> NowBlock {
        NowBlock(id: UUID(), item: .task(id: UUID(), title: title), start: start, end: end, createdAt: created ?? at(0))
    }

    private func resolve(now: Date, blocks: [NowBlock], open: OpenSession? = nil, startHour: Int = 0) -> NowScreen {
        NowResolver(boundary: DayBoundary(calendar: calendar, startHour: startHour))
            .resolve(now: now, blocks: blocks, openSession: open)
    }

    @Test("A block covering now is suggested, with the next one up")
    func current() {
        let research = block("Research", at(10), at(12))
        let outreach = block("Outreach", at(14), at(15))
        let screen = resolve(now: at(10, 17), blocks: [outreach, research])
        #expect(screen.state == .suggestedCurrent(research))
        #expect(screen.upNext == outreach)
    }

    @Test("Between blocks, the next block is suggested and nothing else is up next")
    func gap() {
        let outreach = block("Outreach", at(14), at(15))
        let review = block("Review", at(16), at(17))
        let screen = resolve(now: at(12, 30), blocks: [outreach, review])
        #expect(screen.state == .suggestedNext(outreach))
        #expect(screen.upNext == nil)
    }

    @Test("After the last block the screen is empty")
    func endOfDay() {
        let screen = resolve(now: at(20), blocks: [block("Research", at(10), at(12))])
        #expect(screen.state == .empty)
        #expect(screen.upNext == nil)
    }

    @Test("Blocks on other days are ignored")
    func otherDays() {
        let tomorrow = block("Tomorrow", at(9, day: 14), at(10, day: 14))
        #expect(resolve(now: at(20), blocks: [tomorrow]).state == .empty)
    }

    @Test("Overlap: the earlier start wins, then the earlier created")
    func overlap() {
        let early = block("Early", at(9), at(12))
        let late = block("Late", at(10), at(11))
        #expect(resolve(now: at(10, 30), blocks: [late, early]).state == .suggestedCurrent(early))
        let first = block("First", at(10), at(11), created: at(1))
        let second = block("Second", at(10), at(11), created: at(2))
        #expect(resolve(now: at(10, 30), blocks: [second, first]).state == .suggestedCurrent(first))
    }

    @Test("A block with a start and no end lasts one hour")
    func startWithoutEnd() {
        let open = block("Open-ended", at(10), nil)
        #expect(resolve(now: at(10, 59), blocks: [open]).state == .suggestedCurrent(open))
        #expect(resolve(now: at(11, 1), blocks: [open]).state == .empty)
    }

    @Test("A running session wins over any plan and keeps its block's range")
    func openSessionWins() {
        let research = block("Research", at(10), at(12))
        let outreach = block("Outreach", at(14), at(15))
        let running = OpenSession(id: UUID(), item: research.item, session: WorkSession(startedAt: at(10, 17)), blockID: research.id)
        let screen = resolve(now: at(13), blocks: [research, outreach], open: running)
        #expect(screen.state == .running(running, plannedRange: research.range))
        #expect(screen.upNext == outreach)
    }

    @Test("A session without a block has no planned range")
    func sessionWithoutBlock() {
        let item = NowItem.task(id: UUID(), title: "Ad hoc")
        let running = OpenSession(id: UUID(), item: item, session: WorkSession(startedAt: at(9)), blockID: nil)
        #expect(resolve(now: at(9, 30), blocks: [], open: running).state == .running(running, plannedRange: nil))
    }

    @Test("Today follows the day start hour")
    func dayStartHour() {
        // Day starts at 04:00: 02:00 on the 14th still belongs to the 13th.
        let late = block("Late night", at(23, day: 13), at(23, 59, day: 13))
        let screen = resolve(now: at(2, day: 14), blocks: [late], startHour: 4)
        #expect(screen.state == .empty)
        let early = block("Before rollover", at(3, day: 14), at(3, 30, day: 14))
        #expect(resolve(now: at(2, day: 14), blocks: [early], startHour: 4).state == .suggestedNext(early))
    }

    @Test("While a session runs, a block that already started is never up next")
    func upNextSkipsStartedBlocks() {
        let a = block("A", at(10), at(12))
        let b = block("B", at(11), at(11, 30))
        let c = block("C", at(14), at(15))
        let running = OpenSession(id: UUID(), item: a.item, session: WorkSession(startedAt: at(10)), blockID: a.id)
        #expect(resolve(now: at(13), blocks: [a, b, c], open: running).upNext == c)
    }

    @Test("Back-to-back blocks: at the shared instant the later one is current")
    func backToBack() {
        let first = block("First", at(10), at(11))
        let second = block("Second", at(11), at(12))
        #expect(resolve(now: at(11), blocks: [first, second]).state == .suggestedCurrent(second))
    }

    @Test("A session whose block is on another day has no planned range")
    func sessionBlockOtherDay() {
        let yesterday = block("Yesterday", at(10, day: 12), at(12, day: 12))
        let running = OpenSession(id: UUID(), item: yesterday.item, session: WorkSession(startedAt: at(9)), blockID: yesterday.id)
        #expect(resolve(now: at(9, 30), blocks: [yesterday], open: running).state == .running(running, plannedRange: nil))
    }

    @Test("An ad-hoc session hides the planned block covering now")
    func adHocHidesCurrentBlock() {
        let covering = block("Covering", at(10), at(12))
        let later = block("Later", at(14), at(15))
        let item = NowItem.task(id: UUID(), title: "Ad hoc")
        let running = OpenSession(id: UUID(), item: item, session: WorkSession(startedAt: at(10, 15)), blockID: nil)
        let screen = resolve(now: at(10, 30), blocks: [covering, later], open: running)
        #expect(screen.state == .running(running, plannedRange: nil))
        #expect(screen.upNext == later)
    }
}
