import Foundation
import Testing
@testable import Kado
import KadoCore

/// Model requests run one at a time, give up after a time limit, and
/// turn every failure into "no answer".
@MainActor
@Suite("ItemSuggestionRunner")
struct ItemSuggestionRunnerTests {
    /// Sleep stand-in for the time limit: suspends until `fire()`.
    final class ManualSleeper {
        private(set) var requested: [Duration] = []
        private var pending: [CheckedContinuation<Void, Never>] = []

        func sleep(_ duration: Duration) async throws {
            requested.append(duration)
            await withCheckedContinuation { pending.append($0) }
        }

        func fire() {
            let waiting = pending
            pending.removeAll()
            waiting.forEach { $0.resume() }
        }
    }

    let request = ItemSuggestionRequest(title: "Book IELTS test", kind: .task, goals: [])

    /// With a manual sleeper the time limit passes only on `fire()`;
    /// without one it is a real minute, which no test reaches.
    func makeRunner(_ suggester: MockItemSuggester, sleeper: ManualSleeper? = nil) -> ItemSuggestionRunner {
        guard let sleeper else { return ItemSuggestionRunner(suggester: suggester, timeout: .seconds(60)) }
        return ItemSuggestionRunner(suggester: suggester, timeout: .seconds(5), sleep: sleeper.sleep)
    }

    /// Lets queued main-actor work run until `condition` holds.
    func settle(until condition: () -> Bool) async {
        for _ in 0..<200 where !condition() {
            await Task.yield()
        }
    }

    @Test("The model's answer comes through")
    func answer() async {
        let suggester = MockItemSuggester(result: .success(ModelItemSuggestion(category: .study)))
        let runner = makeRunner(suggester)
        let answer = await runner.suggestion(for: request)
        #expect(answer == ModelItemSuggestion(category: .study))
        #expect(suggester.requests == [request])
    }

    @Test("An error gives no answer")
    func error() async {
        let suggester = MockItemSuggester(result: .failure(.failed))
        let runner = makeRunner(suggester)
        #expect(await runner.suggestion(for: request) == nil)
    }

    @Test("A request that runs past the time limit gives no answer")
    func timeout() async {
        let suggester = MockItemSuggester(result: .success(ModelItemSuggestion(category: .study)))
        suggester.holdsUntilReleased = true
        let sleeper = ManualSleeper()
        let runner = makeRunner(suggester, sleeper: sleeper)
        let call = Task { await runner.suggestion(for: request) }
        await settle { !sleeper.requested.isEmpty && suggester.running == 1 }
        #expect(sleeper.requested == [.seconds(5)])
        sleeper.fire()
        #expect(await call.value == nil)
        suggester.release()
    }

    @Test("The default time limit is 2.5 seconds")
    func defaultTimeout() {
        #expect(ItemSuggestionRunner.defaultTimeout == .milliseconds(2500))
    }

    @Test("A new request waits for the one before it: never two at once")
    func oneAtATime() async {
        let suggester = MockItemSuggester(result: .success(ModelItemSuggestion(category: .study)))
        suggester.holdsUntilReleased = true
        let runner = makeRunner(suggester)
        let first = Task { await runner.suggestion(for: request) }
        await settle { suggester.running == 1 }
        let next = ItemSuggestionRequest(title: "Book IELTS test now", kind: .task, goals: [])
        let second = Task { await runner.suggestion(for: next) }
        for _ in 0..<50 { await Task.yield() }
        // The second request waits; the first is still the only one.
        #expect(suggester.requests.count == 1)
        suggester.release()
        await settle { suggester.requests.count == 2 }
        suggester.release()
        _ = await first.value
        #expect(await second.value == ModelItemSuggestion(category: .study))
        #expect(suggester.mostRunning == 1)
        #expect(suggester.requests.map(\.title) == ["Book IELTS test", "Book IELTS test now"])
    }

    @Test("A cancelled caller gets no answer")
    func cancelled() async {
        let suggester = MockItemSuggester(result: .success(ModelItemSuggestion(category: .study)))
        suggester.holdsUntilReleased = true
        let runner = makeRunner(suggester)
        let call = Task { await runner.suggestion(for: request) }
        await settle { suggester.running == 1 }
        call.cancel()
        suggester.release()
        #expect(await call.value == nil)
    }
}
