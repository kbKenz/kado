import KadoCore
import SwiftUI

/// The big title on a Now card, after the item's icon: the task's
/// category or the habit's own icon. Tapping it opens the item.
struct NowCardTitle: View {
    let title: String
    let glyph: ItemGlyph?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                if let glyph {
                    ItemGlyphView(glyph: glyph)
                        .font(.title2.weight(.semibold))
                }
                Text(title)
                    .font(.largeTitle.bold())
                    .foregroundStyle(Color.kadoForeground)
                    .multilineTextAlignment(.leading)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel { label in
            label
            if let categoryName = glyph?.categoryName { Text(categoryName) }
        }
        .accessibilityHint(Text("Opens details"))
        .accessibilityIdentifier(AccessibilityID.Now.title)
    }
}

#Preview("Task and habit") {
    VStack(alignment: .leading, spacing: 24) {
        NowCardTitle(title: "Revise chemistry notes", glyph: ItemGlyph(category: .study)) {}
        NowCardTitle(title: "Read 20 pages", glyph: ItemGlyph(habitIcon: "book.fill", color: .purple)) {}
        NowCardTitle(title: "Research", glyph: nil) {}
    }
    .padding()
    .kadoTheme()
}

#Preview("Dark") {
    VStack(alignment: .leading, spacing: 24) {
        NowCardTitle(title: "Prepare the board meeting slides", glyph: ItemGlyph(category: .work)) {}
        NowCardTitle(title: "Think about the weekend", glyph: ItemGlyph(category: .other)) {}
    }
    .padding()
    .kadoTheme()
    .preferredColorScheme(.dark)
}

#Preview("XXXL") {
    NowCardTitle(title: "Revise chemistry notes", glyph: ItemGlyph(category: .study)) {}
        .padding()
        .kadoTheme()
        .dynamicTypeSize(.accessibility3)
}
