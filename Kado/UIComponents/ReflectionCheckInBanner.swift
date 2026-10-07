import SwiftUI
import KadoCore

/// The bottom-of-Today card in the days the monthly check-in is open.
/// `TodayCard` decides when; "Not now" hides it until the next month.
struct ReflectionCheckInBanner: View {
    let month: ReflectionMonth
    let onStart: () -> Void
    let onHide: () -> Void
    @Environment(\.calendar) private var calendar

    var body: some View {
        let name = month.monthName(in: calendar)
        TodayNoticeCard(
            systemImage: "book.closed",
            message: "It's time to look back at \(name). About 15 minutes, just for you.",
            primaryTitle: "Start check-in",
            primaryIdentifier: AccessibilityID.Reflect.todayCardStart,
            onPrimary: onStart,
            hideIdentifier: AccessibilityID.Reflect.todayCardHide,
            onHide: onHide
        )
    }
}

#Preview("In place") {
    List {
        Section {
            ReflectionCheckInBanner(month: ReflectionMonth(year: 2026, month: 10), onStart: {}, onHide: {})
                .todayNoticeCardRow()
        }
    }
    .scrollContentBackground(.hidden)
    .background(Color.kadoBackground.ignoresSafeArea())
}

#Preview("Dark") {
    List {
        Section {
            ReflectionCheckInBanner(month: ReflectionMonth(year: 2026, month: 10), onStart: {}, onHide: {})
                .todayNoticeCardRow()
        }
    }
    .scrollContentBackground(.hidden)
    .background(Color.kadoBackground.ignoresSafeArea())
    .preferredColorScheme(.dark)
}
