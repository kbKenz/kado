import Foundation
import SwiftData
import Testing
@testable import Kado
import KadoCore

/// The pieces that let a habit tap rebuild the widget off the main
/// actor: the store read as plain values, the compute on those values,
/// today's tally read without the series, and the ticketed write that
/// keeps a slow older pass from landing over a newer one.
@Suite("WidgetSnapshotBuilder off the main actor")
@MainActor
struct WidgetSnapshotBackgroundTests {
    private func makeContainer() throws -> ModelContainer {
        let schema = Schema(versionedSchema: KadoSchemaV9.self)
        return try ModelContainer(
            for: schema,
            migrationPlan: KadoMigrationPlan.self,
            configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        )
    }

    nonisolated private static let probes: [(String, Calendar, Date)] = [
        ("UTC", TestCalendar.utc, TestCalendar.day(0)),
        ("Paris, across fall-back", TestCalendar.paris, TestCalendar.instant(TestCalendar.paris, 2026, 10, 22, 12)),
        ("Havana, across the midnight transition", TestCalendar.havana, TestCalendar.instant(TestCalendar.havana, 2026, 3, 6, 12)),
    ]

    /// Every frequency and type shape, with a patchy history, plus an
    /// archived habit and a habit with no history at all. `skip` drops
    /// a different set of days per call so the probes see both done
    /// and undone days.
    private func seed(_ context: ModelContext, calendar: Calendar, reference: Date, skip: Int) {
        func daysAgo(_ n: Int) -> Date {
            calendar.date(byAdding: .day, value: -n, to: reference)!
        }
        let shapes: [(String, Frequency, HabitType)] = [
            ("Daily", .daily, .binary),
            ("Weekly", .daysPerWeek(3), .binary),
            ("Tue/Thu", .specificDays([.tuesday, .thursday]), .counter(target: 5)),
            ("Cycle", .everyNDays(3), .binary),
            ("No sugar", .daily, .negative),
            ("Read", .daily, .timer(targetSeconds: 600)),
        ]
        for (index, (name, frequency, type)) in shapes.enumerated() {
            let habit = HabitRecord(name: name, frequency: frequency, type: type, createdAt: daysAgo(40))
            habit.sortOrder = index
            context.insert(habit)
            for n in 0...39 where n % 4 != skip {
                // Values below the counter/timer targets on some days,
                // so partial states show up too.
                let value: Double = n % 3 == 0 ? 2 : 600
                context.insert(CompletionRecord(date: daysAgo(n), value: value, habit: habit))
            }
        }
        let archived = HabitRecord(name: "Archived", frequency: .daily, type: .binary,
                                   createdAt: daysAgo(40), archivedAt: daysAgo(3))
        context.insert(archived)
        context.insert(CompletionRecord(date: daysAgo(0), value: 1, habit: archived))
        context.insert(HabitRecord(name: "Fresh", frequency: .daily, type: .binary, createdAt: reference,
                                   sortOrder: shapes.count))
    }

    @Test("Today's tally read on its own is the series' first day's tally", arguments: probes)
    func dayProgressMatchesSeries(zone: String, calendar: Calendar, reference: Date) throws {
        for skip in 0..<4 {
            let container = try makeContainer()
            seed(container.mainContext, calendar: calendar, reference: reference, skip: skip)
            try container.mainContext.save()

            let source = WidgetSnapshotBuilder.Source(context: container.mainContext)
            let day = calendar.startOfDay(for: reference)
            for offset in 0..<3 {
                let asOf = calendar.date(byAdding: .day, value: offset, to: day)!
                let series = WidgetSnapshotBuilder.buildSeries(
                    from: container.mainContext, asOf: asOf, calendar: calendar
                )
                let progress = WidgetSnapshotBuilder.dayProgress(source: source, asOf: asOf, calendar: calendar)
                #expect(progress == series.days.first?.dayProgress, "\(zone), skip \(skip), +\(offset)")
            }
        }
    }

