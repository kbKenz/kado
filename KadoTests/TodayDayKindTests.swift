import Foundation
import Testing
@testable import Kado

@Suite("TodayDayKind")
struct TodayDayKindTests {
    private let cal = TestCalendar.utc

    @Test("Past, today and future by calendar day")
    func kinds() {
        let today = TestCalendar.referenceDate
        #expect(TodayDayKind(day: TestCalendar.day(-1), today: today, calendar: cal) == .past)
        #expect(TodayDayKind(day: cal.startOfDay(for: today), today: today, calendar: cal) == .today)
        #expect(TodayDayKind(day: TestCalendar.day(1), today: today, calendar: cal) == .future)
    }

    @Test("Only future days refuse habit logging")
    func logging() {
        #expect(TodayDayKind.past.allowsHabitLogging)
        #expect(TodayDayKind.today.allowsHabitLogging)
        #expect(!TodayDayKind.future.allowsHabitLogging)
    }
}
