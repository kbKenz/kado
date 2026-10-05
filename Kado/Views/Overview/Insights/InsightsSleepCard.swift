import Charts
import SwiftUI
import KadoCore

/// Sleep from Apple Health (average, bedtime consistency, nights of
/// 7 hours or more, usual bedtime and wake-up, a bar per night) and
/// the Sleep habits' consistency.
///
/// Without Health it offers to connect it; without a Sleep habit it
/// offers one.
struct InsightsSleepCard: View {
    let sleep: InsightsSleep
    /// The period's days, for the chart's span.
    let days: [Date]
    let actions: InsightsActions

    @Environment(\.calendar) private var calendar

    var body: some View {
        InsightsCard(kind: .sleep) {
            VStack(alignment: .leading, spacing: 16) {
                health
                if sleep.habits.isEmpty {
                    InsightsHealthPrompt(message: nil, showsConnect: false, template: .sleep, actions: actions)
                } else {
                    InsightsHabitConsistencyList(habits: sleep.habits)
                }
            }
        }
    }

    @ViewBuilder
    private var health: some View {
        if !sleep.isHealthConnected {
            InsightsHealthPrompt(
                message: "Connect Apple Health to see your nights.",
                showsConnect: true,
                template: nil,
                actions: actions
            )
        } else if let average = sleep.averageDuration, !sleep.nights.isEmpty {
            nights(average: average)
        } else {
            Text("No sleep data from Apple Health in this period.")
                .font(.subheadline)
                .foregroundStyle(Color.kadoForegroundSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func nights(average: TimeInterval) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(InsightsFormat.duration(average))
                    .font(.kado(.displayBold, size: 34))
                    .monospacedDigit()
                    .foregroundStyle(Color.kadoForeground)
                Text(averageCaption)
                    .font(.footnote)
                    .foregroundStyle(Color.kadoForegroundSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let previous = sleep.previousAverageDuration {
                    InsightsChangeLabel(InsightsFormat.durationChange(average, from: previous))
                }
            }
            InsightsNightsChart(nights: sleep.nights, days: days)
            // "14 of 21 nights" needs the width of a row to stay on one
            // line, so the two times get a row of their own.
            InsightsStat(value: nightsOverSeven, label: "7 h or more")
            InsightsStatRow {
                InsightsStat(value: time(sleep.medianBedtimeMinutes), label: "Bedtime")
                InsightsStat(value: time(sleep.medianWakeMinutes), label: "Wake-up")
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(summary(average: average)))
    }

    /// "Average night · 78% consistent".
    private var averageCaption: String {
        let label = String(localized: "Average night", comment: "Insights Sleep: caption under the average sleep duration.")
        guard let percent = InsightsFormat.percent(sleep.bedtimeConsistency) else { return label }
        let consistent = String(localized: "\(percent) consistent", comment: "Insights: share of due habit-days done. The value is a percent.")
        return "\(label) · \(consistent)"
    }

    /// "14 of 21 nights".
    private var nightsOverSeven: String {
        let rate = sleep.nightsOverSevenHours
        return String(localized: "\(rate.done) of \(rate.total) nights", comment: "Insights Sleep: nights of 7 hours or more out of all nights recorded.")
    }

    private func time(_ minutes: Int?) -> String {
        minutes.map { InsightsFormat.time(minutesAfterMidnight: $0, calendar: calendar) } ?? "—"
    }

    private func summary(average: TimeInterval) -> String {
        var parts = [String(localized: "Average sleep \(InsightsFormat.duration(average))", comment: "Insights Sleep, VoiceOver: average sleep per night. The value is a duration.")]
        if let previous = sleep.previousAverageDuration {
            parts.append(InsightsFormat.durationChange(average, from: previous).spokenText)
        }
        if let percent = InsightsFormat.percent(sleep.bedtimeConsistency) {
            parts.append(String(localized: "Bedtime \(percent) consistent", comment: "Insights Sleep, VoiceOver: share of nights that started near the usual bedtime. The value is a percent."))
        }
        parts.append(String(localized: "7 hours or more: \(nightsOverSeven)", comment: "Insights Sleep, VoiceOver: nights of 7 hours or more. The value reads like 14 of 21 nights."))
        if let bedtime = sleep.medianBedtimeMinutes, let wake = sleep.medianWakeMinutes {
            parts.append(String(localized: "Usual bedtime \(time(bedtime)), wake-up \(time(wake))", comment: "Insights Sleep, VoiceOver: median bedtime and wake time. The values are times of day."))
        }
        return parts.map { $0 + "." }.joined(separator: " ")
    }
}

/// A bar per night across the period, with a dashed line at 7 hours.
private struct InsightsNightsChart: View {
    let nights: [InsightsNight]
    let days: [Date]

    @Environment(\.calendar) private var calendar
    @Environment(\.habitTheme) private var habitTheme
    @ScaledMetric(relativeTo: .body) private var height: CGFloat = 120

    private static let sevenHours: Double = 7

    var body: some View {
        Chart {
            ForEach(nights) { night in
                BarMark(
                    x: .value("Night", night.day, unit: .day),
                    y: .value("Sleep", night.duration / 3600),
                    // A year of nights reads as one shape, not a barcode.
                    width: days.count > 31 ? .ratio(1) : .automatic
                )
                .foregroundStyle(ItemCategory.sleep.chartColor(in: habitTheme))
            }
            RuleMark(y: .value("7 hours", Self.sevenHours))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                .foregroundStyle(Color.kadoForegroundSecondary)
        }
        .chartXScale(domain: xDomain)
        .chartYScale(domain: 0...yTop)
        // The 7-hour line's label sits beside the plot, clear of the bars.
        .chartYAxis {
            AxisMarks(position: .trailing, values: [Self.sevenHours]) { _ in
                AxisValueLabel {
                    Text(InsightsFormat.duration(Self.sevenHours * 3600))
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: axisDates) { _ in
                // Large text: drop the labels that would overlap.
                AxisValueLabel(format: axisFormat, centered: true, collisionResolution: .greedy)
            }
        }
        // Grows with the text, up to a point.
        .frame(height: min(height, 200))
    }

    private var yTop: Double {
        let longest = nights.map(\.duration).max() ?? 0
        return max(9, (longest / 3600).rounded(.up))
    }

    private var xDomain: ClosedRange<Date> {
        guard let first = days.first, let last = days.last else {
            let now = Date.now
            return now...now
        }
        let end = calendar.date(byAdding: .day, value: 1, to: last) ?? last
        return first...end
    }

    /// Every day for a week, every seventh for a month, the first of
    /// each month for a year.
    private var axisDates: [Date] {
        switch days.count {
        case ...7:
            return days
        case ...31:
            return days.enumerated().filter { $0.offset % 7 == 0 }.map(\.element)
        default:
            return days.filter { calendar.component(.day, from: $0) == 1 }
        }
    }

    private var axisFormat: Date.FormatStyle {
        switch days.count {
        case ...7: .dateTime.weekday(.narrow)
        case ...31: .dateTime.day().month(.abbreviated)
        default: .dateTime.month(.narrow)
        }
    }
}

#Preview("Health") {
    ScrollView {
        InsightsSleepCard(sleep: InsightsPreviewData.rich.sleep, days: InsightsPreviewData.rich.days, actions: .none)
            .padding()
    }
    .background(Color.kadoBackground)
}

#Preview("Dark") {
    ScrollView {
        VStack(spacing: 16) {
            InsightsSleepCard(sleep: InsightsPreviewData.richQuarter.sleep, days: InsightsPreviewData.richQuarter.days, actions: .none)
            InsightsSleepCard(sleep: InsightsPreviewData.sparse.sleep, days: InsightsPreviewData.sparse.days, actions: .none)
        }
        .padding()
    }
    .background(Color.kadoBackground)
    .preferredColorScheme(.dark)
}
