import SwiftUI
import KadoCore

/// The period as a heat map of habit days, one column per week, with
/// the perfect days and the longest perfect run beside it.
///
/// A cell's shade is the share of the day's due habits that were done.
/// A day with nothing due keeps an outline, so colour is never the only
/// way to tell it from a day with nothing done.
struct InsightsActivityCard: View {
    let activity: InsightsActivity
    let period: InsightsPeriod

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        InsightsCard(kind: .activity) {
            VStack(alignment: .leading, spacing: 14) {
                if period == .year || dynamicTypeSize.isAccessibilitySize {
                    InsightsHeatMap(days: activity.days, scrolls: period == .year)
                    InsightsStatRow { stats }
                } else {
                    HStack(alignment: .top, spacing: 24) {
                        InsightsHeatMap(days: activity.days, scrolls: false)
                        VStack(alignment: .leading, spacing: 12) { stats }
                    }
                }
                InsightsHeatMapLegend()
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(summary))
        }
    }

    @ViewBuilder
    private var stats: some View {
        InsightsStat(value: InsightsFormat.count(activity.perfectDays), label: "Perfect days")
        InsightsStat(
            value: String(localized: "\(activity.longestPerfectRun) days", comment: "Insights Activity: the longest run of perfect days, in days."),
            label: "Best run"
        )
    }

    private var summary: String {
        let perfect = String(localized: "\(activity.perfectDays) perfect days", comment: "Insights: days on which every due habit was done.")
        let run = String(localized: "Best run: \(activity.longestPerfectRun) days", comment: "Insights Activity, VoiceOver: the longest run of perfect days in the period.")
        return "\(perfect). \(run)."
    }
}

/// The heat map itself: a column of weekday letters, then one column
/// per week, each from the calendar's first weekday down.
private struct InsightsHeatMap: View {
    let days: [InsightsActivityDay]
    /// The year: scroll sideways, opened on the latest weeks, with the
    /// month names on top.
    let scrolls: Bool

    @Environment(\.calendar) private var calendar
    @ScaledMetric(relativeTo: .caption2) private var cell: CGFloat = 14
    @ScaledMetric(relativeTo: .caption2) private var gap: CGFloat = 3
    @ScaledMetric(relativeTo: .caption2) private var monthHeight: CGFloat = 14

    var body: some View {
        let columns = Self.columns(of: days, calendar: calendar)
        HStack(alignment: .top, spacing: gap) {
            weekdayLabels
            if scrolls {
                ScrollView(.horizontal, showsIndicators: false) {
                    grid(columns)
                }
                .defaultScrollAnchor(.trailing)
            } else {
                grid(columns)
            }
        }
    }

    private var weekdayLabels: some View {
        VStack(alignment: .leading, spacing: gap) {
            if scrolls {
                Color.clear.frame(width: 1, height: monthHeight)
            }
            ForEach(Weekday.week(startingOn: calendar.firstWeekday), id: \.self) { weekday in
                Text(weekday.localizedShort)
                    .font(.caption2)
                    .foregroundStyle(Color.kadoForegroundSecondary)
                    .frame(height: cell)
            }
        }
    }

    private func grid(_ columns: [Column]) -> some View {
        HStack(alignment: .top, spacing: gap) {
            ForEach(columns) { column in
                VStack(spacing: gap) {
                    if scrolls {
                        monthLabel(column)
                    }
                    ForEach(0..<7, id: \.self) { row in
                        cellView(column.cells[row])
                    }
                }
            }
        }
    }

    /// The month's short name over the week its first day falls in.
    private func monthLabel(_ column: Column) -> some View {
        let first = column.cells.compactMap { $0 }.first { calendar.component(.day, from: $0.date) == 1 }
        return ZStack(alignment: .leading) {
            Color.clear.frame(width: cell, height: monthHeight)
            if let first {
                Text(first.date, format: .dateTime.month(.abbreviated))
                    .font(.caption2)
                    .foregroundStyle(Color.kadoForegroundSecondary)
                    .fixedSize()
            }
        }
        .frame(width: cell, height: monthHeight, alignment: .leading)
    }

