import KadoCore
import SwiftUI

/// The row under a form's title that shows what the app suggested from
/// it: a wand, the word "Suggested", one chip per field and Undo.
///
/// An applied value is a filled chip with a checkmark; an offered value
/// is an outlined chip with a plus, which applies it on a tap. Undo puts
/// every applied field back and locks it. The form shows this row only
/// while the draft has chips.
struct SuggestionStrip: View {
    let draft: SuggestionDraft

    @Environment(\.habitTheme) private var habitTheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            ChipFlowLayout(spacing: 8) {
                ForEach(draft.chips) { chip in
                    chipView(chip)
                }
            }
        }
        .padding(.vertical, 2)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            HStack(spacing: 5) {
                Image(systemName: "wand.and.stars")
                    .accessibilityHidden(true)
                Text("Suggested")
            }
            .font(.footnote.weight(.semibold))
            .foregroundStyle(Color.kadoForegroundSecondary)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier(AccessibilityID.Suggestion.strip)
            Spacer(minLength: 8)
            if draft.canUndo {
                Button("Undo") {
                    withAnimation(reduceMotion ? nil : KadoMotion.base) { draft.undo() }
                }
                .font(.footnote.weight(.semibold))
                .buttonStyle(.borderless)
                .accessibilityLabel(Text("Undo suggestions"))
                .accessibilityIdentifier(AccessibilityID.Suggestion.undo)
            }
        }
    }

    @ViewBuilder
    private func chipView(_ chip: SuggestionChip) -> some View {
        let goalName = chip.goalID.flatMap(draft.goalName(for:))
        if chip.isApplied {
            chipLabel(chip, goalName: goalName)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(chip.appliedLabel(goalName: goalName)))
                .accessibilityIdentifier(AccessibilityID.Suggestion.chip(chip.field.rawValue))
        } else {
            Button {
                withAnimation(reduceMotion ? nil : KadoMotion.base) { draft.accept(chip) }
            } label: {
                chipLabel(chip, goalName: goalName)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(Text(chip.offerLabel(goalName: goalName)))
            .accessibilityIdentifier(AccessibilityID.Suggestion.chip(chip.field.rawValue))
        }
    }

    private func chipLabel(_ chip: SuggestionChip, goalName: String?) -> some View {
        HStack(spacing: 5) {
            if !chip.isApplied {
                Image(systemName: "plus")
                    .font(.caption2.weight(.bold))
            }
            glyph(chip)
            Text(chip.title(goalName: goalName))
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            if chip.isApplied {
                Image(systemName: "checkmark")
                    .font(.caption2.weight(.bold))
            }
        }
        .font(.footnote)
        .foregroundStyle(chip.isApplied ? Color.kadoAccent : Color.kadoForeground)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background {
            Capsule().fill(chip.isApplied ? Color.kadoAccentTint : Color.clear)
        }
        .overlay {
            Capsule().strokeBorder(chip.isApplied ? Color.clear : Color.kadoDivider, lineWidth: 1)
        }
        .contentShape(Capsule())
    }

    @ViewBuilder
    private func glyph(_ chip: SuggestionChip) -> some View {
        switch chip.value {
        case .category(let category):
            Image(systemName: category.symbolName)
        case .goal:
            Image(systemName: "scope")
        case .icon(let icon):
            Image(systemName: icon)
        case .color(let color):
            Circle()
                .fill(color.color(in: habitTheme))
                .frame(width: 12, height: 12)
        }
    }
}

/// Lays chips out left to right and wraps them onto new lines, so a
/// long goal name or a large text size never pushes a chip off screen.
private struct ChipFlowLayout: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        let rows = arrange(subviews, in: width)
        let height = rows.last.map { $0.y + $0.height } ?? 0
        let used = rows.map(\.width).max() ?? 0
        return CGSize(width: proposal.width ?? used, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for row in arrange(subviews, in: bounds.width) {
            for item in row.items {
                subviews[item.index].place(
                    at: CGPoint(x: bounds.minX + item.x, y: bounds.minY + row.y),
                    proposal: ProposedViewSize(item.size)
                )
            }
        }
    }

    private struct Row {
        var items: [(index: Int, x: CGFloat, size: CGSize)] = []
        var y: CGFloat = 0
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(_ subviews: Subviews, in width: CGFloat) -> [Row] {
        var rows: [Row] = []
        var row = Row()
        for index in subviews.indices {
            var size = subviews[index].sizeThatFits(ProposedViewSize(width: width, height: nil))
            size.width = min(size.width, width)
            let x = row.items.isEmpty ? 0 : row.width + spacing
            if !row.items.isEmpty, x + size.width > width {
                let nextY = row.y + row.height + spacing
                rows.append(row)
                row = Row(y: nextY)
                row.items.append((index: index, x: 0, size: size))
                row.width = size.width
            } else {
                row.items.append((index: index, x: x, size: size))
                row.width = x + size.width
            }
            row.height = max(row.height, size.height)
        }
        if !row.items.isEmpty { rows.append(row) }
        return rows
    }
}

// MARK: - Previews

@MainActor
private enum SuggestionStripPreview {
    static let cambridge = SuggestionGoal(name: "Get into Cambridge", category: nil)

    /// A new task: category and goal applied from a title with typos.
    static func applied() -> SuggestionDraft {
        let draft = SuggestionDraft(kind: .task)
        draft.applyWords(title: "contact proffesors at cambrrdgige", goals: [cambridge])
        return draft
    }

    /// A new habit: icon, category and colour applied.
    static func habit() -> SuggestionDraft {
        let draft = SuggestionDraft(kind: .habit)
        draft.applyWords(title: "Morning run", goals: [])
        return draft
    }

    /// An edit form: offers only.
    static func offers() -> SuggestionDraft {
        let draft = SuggestionDraft(kind: .task, isEditing: true)
        draft.load(category: nil, goalID: nil)
        draft.applyWords(title: "Email Cambridge professors", goals: [cambridge])
        return draft
    }
}

#Preview("Applied") {
    Form {
        Section {
            Text("contact proffesors at cambrrdgige")
            SuggestionStrip(draft: SuggestionStripPreview.applied())
        }
        Section {
            Text("Morning run")
            SuggestionStrip(draft: SuggestionStripPreview.habit())
        }
    }
    .kadoTheme()
}

#Preview("Offers") {
    Form {
        Section {
            Text("Email Cambridge professors")
            SuggestionStrip(draft: SuggestionStripPreview.offers())
        }
    }
    .kadoTheme()
}

#Preview("Dark") {
    Form {
        Section {
            Text("contact proffesors at cambrrdgige")
            SuggestionStrip(draft: SuggestionStripPreview.applied())
        }
        Section {
            Text("Email Cambridge professors")
            SuggestionStrip(draft: SuggestionStripPreview.offers())
        }
    }
    .kadoTheme()
    .preferredColorScheme(.dark)
}
