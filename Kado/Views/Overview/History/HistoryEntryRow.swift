import SwiftUI
import KadoCore

/// One thing done: its glyph, title and when, then what was done on the
/// right ("3/5", "25 min", a tick).
///
/// A tap opens the task's form or the habit's detail. The long-press
/// menu holds the one correction History needs, and VoiceOver gets the
/// same actions. A context menu rather than swipe actions, which only
/// fire inside a `List` (CLAUDE.md, issue #87).
struct HistoryEntryRow: View {
    let entry: HistoryEntry
    var actions: HistoryActions

    @Environment(\.habitTheme) private var habitTheme
    @ScaledMetric(relativeTo: .body) private var glyphSize: CGFloat = 34

    var body: some View {
        Button(action: open) {
            HStack(alignment: .center, spacing: 12) {
                glyph
                VStack(alignment: .leading, spacing: 3) {
                    Text(entry.title)
                        .font(.body.weight(.medium))
                        .foregroundStyle(Color.kadoForeground)
                        .multilineTextAlignment(.leading)
                    detailLine
                    if let note {
                        Label(note, systemImage: "note.text")
                            .font(.caption)
                            .foregroundStyle(Color.kadoForegroundSecondary)
                            .lineLimit(2)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                outcome
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu { menu }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(spokenLabel))
        .accessibilityValue(Text(outcomeText))
        .accessibilityHint(entry.isTask ? Text("Edit task") : Text("Open habit"))
        .accessibilityAddTraits(.isButton)
        .accessibilityActions { accessibilityActionList }
        .accessibilityIdentifier(AccessibilityID.History.entry(entry.id))
    }

    // MARK: - Pieces

    private var itemGlyph: ItemGlyph {
        if let icon = entry.habitIcon, let color = entry.habitColor {
            return ItemGlyph(habitIcon: icon, color: color)
        }
        return ItemGlyph(category: entry.category)
    }

    private var tint: Color {
        itemGlyph.color?.color(in: habitTheme) ?? Color.kadoForegroundSecondary
    }

    private var glyph: some View {
        ItemGlyphView(glyph: itemGlyph)
            .font(.system(size: glyphSize * 0.45, weight: .semibold))
            .frame(width: glyphSize, height: glyphSize)
            .background(tint.opacity(0.15), in: Circle())
    }

    /// Time, tracked time and goal, joined by middots.
    private var detailLine: some View {
        HStack(spacing: 6) {
            Text(entry.time, format: .dateTime.hour().minute())
            if entry.trackedSeconds >= 60, !isFocus {
                Label(InsightsFormat.duration(entry.trackedSeconds), systemImage: "timer")
                    .labelStyle(TightLabelStyle())
            }
            if let goal = entry.goalName {
                Label(goal, systemImage: "target")
                    .labelStyle(TightLabelStyle())
                    .lineLimit(1)
            }
        }
        .font(.caption)
        .foregroundStyle(Color.kadoForegroundSecondary)
    }

    @ViewBuilder
    private var outcome: some View {
        switch entry.item {
        case .task:
            Image(systemName: "checkmark.circle.fill")
                .font(.title3)
                .foregroundStyle(Color.kadoAccent)
        case .habit(_, _, let type, let value, _):
            switch type {
            case .binary:
                Image(systemName: "checkmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(tint)
            case .negative:
                outcomeText(String(localized: "Slipped"), color: Color.kadoForegroundSecondary)
            case .counter, .timer:
                outcomeText(Self.amount(value, of: type), color: tint)
            }
        case .focus:
            Label(InsightsFormat.duration(entry.trackedSeconds), systemImage: "timer")
                .labelStyle(TightLabelStyle())
                .font(.callout.weight(.semibold).monospacedDigit())
                .foregroundStyle(Color.kadoForegroundSecondary)
        }
    }

    private func outcomeText(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.callout.weight(.semibold).monospacedDigit())
            .foregroundStyle(color)
            .fixedSize()
    }

    @ViewBuilder
    private var menu: some View {
        switch entry.item {
        case .task(let id):
            Button { actions.openTask(id) } label: { Label("Edit task", systemImage: "pencil") }
            Button { actions.markTaskNotDone(id) } label: { Label("Mark incomplete", systemImage: "arrow.uturn.backward.circle") }
        case .habit(let id, let completionID, _, _, _):
            Button { actions.openHabit(id) } label: { Label("Open habit", systemImage: "arrow.right.circle") }
            Button(role: .destructive) { actions.deleteHabitRecord(completionID) } label: { Label("Delete entry", systemImage: "trash") }
        case .focus(let taskID, let habitID):
            if let taskID {
                Button { actions.openTask(taskID) } label: { Label("Edit task", systemImage: "pencil") }
            } else if let habitID {
                Button { actions.openHabit(habitID) } label: { Label("Open habit", systemImage: "arrow.right.circle") }
            }
        }
    }

    @ViewBuilder
    private var accessibilityActionList: some View {
        switch entry.item {
        case .task(let id):
            Button("Mark incomplete") { actions.markTaskNotDone(id) }
        case .habit(_, let completionID, _, _, _):
            Button("Delete entry") { actions.deleteHabitRecord(completionID) }
        case .focus:
            EmptyView()
        }
    }

    // MARK: - Text

    private var isFocus: Bool {
        if case .focus = entry.item { return true }
        return false
    }

    private var note: String? {
        if case .habit(_, _, _, _, let note) = entry.item { return note }
        return nil
    }

    private func open() {
        switch entry.item {
        case .task(let id): actions.openTask(id)
        case .habit(let id, _, _, _, _): actions.openHabit(id)
        case .focus(let taskID, let habitID):
            if let taskID { actions.openTask(taskID) } else if let habitID { actions.openHabit(habitID) }
        }
    }

    /// What the right side says, for VoiceOver.
    private var outcomeText: String {
        switch entry.item {
        case .task:
            return String(localized: "Done")
        case .habit(_, _, let type, let value, _):
            switch type {
            case .binary: return String(localized: "Done")
            case .negative: return String(localized: "Slipped")
            case .counter, .timer: return Self.amount(value, of: type)
            }
        case .focus:
            return String(localized: "Worked \(InsightsFormat.duration(entry.trackedSeconds))", comment: "History, VoiceOver: time tracked on a task or habit that was not finished that day. The value is a duration.")
        }
    }

    private var spokenLabel: String {
        var parts = [entry.title, entry.category.localizedName, entry.time.formatted(date: .omitted, time: .shortened)]
        if entry.trackedSeconds >= 60, !isFocus {
            parts.append(String(localized: "Focus time \(InsightsFormat.duration(entry.trackedSeconds))", comment: "Insights Focus, VoiceOver: total session time in the period. The value is a duration."))
        }
        if let goal = entry.goalName { parts.append(goal) }
        if let note { parts.append(String(localized: "Note: \(note)")) }
        return parts.joined(separator: ", ")
    }

    /// "3/5" for a counter, "25 min / 30 min" for a timer.
    static func amount(_ value: Double, of type: HabitType) -> String {
        switch type {
        case .counter(let target):
            return "\(InsightsFormat.amount(value))/\(InsightsFormat.amount(target))"
        case .timer(let targetSeconds):
            return "\(InsightsFormat.duration(value)) / \(InsightsFormat.duration(targetSeconds))"
        case .binary, .negative:
            return InsightsFormat.amount(value)
        }
    }
}

/// Icon and text close together.
private struct TightLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 3) {
            configuration.icon
            configuration.title
        }
    }
}

#Preview("Rows") {
    ScrollView {
        VStack(spacing: 0) {
            ForEach(HistoryPreviewData.days.prefix(2).flatMap(\.entries)) { entry in
                HistoryEntryRow(entry: entry, actions: HistoryActions())
                Divider().padding(.leading, 60)
            }
        }
        .background(Color.kadoBackgroundSecondary, in: RoundedRectangle(cornerRadius: KadoRadius.card))
        .padding()
    }
    .background(Color.kadoBackground)
}

#Preview("Dark") {
    ScrollView {
        VStack(spacing: 0) {
            ForEach(HistoryPreviewData.days.prefix(2).flatMap(\.entries)) { entry in
                HistoryEntryRow(entry: entry, actions: HistoryActions())
                Divider().padding(.leading, 60)
            }
        }
        .background(Color.kadoBackgroundSecondary, in: RoundedRectangle(cornerRadius: KadoRadius.card))
        .padding()
    }
    .background(Color.kadoBackground)
    .preferredColorScheme(.dark)
}
