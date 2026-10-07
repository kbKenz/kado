import Foundation
import SwiftData
import Testing
@testable import Kado
import KadoCore

/// The Calendar agenda fetches only the blocks around its day, then
/// keeps the ones `TaskScheduleItem.belongs(to:)` accepts. The fetch
/// must never drop a block the old fetch-everything path kept: untimed,
/// start-only, end-only, cross-midnight and multi-day blocks, on each
/// day they touch, in zones whose days are 23, 24 or 25 hours long.
@Suite("CalendarDayAgenda query")
@MainActor
struct CalendarDayAgendaQueryTests {
    private func makeContainer() throws -> ModelContainer {
        let schema = Schema(versionedSchema: KadoSchemaV10.self)
        return try ModelContainer(
            for: schema,
            migrationPlan: KadoMigrationPlan.self,
            configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        )
    }

    @Test("The day's fetch keeps every block that belongs to the day", arguments: [
        (TestCalendar.utc, TestCalendar.utc),
        (TestCalendar.paris, TestCalendar.paris),
        (TestCalendar.havana, TestCalendar.havana),
        // A query built in one zone, drawn in another.
        (TestCalendar.utc, TestCalendar.paris),
    ])
    func fetchKeepsEveryBelongingBlock(queryCalendar: Calendar, drawCalendar: Calendar) throws {
        // Held for the whole test: a context outlives a released container
        // only until its autosave fires, which traps.
        let container = try makeContainer()
        let ctx = container.mainContext
        // Around both 2026 transitions for Paris and Havana's midnight one.
        let anchors = [
            drawCalendar.date(from: DateComponents(year: 2026, month: 3, day: 8))!,
            drawCalendar.date(from: DateComponents(year: 2026, month: 3, day: 29))!,
            drawCalendar.date(from: DateComponents(year: 2026, month: 10, day: 25))!,
        ]
        for anchor in anchors {
            for dayOffset in -2...2 {
                let day = drawCalendar.startOfDay(for: drawCalendar.date(byAdding: .day, value: dayOffset, to: anchor)!)
                for (startHours, lengthHours) in [(-30.0, 2.0), (-3.0, 5.0), (10.0, 1.0), (22.5, 3.0), (23.0, 50.0), (-26.0, 80.0)] {
                    let start = day.addingTimeInterval(startHours * 3600)
                    let end = start.addingTimeInterval(lengthHours * 3600)
                    ctx.insert(ScheduleBlockRecord(plannedDay: day, startAt: start, endAt: end))
                    ctx.insert(ScheduleBlockRecord(plannedDay: day, startAt: start))
                    ctx.insert(ScheduleBlockRecord(plannedDay: day, endAt: end))
                    // Planned on another day than its times say.
                    ctx.insert(ScheduleBlockRecord(plannedDay: day.addingTimeInterval(-86_400 * 3), startAt: start, endAt: end))
                }
                ctx.insert(ScheduleBlockRecord(plannedDay: day))
                ctx.insert(ScheduleBlockRecord(plannedDay: day.addingTimeInterval(86_399)))
            }
        }
        try ctx.save()
        let all = try ctx.fetch(FetchDescriptor<ScheduleBlockRecord>(sortBy: [SortDescriptor(\.plannedDay)]))

        for anchor in anchors {
            for dayOffset in -4...4 {
                let day = drawCalendar.startOfDay(for: drawCalendar.date(byAdding: .day, value: dayOffset, to: anchor)!)
                let belongs = { (block: ScheduleBlockRecord) in
                    TaskScheduleItem(block).belongs(to: day, calendar: drawCalendar)
                }
                let fetched = try ctx.fetch(CalendarDayAgenda.blocksDescriptor(touching: day, calendar: queryCalendar))
                let expected = all.filter(belongs).map(\.id)
                #expect(!expected.isEmpty)
                #expect(Set(fetched.filter(belongs).map(\.id)) == Set(expected), "day \(day)")
                // Sorted by planned day, as the unbounded query was.
                #expect(fetched.map(\.plannedDay) == fetched.map(\.plannedDay).sorted())
                // And it is a narrowing, not the whole table.
                #expect(fetched.count < all.count)
            }
        }
    }
}
