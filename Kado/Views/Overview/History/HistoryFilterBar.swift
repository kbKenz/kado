import SwiftUI
import KadoCore

/// One row of chips over the History: All / Tasks / Habits, then one
/// chip per category with something done. One tap filters; a second tap
/// on a category chip lets it go. Categories combine (Work or Study).
struct HistoryFilterBar: View {
    @Binding var kind: HistoryKind
    @Binding var categories: Set<ItemCategory>
    let available: [ItemCategory]

    @Environment(\.habitTheme) private var habitTheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(HistoryKind.allCases) { option in
                    chip(
                        title: Self.title(of: option),
                        symbol: nil,
                        tint: Color.kadoAccent,
                        isOn: kind == option,
                        identifier: AccessibilityID.History.kind(option.rawValue)
                    ) {
                        kind = option
                    }
                }
                if available.count > 1 {
                    Divider()
                        .frame(height: 20)
                        .padding(.horizontal, 2)
                    ForEach(available) { category in
                        chip(
                            title: category.localizedName,
                            symbol: category.symbolName,
                            tint: category.color?.color(in: habitTheme) ?? Color.kadoForegroundSecondary,
                            isOn: categories.contains(category),
                            identifier: AccessibilityID.History.category(category.rawValue)
                        ) {
                            if categories.contains(category) {
                                categories.remove(category)
                            } else {
                                categories.insert(category)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 4)
        }
        // A category that is no longer there can't stay picked, or the
        // page would be empty with no chip to undo it.
        .onChange(of: available) { _, now in
            categories.formIntersection(now)
        }
    }

    private func chip(
        title: String,
        symbol: String?,
        tint: Color,
        isOn: Bool,
        identifier: String,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            withAnimation(reduceMotion ? nil : .snappy(duration: 0.2)) { action() }
        } label: {
            HStack(spacing: 5) {
                if let symbol {
                    Image(systemName: symbol)
                        .foregroundStyle(isOn ? Color.kadoBackground : tint)
                        .accessibilityHidden(true)
                }
                Text(title)
                    .lineLimit(1)
            }
            .font(.subheadline.weight(.medium))
            .foregroundStyle(isOn ? Color.kadoBackground : Color.kadoForeground)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                Capsule().fill(isOn ? tint : Color.kadoBackgroundSecondary)
            )
            .overlay(
                Capsule().strokeBorder(isOn ? Color.clear : Color.kadoHairline, lineWidth: 1)
            )
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
        .accessibilityIdentifier(identifier)
    }

    static func title(of kind: HistoryKind) -> String {
        switch kind {
        case .all: String(localized: "All", comment: "History filter chip: show tasks and habits.")
        case .tasks: String(localized: "Tasks", comment: "History filter chip: show tasks only.")
        case .habits: String(localized: "Habits", comment: "History filter chip: show habits only.")
        }
    }
}

#Preview("Chips") {
    @Previewable @State var kind = HistoryKind.all
    @Previewable @State var categories: Set<ItemCategory> = [.study]
    HistoryFilterBar(kind: $kind, categories: $categories, available: [.work, .study, .fitness, .health, .home])
        .background(Color.kadoBackground)
}

#Preview("Dark") {
    @Previewable @State var kind = HistoryKind.tasks
    @Previewable @State var categories: Set<ItemCategory> = [.fitness]
    HistoryFilterBar(kind: $kind, categories: $categories, available: [.work, .study, .fitness])
        .background(Color.kadoBackground)
        .preferredColorScheme(.dark)
}
