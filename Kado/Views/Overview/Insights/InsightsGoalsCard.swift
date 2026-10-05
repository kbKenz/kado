import SwiftUI
import KadoCore

/// Every active goal: progress, linked tasks done, pace and days left.
/// A row opens the goal.
struct InsightsGoalsCard: View {
    let goals: [InsightsGoalRow]
    let actions: InsightsActions

    var body: some View {
        InsightsCard(kind: .goals) {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(goals) { goal in
                    InsightsGoalRowButton(goal: goal) {
                        actions.openGoal(goal.goalID)
                    }
                }
            }
        }
    }
}

/// One goal as a button, its own VoiceOver element.
private struct InsightsGoalRowButton: View {
    let goal: InsightsGoalRow
    let action: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                if dynamicTypeSize.isAccessibilitySize {
                    stackedHeader
                } else {
                    inlineHeader
                }
                if let progress = goal.progress {
                    HStack(spacing: 10) {
                        ProgressView(value: min(1, max(0, progress)))
                            .progressViewStyle(.linear)
                            .tint(Color.kadoAccent)
                        Text(InsightsFormat.percent(progress))
                            .font(.caption.weight(.semibold))
                            .monospacedDigit()
                            .foregroundStyle(Color.kadoForegroundSecondary)
                    }
                }
                if !details.isEmpty {
                    Text(details.joined(separator: " · "))
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(Color.kadoForegroundSecondary)
                        .multilineTextAlignment(.leading)
                }
            }
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(spoken))
        .accessibilityHint(Text("Opens the goal.", comment: "Insights Goals, VoiceOver hint on a goal row."))
        .accessibilityIdentifier(AccessibilityID.Insights.goalRow(goal.goalID))
    }

    /// Icon, name, pace and chevron on one line.
    private var inlineHeader: some View {
        HStack(spacing: 10) {
            InsightsMark(category: goal.category)
            name.lineLimit(2)
            Spacer(minLength: 8)
            if let pace = goal.pace {
                InsightsPaceChip(pace: pace)
            }
            chevron
        }
    }

    /// Accessibility sizes: the name and the pace get lines of their
    /// own, so neither is cut.
    private var stackedHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                InsightsMark(category: goal.category)
                Spacer(minLength: 8)
                chevron
            }
            name
            if let pace = goal.pace {
                InsightsPaceChip(pace: pace)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var name: some View {
        Text(goal.name)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Color.kadoForeground)
            .multilineTextAlignment(.leading)
    }

    private var chevron: some View {
        Image(systemName: "chevron.right")
            .font(.caption.weight(.semibold))
            .foregroundStyle(Color.kadoForegroundTertiary)
    }

    /// "6 of 14 tasks · 172 days left".
    private var details: [String] {
        var parts: [String] = []
        if goal.tasksTotal > 0 {
            parts.append(String(localized: "\(goal.tasksDone) of \(goal.tasksTotal) tasks", comment: "Insights Goals: linked tasks done out of all linked tasks."))
        }
        if let daysLeft = goal.daysLeft {
            if daysLeft == 0 {
                parts.append(String(localized: "Ends today", comment: "Insights Goals: the goal's target date is today."))
            } else {
                parts.append(String(localized: "\(daysLeft) days left", comment: "Insights Goals: days until the goal's target date."))
            }
        }
        return parts
    }

    private var spoken: String {
        var parts = [goal.name]
        if let progress = goal.progress {
            parts.append(String(localized: "Progress \(InsightsFormat.percent(progress))", comment: "Insights Goals, VoiceOver: how far the goal is. The value is a percent."))
        }
        if let pace = goal.pace {
            parts.append(pace.title)
        }
        parts += details
        return parts.joined(separator: ", ")
    }
}

/// "Ahead", "On track" or "Behind", in a capsule. Behind stays neutral.
private struct InsightsPaceChip: View {
    let pace: InsightsGoalPace

    var body: some View {
        Text(pace.title)
            .font(.caption.weight(.semibold))
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .foregroundStyle(pace == .behind ? Color.kadoForegroundSecondary : Color.kadoAccent)
            .background(
                Capsule().fill(pace == .behind ? Color.kadoHairline : Color.kadoAccentTint)
            )
            .fixedSize()
    }
}

private extension InsightsGoalPace {
    var title: String {
        switch self {
        case .ahead:
            String(localized: "Ahead", comment: "Insights Goals: progress is ahead of the time that has passed.")
        case .onTrack:
            String(localized: "On track", comment: "Insights Goals: progress keeps up with the time that has passed.")
        case .behind:
            String(localized: "Behind", comment: "Insights Goals: progress is behind the time that has passed.")
        }
    }
}

#Preview("Goals") {
    InsightsGoalsCard(goals: InsightsPreviewData.rich.goals, actions: .none)
        .padding()
        .background(Color.kadoBackground)
}

#Preview("Dark") {
    InsightsGoalsCard(goals: InsightsPreviewData.rich.goals + InsightsPreviewData.behindGoals, actions: .none)
        .padding()
        .background(Color.kadoBackground)
        .preferredColorScheme(.dark)
}

#Preview("XXXL") {
    ScrollView {
        InsightsGoalsCard(goals: InsightsPreviewData.rich.goals, actions: .none)
            .padding()
    }
    .background(Color.kadoBackground)
    .dynamicTypeSize(.accessibility3)
}
