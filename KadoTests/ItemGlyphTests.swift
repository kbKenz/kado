import KadoCore
import Testing
@testable import Kado

@Suite("Item glyph")
struct ItemGlyphTests {
    @Test("A category glyph takes the category's symbol, colour slot and name")
    func categoryGlyph() {
        for category in ItemCategory.allCases {
            let glyph = ItemGlyph(category: category)
            #expect(glyph.symbolName == category.symbolName)
            #expect(glyph.color == category.color)
            #expect(glyph.categoryName == category.localizedName)
        }
    }

    @Test("Other has no colour slot, so it draws in the secondary ink")
    func otherHasNoColor() {
        #expect(ItemGlyph(category: .other).color == nil)
    }

    @Test("A habit keeps its own icon and colour, and has no category name to read")
    func habitGlyph() {
        let glyph = ItemGlyph(habitIcon: "book.fill", color: .purple)
        #expect(glyph.symbolName == "book.fill")
        #expect(glyph.color == .purple)
        #expect(glyph.categoryName == nil)
    }
}
