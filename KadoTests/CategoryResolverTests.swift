import Foundation
import Testing
@testable import KadoCore

@Suite("Category resolver")
struct CategoryResolverTests {
    @Test("A stored category wins over everything else")
    func storedFirst() {
        #expect(CategoryResolver.resolve(stored: .work, goalCategory: .study, title: "Run 5k") == .work)
        #expect(CategoryResolver.resolve(stored: .other, goalCategory: .study, title: "Run 5k") == .other)
    }

    @Test("Without a stored category, the linked goal's category")
    func goalSecond() {
        #expect(CategoryResolver.resolve(stored: nil, goalCategory: .study, title: "Run 5k") == .study)
    }

    @Test("Without either, the keyword guess from the title")
    func titleThird() {
        #expect(CategoryResolver.resolve(stored: nil, goalCategory: nil, title: "Run 5k") == .fitness)
        #expect(
            CategoryResolver.resolve(stored: nil, goalCategory: nil, title: "Contact professors at Cambridge")
                == CategoryClassifier.classify("Contact professors at Cambridge")
        )
    }

    @Test("With nothing to go on, Other")
    func otherLast() {
        #expect(CategoryResolver.resolve(stored: nil, goalCategory: nil, title: "zzz qwerty") == .other)
        #expect(CategoryResolver.resolve(stored: nil, goalCategory: nil, title: "") == .other)
    }
}
