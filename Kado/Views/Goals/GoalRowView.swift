import KadoCore
import SwiftUI

struct GoalRowView: View {
    let item: GoalListItem
    var progress: GoalProgressResult? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(item.name)
                .font(.body.weight(.semibold))
                .foregroundStyle(Color.kadoForeground)
            if !item.details.isEmpty {
                Text(item.details)
                    .font(.subheadline)
                    .foregroundStyle(Color.kadoForegroundSecondary)
                    .lineLimit(2)
            }
            if let progress, item.measurement.enabled {
                if progress.isAvailable {
                    Text("\(progress.current.formatted()) / \(item.measurement.target.formatted()) \(GoalProgressDisplay.unit(progress.unit, mode: item.measurement.mode))")
                        .font(.caption).foregroundStyle(Color.kadoForegroundSecondary)
                    ProgressView(value: progress.fraction).tint(Color.kadoAccent).accessibilityLabel("Goal progress")
                } else { Text("Source unavailable").font(.caption).foregroundStyle(.secondary) }
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) { metadata }
                VStack(alignment: .leading, spacing: 5) { metadata }
            }
            .font(.caption)
            .foregroundStyle(Color.kadoForegroundSecondary)
        }
        .padding(.vertical, 5)
    }

    @ViewBuilder
    private var metadata: some View {
        Label(item.archivedAt == nil ? item.status.plannerTitle : String(localized: "Archived"),
              systemImage: item.archivedAt == nil ? item.status.plannerSymbol : "archivebox")
        if let target = item.targetDate {
            Text("Target \(target.formatted(date: .abbreviated, time: .omitted))")
        }
    }
}

private enum GoalRowPreview {
    static let active = GoalListItem(name: "Make more time for health", details: "Build a routine that fits an ordinary week.", targetDate: .now)
    static let paused = GoalListItem(name: "Learn conversational Japanese", status: .paused)
    static let completed = GoalListItem(name: "Finish the first draft", status: .completed, completedAt: .now)
}

#Preview("Goal states") {
    List {
        GoalRowView(item: GoalRowPreview.active)
        GoalRowView(item: GoalRowPreview.paused)
        GoalRowView(item: GoalRowPreview.completed)
    }
    .kadoTheme()
}

#Preview("Dark") {
    List {
        GoalRowView(item: GoalRowPreview.active)
        GoalRowView(item: GoalRowPreview.completed)
    }
    .kadoTheme()
    .preferredColorScheme(.dark)
}
