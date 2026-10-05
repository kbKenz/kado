import KadoCore
import SwiftUI

/// A task always reads completion from TaskRecord, including when the
/// same task has several planned blocks or originated in Google.
struct TaskRowView: View {
    let item: TaskListItem
    var schedule: TaskScheduleItem? = nil
    var showsDate = true
    let onToggle: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    @Environment(\.calendar) private var calendar
    @Environment(\.civilToday) private var today
    /// The icon column of the lines under the title: wide enough for
    /// the widest category symbol, so every line's text starts at the
    /// same place.
    @ScaledMetric(relativeTo: .caption) private var iconWidth: CGFloat = 18

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Button(action: onToggle) {
                Image(systemName: item.isComplete ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(item.isComplete ? Color.kadoAccent : Color.kadoForegroundSecondary)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(item.isComplete ? String(localized: "Mark incomplete") : String(localized: "Complete task"))
            .accessibilityValue(item.isComplete ? String(localized: "Complete") : String(localized: "Incomplete"))
            .accessibilityHint(Text(item.title))
            .accessibilityIdentifier(AccessibilityID.Tasks.complete(item.id))

            Button(action: onEdit) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(item.title)
                        .font(.body.weight(.medium))
                        .foregroundStyle(item.isComplete ? Color.kadoForegroundSecondary : Color.kadoForeground)
                        .strikethrough(item.isComplete)
                        .multilineTextAlignment(.leading)
                    // The category glyph leads the date line, so the
                    // title keeps the row's full width.
                    detailLine(Text(subtitle)) {
                        ItemGlyphView(glyph: ItemGlyph(category: category))
                    }
                    .font(.caption)
                    if item.isFromGoogle {
                        detailLine(Text("Google Calendar")) {
                            Image(systemName: "arrow.triangle.2.circlepath")
                        }
                        .font(.caption2)
                    }
                    if let goalName = item.goalName {
                        detailLine(Text(goalName)) {
                            Image(systemName: "target")
                        }
                        .font(.caption)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .accessibilityElement(children: .combine)
            .accessibilityLabel { label in
                label
                Text(category.localizedName)
            }
            .accessibilityValue(item.isComplete ? String(localized: "Complete") : String(localized: "Incomplete"))
            .accessibilityHint(item.isFromGoogle ? Text("View event") : Text("Edit task"))
            .accessibilityIdentifier(AccessibilityID.Tasks.row(item.id))
        }
        .padding(.vertical, 3)
        .contextMenu {
            Button(action: onToggle) {
                Label(item.isComplete ? String(localized: "Mark incomplete") : String(localized: "Complete task"), systemImage: "checkmark.circle")
            }
            Button(action: onEdit) { Label("Edit task", systemImage: "pencil") }
            Button(role: .destructive, action: onDelete) {
                Label(item.isFromGoogle ? String(localized: "Remove from planner") : String(localized: "Delete task"), systemImage: "trash")
            }
        }
        .accessibilityAction(named: item.isComplete ? Text("Mark incomplete") : Text("Complete task"), onToggle)
        .accessibilityAction(named: Text("Edit task"), onEdit)
        .accessibilityAction(named: item.isFromGoogle ? Text("Remove from planner") : Text("Delete task"), onDelete)
    }

    private var category: ItemCategory { item.resolvedCategory }

    /// A line under the title: an icon in a fixed column, then the text.
    /// The icon is decorative; the row's label carries what it means.
    private func detailLine<Icon: View>(_ text: Text, @ViewBuilder icon: () -> Icon) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            icon()
                .frame(width: iconWidth, alignment: .leading)
                .accessibilityHidden(true)
            text
                .multilineTextAlignment(.leading)
        }
        .foregroundStyle(Color.kadoForegroundSecondary)
    }

    private var subtitle: String {
        let chosenSchedule = schedule ?? item.schedules.first
        let time = chosenSchedule?.timeLabel
        guard showsDate else { return time ?? String(localized: "Any time") }
        guard let date = chosenSchedule?.plannedDay ?? item.dueDate else {
            return String(localized: "No day selected")
        }
        let dateLabel: String
        if calendar.isDate(date, inSameDayAs: today) {
            dateLabel = String(localized: "Today")
        } else if date < calendar.startOfDay(for: today) && !item.isComplete {
            dateLabel = String(localized: "Overdue · \(date.formatted(date: .abbreviated, time: .omitted))")
        } else {
            dateLabel = date.formatted(date: .abbreviated, time: .omitted)
        }
        return time.map { "\(dateLabel) · \($0)" } ?? dateLabel
    }
}

#Preview("Tasks") {
    List {
        TaskRowView(item: TaskListItem(title: "Prepare for tomorrow"), onToggle: {}, onEdit: {}, onDelete: {})
        TaskRowView(item: TaskListItem(title: "Meeting with Thomas", dueDate: .now, isFromGoogle: true), onToggle: {}, onEdit: {}, onDelete: {})
        TaskRowView(item: TaskListItem(title: "Contact professors at Cambridge", dueDate: .now,
                                       goalName: "Get into Cambridge", goalCategory: .study),
                    onToggle: {}, onEdit: {}, onDelete: {})
    }
    .kadoTheme()
}

#Preview("Dark") {
    List {
        TaskRowView(item: TaskListItem(title: "Read a chapter", dueDate: .now, completedAt: .now), onToggle: {}, onEdit: {}, onDelete: {})
        TaskRowView(item: TaskListItem(title: "Meeting with Thomas", isFromGoogle: true), onToggle: {}, onEdit: {}, onDelete: {})
        TaskRowView(item: TaskListItem(title: "Pay the electricity bill", dueDate: .now), onToggle: {}, onEdit: {}, onDelete: {})
    }
    .kadoTheme()
    .preferredColorScheme(.dark)
}

#Preview("XXXL") {
    List {
        TaskRowView(item: TaskListItem(title: "Prepare the slides for the quarterly planning meeting", dueDate: .now,
                                       goalName: "Get promoted"),
                    onToggle: {}, onEdit: {}, onDelete: {})
    }
    .kadoTheme()
    .dynamicTypeSize(.accessibility3)
}
