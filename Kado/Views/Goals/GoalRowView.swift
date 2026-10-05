import KadoCore
import SwiftUI

struct GoalRowView: View {
    let item: GoalListItem
    var progress: GoalProgressResult? = nil

    /// Wide enough for the widest category symbol, so every name starts
    /// at the same place.
    @ScaledMetric(relativeTo: .body) private var iconWidth: CGFloat = 26

    var body: some View {
        // The icon sits in a column of its own, so the details, progress
        // and dates below line up with the name.
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            ItemGlyphView(glyph: ItemGlyph(category: item.resolvedCategory))
                .font(.body.weight(.semibold))
                .frame(width: iconWidth)
            details
        }
        .padding(.vertical, 5)
    }

    private var details: some View {
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
    static let study = GoalListItem(name: "Get into Cambridge", details: "Apply for the 2027 intake.", targetDate: .now, category: .study)
}

#Preview("Goal states") {
    List {
        GoalRowView(item: GoalRowPreview.active)
        GoalRowView(item: GoalRowPreview.paused)
        GoalRowView(item: GoalRowPreview.completed)
        GoalRowView(item: GoalRowPreview.study)
    }
    .kadoTheme()
}

#Preview("Dark") {
    List {
        GoalRowView(item: GoalRowPreview.active)
        GoalRowView(item: GoalRowPreview.completed)
        GoalRowView(item: GoalRowPreview.study)
    }
    .kadoTheme()
    .preferredColorScheme(.dark)
}

#Preview("XXXL") {
    List {
        GoalRowView(item: GoalRowPreview.study)
    }
    .kadoTheme()
    .dynamicTypeSize(.accessibility3)
}
