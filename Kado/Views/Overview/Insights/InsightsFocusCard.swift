import Charts
import SwiftUI
import KadoCore

/// Tracked session time: the total and its change, bars per day (per
/// month for the year) stacked by category, then sessions, average,
/// longest and time against plan.
///
/// Before the first session ever, it explains how to start one.
struct InsightsFocusCard: View {
    let focus: InsightsFocus
    let period: InsightsPeriod

    var body: some View {
        InsightsCard(kind: .focus) {
            if focus.hasEverTracked {
                tracked
            } else {
                Text("Start a session from Now to see your focus time.")
                    .font(.subheadline)
                    .foregroundStyle(Color.kadoForeground)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var tracked: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(InsightsFormat.duration(focus.total))
                    .font(.kado(.displayBold, size: 34))
                    .monospacedDigit()
                    .foregroundStyle(Color.kadoForeground)
                InsightsChangeLabel(InsightsFormat.durationChange(focus.total, from: focus.previousTotal))
            }
            if focus.total > 0 {
                InsightsFocusChart(buckets: focus.buckets, period: period)
            } else {
                Text("No sessions in this period.")
                    .font(.subheadline)
                    .foregroundStyle(Color.kadoForegroundSecondary)
            }
            InsightsStatRow {
                InsightsStat(value: InsightsFormat.count(focus.sessionCount), label: "Sessions")
                InsightsStat(value: focus.averageSession.map { InsightsFormat.duration($0) } ?? "—", label: "Average")
                InsightsStat(value: focus.longestSession.map { InsightsFormat.duration($0) } ?? "—", label: "Longest")
            }
            if let planRatio = focus.planRatio {
                Label {
                    Text(planText(planRatio))
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "clock.arrow.circlepath")
                }
                .font(.footnote)
                .foregroundStyle(Color.kadoForegroundSecondary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(summary))
    }

    private func planText(_ ratio: Double) -> String {
        switch InsightsFormat.planDrift(ratio) {
        case .onPlan:
            String(localized: "On plan", comment: "Insights Focus: sessions lasted about as long as their planned blocks.")
        case .longer(let share):
            String(localized: "Sessions ran \(InsightsFormat.percent(share)) longer than planned", comment: "Insights Focus: sessions lasted longer than their planned blocks. The value is a percent.")
        case .shorter(let share):
            String(localized: "Sessions ran \(InsightsFormat.percent(share)) shorter than planned", comment: "Insights Focus: sessions were shorter than their planned blocks. The value is a percent.")
        }
    }

    private var summary: String {
        var parts = [
            String(localized: "Focus time \(InsightsFormat.duration(focus.total))", comment: "Insights Focus, VoiceOver: total session time in the period. The value is a duration."),
            InsightsFormat.durationChange(focus.total, from: focus.previousTotal).spokenText,
            String(localized: "\(focus.sessionCount) sessions", comment: "Insights Focus, VoiceOver: how many sessions ran in the period."),
        ]
        if let average = focus.averageSession {
            parts.append(String(localized: "Average \(InsightsFormat.duration(average))", comment: "Insights, VoiceOver: an average length. The value is a duration."))
        }
        if let longest = focus.longestSession {
            parts.append(String(localized: "Longest \(InsightsFormat.duration(longest))", comment: "Insights Focus, VoiceOver: the longest session. The value is a duration."))
        }
        if let planRatio = focus.planRatio {
            parts.append(planText(planRatio))
        }
        return parts.map { $0 + "." }.joined(separator: " ")
    }
}

/// The bars: one per bucket, stacked by category in category order,
/// each in its category's colour.
private struct InsightsFocusChart: View {
    let buckets: [InsightsFocusBucket]
    let period: InsightsPeriod

    @Environment(\.habitTheme) private var habitTheme
    @Environment(\.calendar) private var calendar
    @ScaledMetric(relativeTo: .body) private var height: CGFloat = 150

    private struct Segment: Identifiable {
        let start: Date
        let category: ItemCategory
        let seconds: TimeInterval
        var id: String { "\(start.timeIntervalSinceReferenceDate)-\(category.rawValue)" }
    }

