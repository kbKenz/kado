import SwiftUI
import KadoCore

/// Workouts from Apple Health (count, average length, most frequent
/// type), then Fitness habits and tasks (times done, average time) and
/// the Fitness habits' consistency.
///
/// Without Health it offers to connect it; without a Fitness habit it
/// offers one.
struct InsightsMovementCard: View {
    let movement: InsightsMovement
    let actions: InsightsActions

    var body: some View {
        InsightsCard(kind: .movement) {
            VStack(alignment: .leading, spacing: 16) {
                health
                habitsAndTasks
                if movement.habits.isEmpty {
                    InsightsHealthPrompt(message: nil, showsConnect: false, template: .workout, actions: actions)
                } else {
                    InsightsHabitConsistencyList(habits: movement.habits)
                }
            }
        }
    }

    // MARK: - Apple Health

    @ViewBuilder
    private var health: some View {
        if !movement.isHealthConnected {
            InsightsHealthPrompt(
                message: "Connect Apple Health to see your workouts.",
                showsConnect: true,
                template: nil,
                actions: actions
            )
        } else if movement.workoutCount > 0 {
            section(title: "Apple Health", lines: workoutLines)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(spokenWorkouts))
        } else {
            Text("No workouts from Apple Health in this period.")
                .font(.subheadline)
                .foregroundStyle(Color.kadoForegroundSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// "12 workouts", "avg 42m", "Top: Running, 7 times".
    private var workoutLines: [String] {
        var lines = [String(localized: "\(movement.workoutCount) workouts", comment: "Insights Movement: Apple Health workouts in the period.")]
        if let average = movement.averageWorkout {
            lines.append(String(localized: "avg \(InsightsFormat.duration(average))", comment: "Insights Movement: average length. avg is short for average. The value is a duration."))
        }
        if let top = movement.topWorkout {
            lines.append(String(localized: "Top: \(top.name), \(top.count) times", comment: "Insights Movement: the most frequent workout type and how often it was done."))
        }
        return lines
    }

    /// The same lines for VoiceOver, with "Average" spelled out.
    private var spokenWorkouts: String {
        var parts = [String(localized: "\(movement.workoutCount) workouts", comment: "Insights Movement: Apple Health workouts in the period.")]
        if let average = movement.averageWorkout {
            parts.append(String(localized: "Average \(InsightsFormat.duration(average))", comment: "Insights, VoiceOver: an average length. The value is a duration."))
        }
        if let top = movement.topWorkout {
            parts.append(String(localized: "Top: \(top.name), \(top.count) times", comment: "Insights Movement: the most frequent workout type and how often it was done."))
        }
        return parts.map { $0 + "." }.joined(separator: " ")
    }

    // MARK: - Habits and tasks

    @ViewBuilder
    private var habitsAndTasks: some View {
        if movement.fitnessTimesDone > 0 {
            section(title: "Habits and tasks", lines: fitnessLines)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(spokenFitness))
        }
    }

    /// "11 times", "avg 35m".
    private var fitnessLines: [String] {
        var lines = [String(localized: "\(movement.fitnessTimesDone) times", comment: "Insights: how many times something was done in the period.")]
        if let average = movement.averageFitnessTime {
            lines.append(String(localized: "avg \(InsightsFormat.duration(average))", comment: "Insights Movement: average length. avg is short for average. The value is a duration."))
        }
        return lines
    }

    private var spokenFitness: String {
        let times = String(localized: "Fitness habits and tasks: \(movement.fitnessTimesDone) times", comment: "Insights Movement, VoiceOver: Fitness habit days and tasks done in the period.")
        guard let average = movement.averageFitnessTime else { return times + "." }
        let averageText = String(localized: "Average \(InsightsFormat.duration(average))", comment: "Insights, VoiceOver: an average length. The value is a duration.")
        return "\(times). \(averageText)."
    }

    // MARK: - Layout

    /// A small caption, then the figures on one line: the first large,
    /// the rest after it.
    private func section(title: LocalizedStringKey, lines: [String]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.kadoForegroundSecondary)
            if let first = lines.first {
                Text(first)
                    .font(.title3.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(Color.kadoForeground)
            }
            if lines.count > 1 {
                Text(lines.dropFirst().joined(separator: " · "))
                    .font(.subheadline)
                    .monospacedDigit()
                    .foregroundStyle(Color.kadoForegroundSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

#Preview("Health") {
    InsightsMovementCard(movement: InsightsPreviewData.rich.movement, actions: .none)
        .padding()
        .background(Color.kadoBackground)
}

#Preview("Dark") {
    ScrollView {
        VStack(spacing: 16) {
            InsightsMovementCard(movement: InsightsPreviewData.rich.movement, actions: .none)
            InsightsMovementCard(movement: InsightsPreviewData.sparse.movement, actions: .none)
            InsightsMovementCard(movement: .empty, actions: .none)
        }
        .padding()
    }
    .background(Color.kadoBackground)
    .preferredColorScheme(.dark)
}
