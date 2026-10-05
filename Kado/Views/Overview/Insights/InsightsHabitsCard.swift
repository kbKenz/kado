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

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                InsightsMark(systemImage: habit.icon, color: habit.color)
                VStack(alignment: .leading, spacing: 2) {
                    Text(habit.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.kadoForeground)
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)
                    Text(detail)
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(Color.kadoForegroundSecondary)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 2) {
                    Text(InsightsFormat.percent(habit.rate) ?? "—")
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(Color.kadoForeground)
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
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.kadoForegroundTertiary)
            }
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(spoken))
        .accessibilityHint(Text("Opens the habit.", comment: "Insights Habits, VoiceOver hint on a habit row."))
        .accessibilityIdentifier(AccessibilityID.Insights.habitRow(habit.habitID))
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
