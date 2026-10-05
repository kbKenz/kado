import SwiftUI
import KadoCore

/// The habits of one category with their consistency, as the Sleep and
/// Movement cards list them. One VoiceOver element for the list.
struct InsightsHabitConsistencyList: View {
    let habits: [InsightsHabitConsistency]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(habits) { habit in
                HStack(spacing: 10) {
                    InsightsMark(systemImage: habit.icon, color: habit.color)
                    Text(habit.name)
                        .font(.subheadline)
                        .foregroundStyle(Color.kadoForeground)
                        .lineLimit(2)
                    Spacer(minLength: 8)
                    Text(InsightsFormat.percent(habit.rate) ?? "—")
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(Color.kadoForeground)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(spoken))
    }

    /// "Lights out by 11: 73% consistent. Run: no data yet."
    private var spoken: String {
        habits.map { habit in
            guard let percent = InsightsFormat.percent(habit.rate) else {
                return String(localized: "\(habit.name): no data yet", comment: "Insights, VoiceOver: a habit had nothing due in this period. The value is the habit name.")
            }
            return String(localized: "\(habit.name): \(percent) consistent", comment: "Insights, VoiceOver: a habit's share of due days done. The values are the habit name and a percent.")
        }
        .joined(separator: ". ")
    }
}

#Preview("Habits") {
    InsightsHabitConsistencyList(habits: InsightsPreviewData.rich.sleep.habits + InsightsPreviewData.rich.movement.habits)
        .padding()
        .background(Color.kadoBackgroundSecondary)
}

#Preview("Dark") {
    InsightsHabitConsistencyList(habits: InsightsPreviewData.rich.movement.habits)
        .padding()
        .background(Color.kadoBackgroundSecondary)
        .preferredColorScheme(.dark)
}
