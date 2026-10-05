import Foundation
import Testing
@testable import KadoCore

@Suite("Category classifier")
struct CategoryClassifierTests {
    /// The required examples: a title and its category.
    static let requiredExamples: [(String, ItemCategory)] = [
        ("Contact professors at Cambridge", .study),
        ("Run 5k", .fitness),
        ("Méditer 10 minutes", .mind),
        ("Pay rent", .money),
        ("Buy groceries", .errands),
        ("Call mom", .social),
        ("Go to bed by 11", .sleep),
        ("Clean the kitchen", .home),
        ("Guitar practice", .creative),
        ("Prepare slides for the meeting", .work),
        ("Take vitamins", .health),
        ("Réviser l'examen de maths", .study),
        ("Faire les courses", .errands)
    ]

    @Test("Titles in English and French get their category", arguments: requiredExamples)
    func examples(title: String, expected: ItemCategory) {
        #expect(CategoryClassifier.classify(title) == expected)
    }

    @Test("No keyword, no category", arguments: ["zzz qwerty", "", "   ", "42", "Get into Cambridge"])
    func noMatch(title: String) {
        #expect(CategoryClassifier.classify(title) == nil)
    }

    @Test("Case and accents are ignored")
    func foldsCaseAndAccents() {
        #expect(CategoryClassifier.classify("MÉDITER") == .mind)
        #expect(CategoryClassifier.classify("mediter") == .mind)
        #expect(CategoryClassifier.classify("RÉVISER") == .study)
        #expect(CategoryClassifier.classify("PAY RENT") == .money)
    }

    @Test("Only whole words match")
    func wholeWords() {
        // "run" inside "runway", "rent" inside "parents", "gym" inside "gymnastics".
        #expect(CategoryClassifier.classify("Runway") == nil)
        #expect(CategoryClassifier.classify("Gymnastics") == nil)
        #expect(CategoryClassifier.classify("Apparent") == nil)
        // Punctuation and digits split words.
        #expect(CategoryClassifier.classify("run,5k") == .fitness)
        #expect(CategoryClassifier.classify("Réviser l’examen") == .study)
    }

    @Test("A trailing s or es is dropped to find the keyword")
    func plurals() {
        #expect(CategoryClassifier.classify("Professors") == .study)
        #expect(CategoryClassifier.classify("Pay bills") == .money)
        #expect(CategoryClassifier.classify("Taxes") == .money)
        #expect(CategoryClassifier.classify("Classes") == .study)
        #expect(CategoryClassifier.classify("Arroser les plantes") == .home)
    }

    @Test("A word that is a keyword as written is not read as a plural")
    func exactWordsWin() {
        // "courses" (French shopping) is a keyword; it must not also
        // count as "course" or "cours" (a class).
        #expect(CategoryClassifier.classify("Courses") == .errands)
        #expect(CategoryClassifier.classify("Online course") == .study)
        #expect(CategoryClassifier.classify("Aller en cours") == .study)
    }

    @Test("Phrases match consecutive words")
    func phrases() {
        #expect(CategoryClassifier.classify("Lights out") == .sleep)
        #expect(CategoryClassifier.classify("Self-care Sunday") == .mind)
        #expect(CategoryClassifier.classify("Faire des courses") == .errands)
        // The same words, not next to each other, are not the phrase.
        #expect(CategoryClassifier.classify("Out of lights") == nil)
    }

    @Test("The category whose keywords cover the most words wins")
    func mostWords() {
        // Fitness covers one word ("run"); study covers two ("study", "exam").
        #expect(CategoryClassifier.classify("Run then study for the exam") == .study)
        // Work covers two words ("slides", "meeting"); creative one ("write").
        #expect(CategoryClassifier.classify("Write slides for the meeting") == .work)
        // A phrase covers each of its words: "post office" (errands, two
        // words) beats "office" (work, one word).
        #expect(CategoryClassifier.classify("Post office") == .errands)
        #expect(CategoryClassifier.classify("Course à pied") == .fitness)
        #expect(CategoryClassifier.classify("Mental health day") == .mind)
        // "water the plants" (home) beats "water" (health).
        #expect(CategoryClassifier.classify("Water the plants") == .home)
    }

    @Test("A tie goes to the earlier category in the priority order")
    func tieBreak() {
        // One hit each: fitness ("run") and sleep ("bed").
        #expect(CategoryClassifier.classify("Run before bed") == .fitness)
        // One hit each: health ("doctor") and errands ("appointment").
        #expect(CategoryClassifier.classify("Doctor appointment") == .health)
        // One hit each: work ("report") and creative ("write").
        #expect(CategoryClassifier.classify("Write report") == .work)
        #expect(CategoryClassifier.priority == [
            .fitness, .sleep, .health, .mind, .study, .work,
            .money, .home, .errands, .social, .creative
        ])
    }

    @Test("The classifier never answers Other")
    func neverOther() {
        let titles = ["Other", "Autre", "Something else", "Misc", "zzz"]
            + CategoryClassifier.english.values.flatMap { $0 }
            + CategoryClassifier.french.values.flatMap { $0 }
        for title in titles {
            #expect(CategoryClassifier.classify(title) != .other, "\(title)")
        }
    }

    @Test("Every keyword alone classifies as its own category")
    func everyKeywordWorks() {
        for list in [CategoryClassifier.english, CategoryClassifier.french] {
            for (category, entries) in list {
                for entry in entries {
                    #expect(CategoryClassifier.classify(entry) == category, "\(entry)")
                }
            }
        }
    }

    @Test("Each category has at least 15 English and 15 French keywords; Other has none")
    func listSizes() {
        for category in ItemCategory.allCases where category != .other {
            #expect((CategoryClassifier.english[category]?.count ?? 0) >= 15, "\(category) in English")
            #expect((CategoryClassifier.french[category]?.count ?? 0) >= 15, "\(category) in French")
        }
        #expect(CategoryClassifier.english[.other] == nil)
        #expect(CategoryClassifier.french[.other] == nil)
    }

    @Test("After folding, a keyword belongs to one category only and appears once per list")
    func keywordsAreUnique() {
        var owners: [String: ItemCategory] = [:]
        for list in [CategoryClassifier.english, CategoryClassifier.french] {
            for (category, entries) in list {
                let folded = entries.map { TitleText.words($0).joined(separator: " ") }
                #expect(Set(folded).count == folded.count, "\(category) repeats a keyword")
                for (entry, key) in zip(entries, folded) {
                    #expect(!key.isEmpty, "\(entry) has no letters")
                    if let owner = owners[key] {
                        #expect(owner == category, "\(entry) is in \(owner) and \(category)")
                    }
                    owners[key] = category
                }
            }
        }
    }
}
