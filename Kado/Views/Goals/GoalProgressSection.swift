import KadoCore
import SwiftUI

struct GoalProgressSection: View {
    let goal: GoalListItem
    let result: GoalProgressResult
    let manualEntries: [GoalProgressEntry]
    let onAdd: () -> Void
    let onEdit: (UUID) -> Void
    let onTask: (UUID) -> Void

    var body: some View {
        Section {
            if result.isAvailable {
                Text("\(result.current.formatted()) / \(goal.measurement.target.formatted()) \(GoalProgressDisplay.unit(result.unit, mode: goal.measurement.mode))")
                    .font(.headline).accessibilityIdentifier("goal.progress.total")
                ProgressView(value: result.fraction)
                    .tint(Color.kadoAccent)
                    .accessibilityLabel("Goal progress")
                    .accessibilityValue(result.fraction.formatted(.percent.precision(.fractionLength(0))))
                if goal.measurement.baseline > 0 {
                    Text("Baseline: \(goal.measurement.baseline.formatted())").font(.caption).foregroundStyle(.secondary)
                }
                if goal.measurement.mode == .manual {
                    Button("Add progress", action: onAdd)
                        .disabled(goal.archivedAt != nil).accessibilityIdentifier("goal.progress.add")
                }
            } else {
                Label("Source unavailable", systemImage: "exclamationmark.circle")
                Text("Choose a linked counter or timer habit in Edit Goal. Your configuration and history are retained.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        } header: { Text("Progress") }
        footer: {
            Text(goal.measurement.mode == .tasks
                 ? String(localized: "Each currently linked completed task counts once. Reopening or unlinking a task recalculates progress.")
                 : String(localized: "Progress counts from the start date through today. The deadline does not stop counting; goal completion stays manual."))
        }
        .listRowBackground(Color.kadoBackgroundSecondary)
        Section {
            if goal.measurement.mode == .manual {
                if manualEntries.isEmpty { Text("No progress entries yet").foregroundStyle(.secondary) }
                ForEach(manualEntries.sorted { $0.date > $1.date }) { entry in
                    Button { onEdit(entry.id) } label: {
                        contribution(date: entry.date, amount: entry.amount, title: entry.note ?? "", included: result.contributions.contains { $0.id == entry.id })
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("goal.progress.entry.\(entry.id)")
                }
            } else {
                if result.contributions.isEmpty { Text("No recorded progress in this period").foregroundStyle(.secondary) }
                ForEach(result.contributions) { entry in
                    switch entry.source {
                    case .task(let id):
                        Button { onTask(id) } label: { contribution(date: entry.date, amount: entry.amount, title: entry.title) }.buttonStyle(.plain)
                    case .habit(let id):
                        NavigationLink(value: HabitRoute(id: id)) { contribution(date: entry.date, amount: entry.amount, title: entry.title) }
                    case .manual: EmptyView()
                    }
                }
            }
        } header: { Text("Progress history") }
        footer: { Text("Open an entry to review or correct its original record.") }
        .listRowBackground(Color.kadoBackgroundSecondary)
    }
    private func contribution(date: Date, amount: Double, title: String, included: Bool = true) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("+\(amount.formatted()) \(GoalProgressDisplay.unit(result.unit, mode: goal.measurement.mode))").font(.body.weight(.medium))
            Text(date, format: .dateTime.year().month(.abbreviated).day()).font(.caption).foregroundStyle(.secondary)
            if !title.isEmpty { Text(title).font(.subheadline).foregroundStyle(.secondary) }
            if !included { Text("Outside measurement period").font(.caption).foregroundStyle(.secondary) }
        }
        .foregroundStyle(Color.kadoForeground)
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}
