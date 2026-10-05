import SwiftUI
import KadoCore

/// One row per category: focus time, times done, habit consistency,
/// tasks left undone, and a thin bar for its share of the focus time.
struct InsightsCategoriesCard: View {
    let categories: [InsightsCategoryRow]

    var body: some View {
        let totalFocus = categories.reduce(0) { $0 + $1.focusSeconds }
        InsightsCard(kind: .categories) {
            VStack(alignment: .leading, spacing: 14) {
                ForEach(categories) { row in
                    InsightsCategoryRowView(
                        row: row,
                        focusShare: totalFocus > 0 ? row.focusSeconds / totalFocus : nil
                    )
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(categories.map(\.spokenSummary).joined(separator: ". ")))
        }
    }
}

private struct InsightsCategoryRowView: View {
    let row: InsightsCategoryRow
    /// Share of all the focus time in the card's categories, or `nil`
    /// when no category has any.
    let focusShare: Double?

    @Environment(\.habitTheme) private var habitTheme

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            InsightsMark(category: row.category)
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(row.category.localizedName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.kadoForeground)
                    Spacer(minLength: 8)
                    if let percent = InsightsFormat.percent(row.habitConsistency) {
                        Text(percent)
                            .font(.subheadline.weight(.semibold))
                            .monospacedDigit()
                            .foregroundStyle(Color.kadoForeground)
                    }
                }
                let details = row.details
                if !details.isEmpty {
                    Text(details.joined(separator: " · "))
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(Color.kadoForegroundSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let focusShare {
                    InsightsShareBar(fraction: focusShare, color: row.category.chartColor(in: habitTheme))
                        .padding(.top, 2)
                }
            }
        }
    }
}

private extension InsightsCategoryRow {
    /// "6h 20m focus", "32 done", "2 left undone": the parts that are
    /// not zero.
    var details: [String] {
        var parts: [String] = []
        if focusSeconds > 0 {
            parts.append(String(localized: "\(InsightsFormat.duration(focusSeconds)) focus", comment: "Insights Categories: session time in this category. The value is a duration."))
        }
        let done = habitTimesDone + tasksDone
        if done > 0 {
            parts.append(String(localized: "\(done) done", comment: "Insights Categories: habit days and tasks done in this category."))
        }
        if tasksUndone > 0 {
            parts.append(String(localized: "\(tasksUndone) left undone", comment: "Insights: tasks not done by the day they were planned for."))
        }
        return parts
    }

    /// "Study, 82% consistent, 6h 20m focus, 32 done".
    var spokenSummary: String {
        var parts = [category.localizedName]
        if let percent = InsightsFormat.percent(habitConsistency) {
            parts.append(String(localized: "\(percent) consistent", comment: "Insights: share of due habit-days done. The value is a percent."))
        }
        parts += details
        return parts.joined(separator: ", ")
    }
}

/// A thin bar filled to a share.
struct InsightsShareBar: View {
    let fraction: Double
    let color: Color

    @ScaledMetric(relativeTo: .caption) private var height: CGFloat = 4

    var body: some View {
        Capsule()
            .fill(Color.kadoHairline)
            .frame(height: height)
            .overlay(alignment: .leading) {
                GeometryReader { proxy in
                    Capsule()
                        .fill(color)
                        .frame(width: max(height, proxy.size.width * min(1, max(0, fraction))))
                }
            }
            .accessibilityHidden(true)
    }
}

#Preview("Categories") {
    ScrollView {
        InsightsCategoriesCard(categories: InsightsPreviewData.rich.categories)
            .padding()
    }
    .background(Color.kadoBackground)
}

#Preview("Dark") {
    ScrollView {
        VStack(spacing: 16) {
            InsightsCategoriesCard(categories: InsightsPreviewData.rich.categories)
            InsightsCategoriesCard(categories: InsightsPreviewData.sparse.categories)
        }
        .padding()
    }
    .background(Color.kadoBackground)
    .preferredColorScheme(.dark)
}