    @Test("A series built from a store read matches one built from the context", arguments: probes)
    func seriesFromSourceMatchesContext(zone: String, calendar: Calendar, reference: Date) throws {
        let container = try makeContainer()
        seed(container.mainContext, calendar: calendar, reference: reference, skip: 1)
        try container.mainContext.save()

        let source = WidgetSnapshotBuilder.Source(context: container.mainContext)
        let fromValues = WidgetSnapshotBuilder.buildSeries(source: source, asOf: reference, calendar: calendar)
        let fromContext = WidgetSnapshotBuilder.buildSeries(
            from: container.mainContext, asOf: reference, calendar: calendar
        )
        #expect(Self.comparable(fromValues) == Self.comparable(fromContext), "\(zone)")
        #expect(fromValues.days.count == WidgetSnapshotBuilder.horizonDays)
    }

    @Test("A store read keeps the active habits in order with their own completions")
    func sourceReadsActiveHabitsOnly() throws {
        let container = try makeContainer()
        seed(container.mainContext, calendar: TestCalendar.utc, reference: TestCalendar.day(0), skip: 0)
        try container.mainContext.save()

        let source = WidgetSnapshotBuilder.Source(context: container.mainContext)
        #expect(source.habits.map(\.name) == ["Daily", "Weekly", "Tue/Thu", "Cycle", "No sugar", "Read", "Fresh"])
        #expect(source.allCompletions.allSatisfy { completion in
            source.habits.contains { $0.id == completion.habitID }
        })
        for habit in source.habits {
            #expect(source.completions(for: habit).allSatisfy { $0.habitID == habit.id })
        }
    }

    @Test("A write whose store read is older than the file's is dropped")
    func olderTicketNeverOverwritesNewer() throws {
        let sink = Sink()
        let order = WidgetSnapshotWriteOrder { sink.append($0) }
        let first = order.ticket()
        let second = order.ticket()
        let third = order.ticket()
        let old = WidgetSnapshotSeries(generatedAt: TestCalendar.day(0), days: [])
        let new = WidgetSnapshotSeries(generatedAt: TestCalendar.day(1), days: [])

        // The newer pass finishes first; the older one must not land
        // over it, and neither may a repeat of the same ticket.
        #expect(order.write(new, ticket: second))
        #expect(!order.write(old, ticket: first))
        #expect(!order.write(new, ticket: second))
        #expect(order.write(new, ticket: third))

        let written = sink.items.compactMap { WidgetSnapshotStore.decode($0) }
        #expect(written.map(\.generatedAt) == [TestCalendar.day(1), TestCalendar.day(1)])
    }

    @Test("Writes in read order all land")
    func inOrderWritesAllLand() {
        let sink = Sink()
        let order = WidgetSnapshotWriteOrder { sink.append($0) }
        for n in 0..<5 {
            let ticket = order.ticket()
            #expect(order.write(WidgetSnapshotSeries(generatedAt: TestCalendar.day(n), days: []), ticket: ticket))
        }
        #expect(sink.items.count == 5)
    }

    /// The parts of a series that are a function of the data —
    /// `generatedAt` is the wall clock at build time and differs.
    private static func comparable(_ series: WidgetSnapshotSeries) -> [String] {
        series.days.map { day in
            let habits = day.habits.map { "\($0.id)|\($0.currentStreak)|\($0.bestStreak)|\($0.currentScore)" }
            let today = day.today.map { "\($0.id)|\($0.status)|\($0.progress)|\(String(describing: $0.valueToday))|\($0.streak)" }
            let matrix = day.matrix.map { "\($0.habit.id)|\($0.cells)" }
            return "\(day.logicalDay)|\(day.matrixDays)|\(day.totalDueToday)|\(day.completedToday)|\(habits)|\(today)|\(matrix)"
        }
    }

    /// Single-threaded in these tests: the write order calls it inside
    /// its own lock.
    private final class Sink: @unchecked Sendable {
        private(set) var items: [Data] = []
        func append(_ data: Data) { items.append(data) }
    }
}
