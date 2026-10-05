import Charts
import SwiftUI
import KadoCore

/// When things happen: habit consistency per weekday, with the best
/// day marked, and focus time by part of the day.
struct InsightsRhythmCard: View {
    let rhythm: InsightsRhythm

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .caption) private var swatch: CGFloat = 8

    var body: some View {
        InsightsCard(kind: .rhythm) {
            VStack(alignment: .leading, spacing: 18) {
                if hasWeekdays {
                    weekdays
                }
                if focusTotal > 0 {
                    partsOfDay
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(summary))
        }
    }

    private var hasWeekdays: Bool {
        rhythm.weekdays.contains { $0.rate.total > 0 }
    }

    private var focusTotal: TimeInterval {
        rhythm.focusByPartOfDay.reduce(0) { $0 + $1.seconds }
    }

    // MARK: - Weekdays

    private var weekdays: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Habits by weekday")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.kadoForegroundSecondary)
            InsightsWeekdayChart(weekdays: rhythm.weekdays, best: rhythm.bestWeekday)
            if let best = rhythm.bestWeekday {
                Label {
                    Text(String(localized: "Best day: \(best.localizedFull)", comment: "Insights Rhythm: the weekday with the best habit consistency. The value is a weekday name."))
                } icon: {
                    Image(systemName: "star.fill")
                }
                .font(.footnote.weight(.medium))
                .foregroundStyle(Color.kadoAccent)
            }
        }
    }

    // MARK: - Parts of the day

    private var partsOfDay: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Focus by time of day")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.kadoForegroundSecondary)
            InsightsPartOfDayBar(parts: rhythm.focusByPartOfDay, total: focusTotal)
            LazyVGrid(columns: legendColumns, alignment: .leading, spacing: 6) {
                ForEach(rhythm.focusByPartOfDay) { part in
                    HStack(spacing: 6) {
                        Circle()
                            .fill(part.part.swatch)
                            .frame(width: swatch, height: swatch)
                        Text(part.part.localizedName)
                            .foregroundStyle(Color.kadoForeground)
                        Text(InsightsFormat.percent(part.seconds / focusTotal))
                            .monospacedDigit()
                            .foregroundStyle(Color.kadoForegroundSecondary)
                    }
                    .font(.caption)
                }
            }
        }
    }

    /// Two columns, or one at accessibility sizes so no name breaks.
    private var legendColumns: [GridItem] {
        let count = dynamicTypeSize.isAccessibilitySize ? 1 : 2
        return Array(repeating: GridItem(.flexible(), alignment: .leading), count: count)
    }

    private var summary: String {
        var parts: [String] = []
        if let best = rhythm.bestWeekday {
            parts.append(String(localized: "Best day: \(best.localizedFull)", comment: "Insights Rhythm: the weekday with the best habit consistency. The value is a weekday name."))
        } else if hasWeekdays {
            parts += rhythm.weekdays.compactMap { day in
                InsightsFormat.percent(day.rate).map { "\(day.weekday.localizedFull) \($0)" }
            }
        }
        if focusTotal > 0 {
            parts += rhythm.focusByPartOfDay.map { part in
                "\(part.part.localizedName) \(InsightsFormat.percent(part.seconds / focusTotal))"
            }
        }
        return parts.joined(separator: ", ")
    }
}

/// A bar per weekday, from the calendar's first weekday: the best day
/// in the accent, the others in a neutral tone.
private struct InsightsWeekdayChart: View {
    let weekdays: [InsightsWeekdayRate]
    let best: Weekday?

    @ScaledMetric(relativeTo: .body) private var height: CGFloat = 96

    var body: some View {
        Chart(weekdays) { day in
            BarMark(
                // The medium name keeps each weekday its own bar: the
                // one-letter names repeat (T, S).
                x: .value("Weekday", day.weekday.localizedMedium),
                y: .value("Consistency", day.rate.fraction ?? 0)
            )
            .foregroundStyle(day.weekday == best ? Color.kadoAccent : Color.kadoDivider)
            .cornerRadius(3, style: .continuous)
        }
        .chartYScale(domain: 0...1)
        .chartYAxis(.hidden)
        .chartXAxis {
            AxisMarks { value in
                AxisValueLabel {
                    if let name = value.as(String.self) {
                        Text(shortName(for: name))
                    }
                }
            }
        }
        // Grows with the text, up to a point.
        .frame(height: min(height, 160))
    }

    /// The one-letter name for an axis label.
    private func shortName(for medium: String) -> String {
        weekdays.first { $0.weekday.localizedMedium == medium }?.weekday.localizedShort ?? medium
    }
}

/// Focus time as one bar cut into the four parts of the day.
private struct InsightsPartOfDayBar: View {
    let parts: [InsightsPartOfDayFocus]
    let total: TimeInterval

    @ScaledMetric(relativeTo: .caption) private var height: CGFloat = 12

    var body: some View {
        GeometryReader { proxy in
            HStack(spacing: 2) {
                ForEach(parts.filter { $0.seconds > 0 }) { part in
                    Rectangle()
                        .fill(part.part.swatch)
                        .frame(width: max(2, (proxy.size.width - spacing) * part.seconds / total))
                }
            }
        }
        .frame(height: height)
        .clipShape(Capsule())
        .accessibilityHidden(true)
    }

    /// The gaps between the visible segments.
    private var spacing: CGFloat {
        CGFloat(max(0, parts.filter { $0.seconds > 0 }.count - 1)) * 2
    }
}

private extension InsightsPartOfDay {
    /// Four steps of the sage scale, darkest for the morning.
    var swatch: Color {
        switch self {
        case .morning: Color.kadoAccent
        case .afternoon: Color.kadoSage500
        case .evening: Color.kadoSage300
        case .night: Color.kadoForegroundTertiary
        }
    }
}

#Preview("Rhythm") {
    InsightsRhythmCard(rhythm: InsightsPreviewData.rich.rhythm)
        .padding()
        .background(Color.kadoBackground)
}

#Preview("Dark") {
    VStack(spacing: 16) {
        InsightsRhythmCard(rhythm: InsightsPreviewData.rich.rhythm)
        InsightsRhythmCard(rhythm: InsightsPreviewData.sparse.rhythm)
    }
    .padding()
    .background(Color.kadoBackground)
    .preferredColorScheme(.dark)
}