    @ViewBuilder
    private func cellView(_ day: InsightsActivityDay?) -> some View {
        let shape = RoundedRectangle(cornerRadius: 3, style: .continuous)
        if let day, day.isInPeriod {
            if let fraction = day.habitFraction {
                shape
                    .fill(Self.fill(for: fraction))
                    .frame(width: cell, height: cell)
            } else {
                shape
                    .strokeBorder(Color.kadoDivider, lineWidth: 1)
                    .frame(width: cell, height: cell)
            }
        } else {
            Color.clear.frame(width: cell, height: cell)
        }
    }

    /// The accent, stronger as more of the day's habits were done; the
    /// hairline for a day with nothing done.
    static func fill(for fraction: Double) -> Color {
        guard fraction > 0 else { return Color.kadoHairline }
        return Color.kadoAccent.opacity(0.25 + 0.75 * min(1, fraction))
    }

    /// One week of cells, by row. A slot is `nil` before the first day
    /// or after today.
    struct Column: Identifiable {
        let id: Int
        var cells: [InsightsActivityDay?]
    }

    /// Lays the days out in week columns. A new column starts whenever
    /// the row would not move down, so a report padded to another
    /// first weekday still lands each day on its own weekday's row.
    static func columns(of days: [InsightsActivityDay], calendar: Calendar) -> [Column] {
        var result: [Column] = []
        var current = [InsightsActivityDay?](repeating: nil, count: 7)
        var lastRow = -1
        for day in days {
            let weekday = Weekday(rawValue: calendar.component(.weekday, from: day.date)) ?? .sunday
            let row = weekday.column(inWeekStartingOn: calendar.firstWeekday)
            if row <= lastRow {
                result.append(Column(id: result.count, cells: current))
                current = [InsightsActivityDay?](repeating: nil, count: 7)
            }
            current[row] = day
            lastRow = row
        }
        if lastRow >= 0 {
            result.append(Column(id: result.count, cells: current))
        }
        return result
    }
}

/// "Less ▢▢▢▢ More · ▢ Nothing due".
private struct InsightsHeatMapLegend: View {
    @ScaledMetric(relativeTo: .caption2) private var cell: CGFloat = 10

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                scale
                nothingDue
            }
            VStack(alignment: .leading, spacing: 6) {
                scale
                nothingDue
            }
        }
        .font(.caption2)
        .foregroundStyle(Color.kadoForegroundSecondary)
    }

    private var scale: some View {
        HStack(spacing: 4) {
            Text("Less")
            ForEach([0.0, 0.34, 0.67, 1.0], id: \.self) { fraction in
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(InsightsHeatMap.fill(for: fraction))
                    .frame(width: cell, height: cell)
            }
            Text("More")
        }
        .fixedSize()
    }

    private var nothingDue: some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .strokeBorder(Color.kadoDivider, lineWidth: 1)
                .frame(width: cell, height: cell)
            Text("Nothing due")
        }
        .fixedSize()
    }
}

#Preview("Month") {
    InsightsActivityCard(activity: InsightsPreviewData.rich.activity, period: .month)
        .padding()
        .background(Color.kadoBackground)
}

#Preview("Dark") {
    ScrollView {
        VStack(spacing: 16) {
            InsightsActivityCard(activity: InsightsPreviewData.richYear.activity, period: .year)
            InsightsActivityCard(activity: InsightsPreviewData.sparse.activity, period: .month)
        }
        .padding()
    }
    .background(Color.kadoBackground)
    .preferredColorScheme(.dark)
}

#Preview("Week") {
    InsightsActivityCard(activity: InsightsPreviewData.richWeek.activity, period: .week)
        .padding()
        .background(Color.kadoBackground)
}
