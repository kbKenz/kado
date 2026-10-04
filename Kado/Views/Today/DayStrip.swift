import SwiftUI
import KadoCore

/// The scrolling row of days at the top of Today, like the date strip in
/// sleep-score apps. Lazy, so a long history costs only what's on screen.
struct DayStrip: View {
    let days: [Date]
    @Binding var selection: Date
    let today: Date
    let progress: (Date) -> DayProgress

    @Environment(\.calendar) private var calendar
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 4) {
                    ForEach(days, id: \.self) { day in
                        DayStripCell(
                            day: day,
                            isSelected: calendar.isDate(day, inSameDayAs: selection),
                            isToday: calendar.isDate(day, inSameDayAs: today),
                            progress: progress(day),
                            onSelect: { selection = day }
                        )
                        .id(day)
                    }
                }
                .scrollTargetLayout()
                .padding(.horizontal, 16)
            }
            .scrollTargetBehavior(.viewAligned)
            .onAppear { proxy.scrollTo(selection, anchor: .center) }
            .onChange(of: selection) { _, newValue in
                withAnimation(reduceMotion ? nil : .snappy) {
                    proxy.scrollTo(newValue, anchor: .center)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

private struct DayStripPreview: View {
    @State private var selection = Calendar.current.startOfDay(for: .now)
    var body: some View {
        let cal = Calendar.current
        let days = DayStripRange.days(from: cal.date(byAdding: .day, value: -30, to: .now), today: .now, calendar: cal)
        DayStrip(days: days, selection: $selection, today: cal.startOfDay(for: .now)) { day in
            day < selection ? DayProgress(completed: 2, total: 3) : .empty
        }
    }
}

#Preview { DayStripPreview() }
#Preview("Dark") { DayStripPreview().preferredColorScheme(.dark) }
