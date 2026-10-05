import SwiftUI
import KadoCore

/// Every active habit: times done, total amount, consistency and
/// current streak. A row opens the habit.
struct InsightsHabitsCard: View {
    let habits: [InsightsHabitRow]
    let actions: InsightsActions

    var body: some View {
        InsightsCard(kind: .habits) {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(habits) { habit in
                    InsightsHabitRowButton(habit: habit) {
                        actions.openHabit(habit.habitID)
                    }
                }
            }
        }
    }
}

/// One habit as a button. Its own VoiceOver element, so the card keeps
/// one element per habit.
private struct InsightsHabitRowButton: View {
    let habit: InsightsHabitRow
    let action: () -> Void

    @Environment(\.habitTheme) private var habitTheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Button(action: action) {
            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    stacked
                } else {
                    inline
                }
            }
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(spoken))
        .accessibilityHint(Text("Opens the habit.", comment: "Insights Habits, VoiceOver hint on a habit row."))
        .accessibilityIdentifier(AccessibilityID.Insights.habitRow(habit.habitID))
    }

    /// Name and figures on the left, consistency and streak on the right.
    private var inline: some View {
        HStack(spacing: 12) {
            InsightsMark(systemImage: habit.icon, color: habit.color)
            VStack(alignment: .leading, spacing: 2) {
                name.lineLimit(2)
                detailText
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                percent
                streak
            }
            chevron
        }
    }

    /// Accessibility sizes: one item per line, so the name keeps the
    /// whole width.
    private var stacked: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                InsightsMark(systemImage: habit.icon, color: habit.color)
                Spacer(minLength: 8)
                chevron
            }
            name
            detailText
            HStack(spacing: 12) {
                percent
                streak
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var name: some View {
        Text(habit.name)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Color.kadoForeground)
            .multilineTextAlignment(.leading)
    }

    private var detailText: some View {
        Text(detail)
            .font(.caption)
            .monospacedDigit()
            .foregroundStyle(Color.kadoForegroundSecondary)
            .multilineTextAlignment(.leading)
    }

    private var percent: some View {
        Text(InsightsFormat.percent(habit.rate) ?? "—")
            .font(.subheadline.weight(.semibold))
            .monospacedDigit()
            .foregroundStyle(Color.kadoForeground)
    }

    /// A flame and the current streak, from two days on.
    @ViewBuilder
    private var streak: some View {
        if habit.currentStreak >= 2 {
            HStack(spacing: 2) {
                Image(systemName: "flame.fill")
                Text(InsightsFormat.count(habit.currentStreak))
            }
            .font(.caption.weight(.semibold))
            .monospacedDigit()
            .foregroundStyle(HabitColor.orange.color(in: habitTheme))
        }
    }

    private var chevron: some View {
        Image(systemName: "chevron.right")
            .font(.caption.weight(.semibold))
            .foregroundStyle(Color.kadoForegroundTertiary)
    }

    /// "42 times · 18h" for a timer, "28 times · 214 total" for a
    /// counter, "4 slips" for a negative habit, "27 times" otherwise.
    private var detail: String {
        let times = String(localized: "\(habit.timesDone) times", comment: "Insights: how many times something was done in the period.")
        switch habit.type {
        case .timer:
            return "\(times) · \(InsightsFormat.duration(habit.amount))"
        case .counter:
            let total = String(localized: "\(InsightsFormat.amount(habit.amount)) total", comment: "Insights Habits: a counter habit's summed count in the period. The value is a number.")
            return "\(times) · \(total)"
        case .negative:
            return String(localized: "\(habit.timesDone) slips", comment: "Insights Habits: days a negative habit was slipped in the period.")
        case .binary:
            return times
        }
    }

    /// "Read. 42 times · 18h. 82% consistent. 12-day streak."
    private var spoken: String {
        var parts = [habit.name, detail]
        if let percent = InsightsFormat.percent(habit.rate) {
            parts.append(String(localized: "\(percent) consistent", comment: "Insights: share of due habit-days done. The value is a percent."))
        }
        if habit.currentStreak >= 2 {
            parts.append(String(localized: "\(habit.currentStreak)-day streak", comment: "Insights Habits, VoiceOver: the habit's current streak in days."))
        }
        return parts.joined(separator: ", ")
    }
}

#Preview("Habits") {
    ScrollView {
        InsightsHabitsCard(habits: InsightsPreviewData.rich.habits, actions: .none)
            .padding()
    }
    .background(Color.kadoBackground)
}

#Preview("Dark") {
    ScrollView {
        VStack(spacing: 16) {
            InsightsHabitsCard(habits: InsightsPreviewData.rich.habits, actions: .none)
            InsightsHabitsCard(habits: InsightsPreviewData.sparse.habits, actions: .none)
        }
        .padding()
    }
    .background(Color.kadoBackground)
    .preferredColorScheme(.dark)
}

#Preview("XXXL") {
    ScrollView {
        InsightsHabitsCard(habits: InsightsPreviewData.rich.habits, actions: .none)
            .padding()
    }
    .background(Color.kadoBackground)
    .dynamicTypeSize(.accessibility3)
}
