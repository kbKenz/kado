import SwiftUI
import KadoCore

/// An SF Symbol in a small tinted circle: a habit's icon in its colour,
/// or a category's icon in the category's colour. Without a colour
/// (`ItemCategory.other`) it sits on the neutral hairline.
///
/// Colours come from the habit theme (`tint(.mark)` behind,
/// `onTint` on top), the same pair as the mark on a Today row.
struct InsightsMark: View {
    let systemImage: String
    let color: HabitColor?

    @Environment(\.habitTheme) private var habitTheme
    @ScaledMetric(relativeTo: .subheadline) private var size: CGFloat = 30

    init(systemImage: String, color: HabitColor?) {
        self.systemImage = systemImage
        self.color = color
    }

    /// A category's icon in the category's colour.
    init(category: ItemCategory) {
        self.init(systemImage: category.symbolName, color: category.color)
    }

    var body: some View {
        // Capped, so a mark at accessibility sizes leaves the row room
        // for its text.
        let side = min(size, 48)
        Image(systemName: systemImage)
            .font(.system(size: side * 0.45, weight: .semibold))
            .foregroundStyle(glyph)
            .frame(width: side, height: side)
            .background(Circle().fill(fill))
            .accessibilityHidden(true)
    }

    private var fill: Color {
        color?.tint(.mark, in: habitTheme) ?? Color.kadoHairline
    }

    private var glyph: Color {
        color?.onTint(in: habitTheme) ?? Color.kadoForegroundSecondary
    }
}

extension ItemCategory {
    /// The colour of the category's chart marks and bars: its palette
    /// slot, or the neutral secondary ink for `.other`.
    func chartColor(in theme: HabitTheme) -> Color {
        color?.color(in: theme) ?? Color.kadoForegroundSecondary
    }
}

#Preview("Marks") {
    HStack(spacing: 12) {
        ForEach(ItemCategory.allCases) { category in
            InsightsMark(category: category)
        }
    }
    .padding()
    .background(Color.kadoBackgroundSecondary)
}

#Preview("Dark") {
    HStack(spacing: 12) {
        InsightsMark(systemImage: "book.fill", color: .purple)
        InsightsMark(systemImage: "figure.run", color: .orange)
        InsightsMark(category: .other)
    }
    .padding()
    .background(Color.kadoBackgroundSecondary)
    .preferredColorScheme(.dark)
}
