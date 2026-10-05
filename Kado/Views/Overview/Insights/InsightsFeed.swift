import SwiftUI
import KadoCore

/// The Insights feed: the period picker, then one card per section of
/// the report. Renders a report and never computes a number.
///
/// A card with nothing to say is left out, except Focus, Sleep and
/// Movement: those explain how to get data instead
/// (`InsightsCardKind.visible(in:)`).
struct InsightsFeed: View {
    let report: InsightsReport
    @Binding var period: InsightsPeriod
    let actions: InsightsActions

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                InsightsPeriodRow(period: $period)
                if report.isEmpty {
                    emptyState
                } else {
                    ForEach(InsightsCardKind.visible(in: report)) { kind in
                        card(kind)
                    }
                }
            }
            .padding(.vertical, 12)
            .frame(maxWidth: 640)
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity)
        }
        .background(Color.kadoBackground.ignoresSafeArea())
    }

    @ViewBuilder
    private func card(_ kind: InsightsCardKind) -> some View {
        switch kind {
        case .pulse:
            InsightsPulseCard(pulse: report.pulse)
        case .highlights:
            InsightsHighlightsCard(highlights: report.highlights)
        case .activity:
            InsightsActivityCard(activity: report.activity, period: report.period)
        case .focus:
            InsightsFocusCard(focus: report.focus, period: report.period)
        case .categories:
            InsightsCategoriesCard(categories: report.categories)
        case .sleep:
            InsightsSleepCard(sleep: report.sleep, days: report.days, actions: actions)
        case .movement:
            InsightsMovementCard(movement: report.movement, actions: actions)
        case .habits:
            InsightsHabitsCard(habits: report.habits, actions: actions)
        case .tasks:
            InsightsTasksCard(tasks: report.tasks, followThrough: report.pulse.followThrough)
        case .goals:
            InsightsGoalsCard(goals: report.goals, actions: actions)
        case .rhythm:
            InsightsRhythmCard(rhythm: report.rhythm)
        case .allTime:
            InsightsAllTimeCard(allTime: report.allTime)
        }
    }

    /// First run: nothing exists yet, so there is nothing to summarize.
    private var emptyState: some View {
        ContentUnavailableView {
            Label("Your insights will appear here", systemImage: "chart.bar.xaxis")
        } description: {
            Text("Track a habit, finish a task or start a session from Now.")
        }
        .padding(.top, 24)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(AccessibilityID.Insights.empty)
    }
}

/// The Week / Month / Year picker and the span it covers. Side by side
/// when they fit, stacked otherwise (narrow screens, large text).
private struct InsightsPeriodRow: View {
    @Binding var period: InsightsPeriod

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                picker.fixedSize()
                Spacer(minLength: 0)
                caption
            }
            VStack(alignment: .leading, spacing: 6) {
                picker
                caption
            }
        }
    }

    private var picker: some View {
        Picker("Period", selection: $period) {
            Text("Week").tag(InsightsPeriod.week)
            Text("Month").tag(InsightsPeriod.month)
            Text("Year").tag(InsightsPeriod.year)
        }
        .pickerStyle(.segmented)
        .accessibilityIdentifier(AccessibilityID.Insights.periodPicker)
    }

    private var caption: some View {
        Text(captionText)
            .font(.footnote)
            .foregroundStyle(Color.kadoForegroundSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var captionText: LocalizedStringKey {
        switch period {
        case .week: "Last 7 days"
        case .month: "Last 30 days"
        case .year: "Last 12 months"
        }
    }
}

#Preview("Rich") {
    @Previewable @State var period = InsightsPeriod.month
    InsightsFeed(report: InsightsPreviewData.rich(for: period), period: $period, actions: .none)
        .kadoTheme()
}

#Preview("Dark") {
    @Previewable @State var period = InsightsPeriod.year
    InsightsFeed(report: InsightsPreviewData.rich(for: period), period: $period, actions: .none)
        .kadoTheme()
        .preferredColorScheme(.dark)
}

#Preview("Sparse") {
    @Previewable @State var period = InsightsPeriod.month
    InsightsFeed(report: InsightsPreviewData.sparse, period: $period, actions: .none)
        .kadoTheme()
}

#Preview("Empty") {
    @Previewable @State var period = InsightsPeriod.month
    InsightsFeed(report: InsightsPreviewData.empty, period: $period, actions: .none)
        .kadoTheme()
}

#Preview("XXXL") {
    @Previewable @State var period = InsightsPeriod.month
    InsightsFeed(report: InsightsPreviewData.rich(for: period), period: $period, actions: .none)
        .kadoTheme()
        .dynamicTypeSize(.accessibility3)
}
