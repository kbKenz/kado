import Foundation
import SwiftData
import Testing
@testable import Kado
import KadoCore

@Suite("CoalescingTask")
@MainActor
struct CoalescingTaskTests {
    @Test("A burst of requests runs once, with the last one")
    func burstRunsLastOnly() async {
        let passes = CoalescingTask()
        var runs: [Int] = []
        for n in 0..<5 {
            passes.schedule(after: .milliseconds(20)) { runs.append(n) }
        }
        await passes.flush()
        #expect(runs == [4])
    }

    @Test("A burst with no delay still runs once")
    func zeroDelayBurstRunsLastOnly() async {
        let passes = CoalescingTask()
        var runs: [Int] = []
        for n in 0..<5 {
            passes.schedule(after: .zero) { runs.append(n) }
        }
        await passes.flush()
        #expect(runs == [4])
    }

    @Test("A request made while a pass runs waits for it, then runs")
    func passesNeverOverlap() async {
        let passes = CoalescingTask()
        var log: [String] = []
        var started = false
        passes.schedule(after: .zero) {
            started = true
            log.append("A start")
            try? await Task.sleep(for: .milliseconds(50))
            log.append("A end")
        }
        while !started { await Task.yield() }
        passes.schedule(after: .zero) {
            log.append("B start")
            log.append("B end")
        }
        await passes.flush()
        #expect(log == ["A start", "A end", "B start", "B end"])
    }

    @Test("Cancelling drops a pass that has not started")
    func cancelDropsPendingPass() async {
        let passes = CoalescingTask()
        var runs = 0
        passes.schedule(after: .milliseconds(20)) { runs += 1 }
        passes.cancel()
        await passes.flush()
        #expect(runs == 0)
    }

    @Test("Flushing with nothing scheduled returns at once")
    func flushWhenIdle() async {
        await CoalescingTask().flush()
    }

    @Test("A reload whose store is gone by the time it runs is skipped, not a trap")
    func reloadForAReleasedStoreIsSkipped() async throws {
        let schema = Schema(versionedSchema: KadoSchemaV9.self)
        do {
            let container = try ModelContainer(
                for: schema,
                configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            )
            container.mainContext.insert(HabitRecord(name: "Gone"))
            try container.mainContext.save()
            WidgetReloader.reloadAll(using: container.mainContext)
            RemindersSync.rescheduleAll(using: container.mainContext)
        }
        await WidgetReloader.flush()
    }
}
