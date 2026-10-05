import KadoCore
import SwiftUI

/// Draws an `ItemGlyph`: the symbol at the surrounding font's size, in
/// its palette slot's base colour under the current habit theme (the
/// shade `HabitColor` keeps for an icon beside a name). Without a slot
/// it takes the secondary ink.
///
/// Decorative: VoiceOver skips it, and the row that shows it reads the
/// category name in its own label.
struct ItemGlyphView: View {
    let glyph: ItemGlyph

    @Environment(\.habitTheme) private var habitTheme

    var body: some View {
        Image(systemName: glyph.symbolName)
            .foregroundStyle(tint)
            .accessibilityHidden(true)
    }

    private var tint: Color {
        glyph.color?.color(in: habitTheme) ?? Color.kadoForegroundSecondary
    }
}

private enum ItemGlyphPreview {
    static let habit = ItemGlyph(habitIcon: "book.fill", color: .purple)
}

#Preview("Categories") {
    VStack(alignment: .leading, spacing: 10) {
        ForEach(ItemCategory.allCases) { category in
            Label {
                Text(category.localizedName)
            } icon: {
                ItemGlyphView(glyph: ItemGlyph(category: category))
            }
        }
        Label {
            Text(verbatim: "Read 20 pages")
        } icon: {
            ItemGlyphView(glyph: ItemGlyphPreview.habit)
        }
    }
    .padding()
    .kadoTheme()
}

#Preview("Dark") {
    VStack(alignment: .leading, spacing: 10) {
        ForEach(ItemCategory.allCases) { category in
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                ItemGlyphView(glyph: ItemGlyph(category: category))
                Text(category.localizedName)
            }
            .font(.caption)
            .foregroundStyle(Color.kadoForegroundSecondary)
        }
    }
    .padding()
    .background(Color.kadoBackgroundSecondary)
    .kadoTheme()
    .preferredColorScheme(.dark)
}
