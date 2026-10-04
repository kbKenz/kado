import Foundation
import SwiftData
import Testing
@testable import Kado
import KadoCore

@Suite("NowInputBuilder")
@MainActor
struct NowInputBuilderTests {
    private let calendar = TestCalendar.utc
    private var now: Date { TestCalendar.instant(calendar, 2026, 4, 13, 10) }

    private func context() throws -> ModelContext {
        let schema = Schema(versionedSchema: KadoSchemaV8.self)
        return ModelContext(try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)))
    }

    private var builder: NowInputBuilder {
        NowInputBuilder(boundary: DayBoundary(calendar: calendar, startHour: 0), evaluator: DefaultFrequencyEvaluator(calendar: calendar))
    }

    @Test("Done, archived and cancelled tasks, untimed blocks and negative habits are skipped")
    func skipsUnworkable() throws {
        let context = try context()
        let open = TaskRecord(title: "Open")
        let done = TaskRecord(title: "Done", completedAt: now)
        let cancelled = TaskRecord(title: "Cancelled", externalCancelledAt: now)
        let negative = HabitRecord(name: "No sugar", type: .negative, createdAt: now.addingTimeInterval(-86_400 * 3))
        [open, done, cancelled].forEach(context.insert)
        context.insert(negative)
        for task in [open, done, cancelled] {
            context.insert(ScheduleBlockRecord(plannedDay: now, startAt: now, task: task))
        }
        context.insert(ScheduleBlockRecord(plannedDay: now, startAt: now, habit: negative))
        context.insert(ScheduleBlockRecord(plannedDay: now, task: open))
        try context.save()

        let input = try builder.build(now: now, in: context)
        #expect(input.blocks.map(\.item.title) == ["Open"])
    }

    @Test("A block whose end is not after its start is skipped")
    func skipsEmptyRange() throws {
        let context = try context()
        let task = TaskRecord(title: "Open")
        context.insert(task)
        context.insert(ScheduleBlockRecord(plannedDay: now, startAt: now, endAt: now, task: task))
        context.insert(ScheduleBlockRecord(plannedDay: now, startAt: now, endAt: now.addingTimeInterval(-60), task: task))
        context.insert(ScheduleBlockRecord(plannedDay: now, startAt: now, endAt: now.addingTimeInterval(60), task: task))
        context.insert(ScheduleBlockRecord(plannedDay: now, startAt: now, task: task))
        try context.save()

        let input = try builder.build(now: now, in: context)
        #expect(input.blocks.count == 2)
    }

    @Test("The open session carries its item and block")
    func openSession() throws {
        let context = try context()
        let task = TaskRecord(title: "Research")
        context.insert(task)
        let block = ScheduleBlockRecord(plannedDay: now, startAt: now, task: task)
        context.insert(block)
        context.insert(WorkSessionRecord(startedAt: now, task: task, scheduleBlock: block))
        try context.save()

        let input = try builder.build(now: now, in: context)
        #expect(input.openSession?.item == .task(id: task.id, title: "Research"))
        #expect(input.openSession?.blockID == block.id)
    }

    @Test("Start candidates: open tasks, then outstanding habits")
    func candidates() throws {
        let context = try context()
        context.insert(TaskRecord(title: "Write"))
        context.insert(TaskRecord(title: "Call"))
        context.insert(HabitRecord(name: "Read", createdAt: now.addingTimeInterval(-86_400 * 3)))
        try context.save()
        let input = try builder.build(now: now, in: context)
        #expect(input.startCandidates.map(\.title) == ["Call", "Write", "Read"])
    }

    @Test("A habit created after today is not workable")
    func futureHabitSkipped() throws {
        let context = try context()
        context.insert(HabitRecord(name: "Later", createdAt: now.addingTimeInterval(86_400 * 3)))
        try context.save()
        let input = try builder.build(now: now, in: context)
        #expect(input.startCandidates.isEmpty)
    }
}