    var body: some View {
        let categories = presentCategories
        Chart(segments) { segment in
            BarMark(
                x: .value("Day", segment.start, unit: unit),
                y: .value("Time", segment.seconds / 3600)
            )
            .foregroundStyle(by: .value("Category", segment.category.localizedName))
        }
        .chartForegroundStyleScale(
            domain: categories.map(\.localizedName),
            range: colors(for: categories)
        )
        .chartXScale(domain: xDomain)
        .chartXAxis {
            AxisMarks(values: axisDates) { _ in
                // Large text: drop the labels that would overlap.
                AxisValueLabel(format: axisFormat, centered: true, collisionResolution: .greedy)
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                    .foregroundStyle(Color.kadoHairline)
                AxisValueLabel {
                    if let hours = value.as(Double.self), hours > 0 {
                        Text(InsightsFormat.duration(hours * 3600))
                    }
                }
            }
        }
        .chartLegend(position: .bottom, alignment: .leading, spacing: 10)
        // Grows with the text, up to a point.
        .frame(height: min(height, 220))
    }

    /// Each category's colour. Some categories share a palette slot
    /// (Study and Creative are both purple); a second one in the same
    /// chart takes the slot's lighter tint, so the stacks stay apart.
    private func colors(for categories: [ItemCategory]) -> [Color] {
        var used: Set<HabitColor> = []
        return categories.map { category in
            guard let slot = category.color else { return category.chartColor(in: habitTheme) }
            if used.insert(slot).inserted {
                return slot.color(in: habitTheme)
            }
            return slot.tint(.tilePartial, in: habitTheme)
        }
    }

    /// Quarter buckets are weeks; the others are days.
    private var unit: Calendar.Component {
        period == .quarter ? .weekOfYear : .day
    }

    private var segments: [Segment] {
        buckets.flatMap { bucket in
            ItemCategory.allCases.compactMap { category in
                guard let seconds = bucket.byCategory[category], seconds > 0 else { return nil }
                return Segment(start: bucket.start, category: category, seconds: seconds)
            }
        }
    }

    /// Categories with any time, in category order, so each keeps the
    /// same place in every stack and in the legend.
    private var presentCategories: [ItemCategory] {
        let present = Set(buckets.flatMap { bucket in bucket.byCategory.filter { $0.value > 0 }.keys })
        return ItemCategory.allCases.filter(present.contains)
    }

    /// From the first bucket to the end of the last, so empty days keep
    /// their place.
    private var xDomain: ClosedRange<Date> {
        guard let first = buckets.first?.start, let last = buckets.last?.start else {
            let now = Date.now
            return now...now
        }
        let end = calendar.date(byAdding: unit, value: 1, to: last) ?? last
        return first...end
    }

    /// A label on every bucket for the week, on every seventh day for
    /// the month and on every fourth week for the quarter.
    private var axisDates: [Date] {
        let starts = buckets.map(\.start)
        switch period {
        case .week: return starts
        case .month: return starts.enumerated().filter { $0.offset % 7 == 0 }.map(\.element)
        case .quarter: return starts.enumerated().filter { $0.offset % 4 == 0 }.map(\.element)
        }
    }

    private var axisFormat: Date.FormatStyle {
        switch period {
        case .week: .dateTime.weekday(.narrow)
        case .month: .dateTime.day().month(.abbreviated)
        case .quarter: .dateTime.day().month(.abbreviated)
        }
    }
}

#Preview("Month") {
    InsightsFocusCard(focus: InsightsPreviewData.rich.focus, period: .month)
        .padding()
        .background(Color.kadoBackground)
}

#Preview("Dark") {
    ScrollView {
        VStack(spacing: 16) {
            InsightsFocusCard(focus: InsightsPreviewData.richQuarter.focus, period: .quarter)
            InsightsFocusCard(focus: InsightsPreviewData.sparse.focus, period: .month)
        }
        .padding()
    }
    .background(Color.kadoBackground)
    .preferredColorScheme(.dark)
}

#Preview("Week") {
    InsightsFocusCard(focus: InsightsPreviewData.richWeek.focus, period: .week)
        .padding()
        .background(Color.kadoBackground)
}
