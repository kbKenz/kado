import SwiftUI
import KadoCore

/// Tasks in the period: done, left undone, follow-through and on time,
/// how long tasks take, the categories most often left undone, and the
/// open tasks past their day.
struct InsightsTasksCard: View {
    let tasks: InsightsTasks
    /// Done / (done + left undone), from the Pulse.
    let followThrough: InsightsRate

    var body: some View {
        InsightsCard(kind: .tasks) {
            VStack(alignment: .leading, spacing: 14) {
                InsightsStatRow {
                    InsightsStat(value: InsightsFormat.count(tasks.done), label: "Completed")
                    InsightsStat(value: InsightsFormat.count(tasks.undone), label: "Left undone")
                }
                InsightsStatRow {
                    InsightsStat(value: InsightsFormat.percent(followThrough) ?? "—", label: "Follow-through")
                    InsightsStat(value: InsightsFormat.percent(tasks.onTime) ?? "—", label: "On time")
                }
                if let finishText {
                    Label {
                        Text(finishText)
                            .fixedSize(horizontal: false, vertical: true)
                    } icon: {
                        Image(systemName: "hourglass")
                    }
                    .font(.footnote)
                    .foregroundStyle(Color.kadoForegroundSecondary)
                }
                if !tasks.undoneByCategory.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(tasks.undoneByCategory) { row in
                            HStack(spacing: 10) {
                                InsightsMark(category: row.category)
                                Text(undoneText(row))
                                    .font(.subheadline)
                                    .monospacedDigit()
                                    .foregroundStyle(Color.kadoForeground)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
                if tasks.overdueOpen > 0 {
                    Label {
                        Text(overdueText)
                            .fixedSize(horizontal: false, vertical: true)
                    } icon: {
                        Image(systemName: "calendar.badge.clock")
                    }
                    .font(.footnote)
                    .foregroundStyle(Color.kadoForegroundSecondary)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(summary))
        }
    }

    /// "Finished in 2.4 days on average", or the same day.
    private var finishText: String? {
        guard let days = tasks.averageDaysToFinish else { return nil }
        let rounded = InsightsFormat.days(days)
        if days < 0.05 {
            return String(localized: "Finished the same day on average", comment: "Insights Tasks: tasks done in the period were finished the day they were created, on average.")
        }
        return String(localized: "Finished in \(rounded) days on average", comment: "Insights Tasks: mean days from creating a task to finishing it. The value is a number with one decimal.")
    }

    /// "Errands: 5 of 9 left undone".
    private func undoneText(_ row: InsightsCategoryUndone) -> String {
        String(localized: "\(row.category.localizedName): \(row.undone) of \(row.total) left undone", comment: "Insights Tasks: a category's tasks left undone out of its tasks done or left undone. The values are the category name and two counts.")
    }

    /// "4 open tasks are overdue".
    private var overdueText: String {
        String(localized: "\(tasks.overdueOpen) open tasks are overdue", comment: "Insights Tasks: open tasks whose planned or due day has passed.")
    }

    private var summary: String {
        var parts = [
            String(localized: "\(tasks.done) tasks done", comment: "Insights, VoiceOver: a count of tasks completed."),
            String(localized: "\(tasks.undone) left undone", comment: "Insights: tasks not done by the day they were planned for."),
        ]
        if let percent = InsightsFormat.percent(followThrough) {
            parts.append(String(localized: "Follow-through \(percent)", comment: "Insights Tasks, VoiceOver: share of planned tasks done. The value is a percent."))
        }
        if let percent = InsightsFormat.percent(tasks.onTime) {
            parts.append(String(localized: "On time \(percent)", comment: "Insights Tasks, VoiceOver: share of done tasks finished by their day. The value is a percent."))
        }
        if let finishText {
            parts.append(finishText)
        }
        parts += tasks.undoneByCategory.map(undoneText)
        if tasks.overdueOpen > 0 {
            parts.append(overdueText)
        }
        return parts.map { $0 + "." }.joined(separator: " ")
    }
}

#Preview("Tasks") {
    InsightsTasksCard(tasks: InsightsPreviewData.rich.tasks, followThrough: InsightsPreviewData.rich.pulse.followThrough)
        .padding()
        .background(Color.kadoBackground)
}

#Preview("Dark") {
    ScrollView {
        VStack(spacing: 16) {
            InsightsTasksCard(tasks: InsightsPreviewData.rich.tasks, followThrough: InsightsPreviewData.rich.pulse.followThrough)
            InsightsTasksCard(tasks: InsightsPreviewData.sparse.tasks, followThrough: InsightsPreviewData.sparse.pulse.followThrough)
        }
        .padding()
    }
    .background(Color.kadoBackground)
    .preferredColorScheme(.dark)
}
