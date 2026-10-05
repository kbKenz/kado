import Foundation
import Testing
@testable import KadoCore

@Suite("Habit icon suggester")
struct HabitIconSuggesterTests {
    /// Titles and the icon each one gets.
    static let keywordExamples: [(String, String)] = [
        ("Read 20 pages", "book.fill"), ("Lire un livre", "book.fill"),
        ("Drink water", "drop.fill"), ("Boire de l'eau", "drop.fill"),
        ("Evening walk", "figure.walk"), ("Marche", "figure.walk"),
        ("Morning run", "figure.run"), ("Jog", "figure.run"), ("Courir", "figure.run"),
        ("Gym", "dumbbell.fill"), ("Lift weights", "dumbbell.fill"), ("Muscu", "dumbbell.fill"),
        ("Yoga", "figure.yoga"),
        ("Bike to work", "bicycle"), ("Cycle", "bicycle"), ("Vélo", "bicycle"),
        ("Swim", "figure.pool.swim"), ("Nager", "figure.pool.swim"), ("Piscine", "figure.pool.swim"),
        ("Meditate", "figure.mind.and.body"), ("Breathe", "figure.mind.and.body"), ("Méditer", "figure.mind.and.body"),
        ("Sleep 8 hours", "bed.double.fill"), ("Bed by 11", "bed.double.fill"),
        ("Dormir", "bed.double.fill"), ("Se coucher tôt", "bed.double.fill"),
        ("Morning coffee", "cup.and.saucer.fill"), ("Green tea", "cup.and.saucer.fill"),
        ("Café", "cup.and.saucer.fill"), ("Thé vert", "cup.and.saucer.fill"),
        ("Cook at home", "fork.knife"), ("Eat slowly", "fork.knife"), ("Meal prep", "fork.knife"),
        ("Manger lentement", "fork.knife"), ("Cuisiner", "fork.knife"), ("Repas en famille", "fork.knife"),
        ("Vegetables", "carrot.fill"), ("Fruit", "carrot.fill"), ("Légumes", "carrot.fill"),
        ("Write 500 words", "pencil"), ("Journal", "pencil"), ("Écrire", "pencil"),
        ("Music", "music.note"), ("Guitar", "music.note"), ("Piano", "music.note"), ("Musique", "music.note"),
        ("Draw", "paintbrush.fill"), ("Paint", "paintbrush.fill"), ("Dessiner", "paintbrush.fill"), ("Peindre", "paintbrush.fill"),
        ("Photo a day", "camera.fill"),
        ("Take vitamins", "pills.fill"), ("Pill", "pills.fill"), ("Medicine", "pills.fill"), ("Médicament", "pills.fill"),
        ("Call mom", "phone.fill"), ("Phone a friend", "phone.fill"), ("Appeler papa", "phone.fill"),
        ("Code", "laptopcomputer"), ("Laptop off", "laptopcomputer"), ("Ordinateur", "laptopcomputer"),
        ("Clean the kitchen", "house.fill"), ("Tidy up", "house.fill"), ("Ménage", "house.fill"), ("Ranger", "house.fill")
    ]

    @Test("A keyword in English or French picks its icon", arguments: keywordExamples)
    func keywordIcons(title: String, icon: String) {
        #expect(HabitIconSuggester.icon(for: title, category: nil) == icon)
    }

    @Test("Without a keyword, the category's default icon")
    func categoryFallback() {
        #expect(HabitIconSuggester.icon(for: "Pay rent", category: .money) == "creditcard.fill")
        #expect(HabitIconSuggester.icon(for: "Do the dishes", category: .home) == "house.fill")
        #expect(HabitIconSuggester.icon(for: "", category: .study) == "graduationcap.fill")
        // A keyword wins over the category.
        #expect(HabitIconSuggester.icon(for: "Read", category: .money) == "book.fill")
    }

    @Test("No keyword and no category default, no icon")
    func noIcon() {
        #expect(HabitIconSuggester.icon(for: "zzz qwerty", category: nil) == nil)
        #expect(HabitIconSuggester.icon(for: "zzz qwerty", category: .other) == nil)
        #expect(HabitIconSuggester.icon(for: "", category: nil) == nil)
    }

    @Test("Only whole words match, after folding case and accents")
    func wholeWordsAndFolding() {
        #expect(HabitIconSuggester.icon(for: "Bread", category: nil) == nil)
        #expect(HabitIconSuggester.icon(for: "Runway", category: nil) == nil)
        #expect(HabitIconSuggester.icon(for: "MEDITER", category: nil) == "figure.mind.and.body")
        #expect(HabitIconSuggester.icon(for: "velo", category: nil) == "bicycle")
        #expect(HabitIconSuggester.icon(for: "Books", category: nil) == "book.fill")
    }

    @Test("\"thé\" needs its accent, so the English \"the\" is not tea")
    func theIsNotTea() {
        #expect(HabitIconSuggester.icon(for: "Do the dishes", category: nil) == nil)
        #expect(HabitIconSuggester.icon(for: "Take the stairs", category: .fitness) == "figure.run")
        #expect(HabitIconSuggester.icon(for: "THÉ", category: nil) == "cup.and.saucer.fill")
    }

    @Test("Specific activities win over generic verbs")
    func ruleOrder() {
        #expect(HabitIconSuggester.icon(for: "Drink coffee", category: nil) == "cup.and.saucer.fill")
        #expect(HabitIconSuggester.icon(for: "Eat vegetables", category: nil) == "carrot.fill")
        #expect(HabitIconSuggester.icon(for: "Read before bed", category: nil) == "book.fill")
        #expect(HabitIconSuggester.icon(for: "No phone in bed", category: nil) == "bed.double.fill")
    }

    @Test("Every icon it can return is in the curated list")
    func iconsAreCurated() {
        for rule in HabitIconSuggester.rules {
            #expect(HabitIcon.curated.contains(rule.icon), "\(rule.icon)")
        }
        for category in ItemCategory.allCases {
            if let icon = category.defaultHabitIcon {
                #expect(HabitIcon.curated.contains(icon), "\(category): \(icon)")
            }
        }
    }

    @Test("A keyword belongs to one icon only")
    func keywordsAreUnique() {
        var owners: [String: String] = [:]
        for rule in HabitIconSuggester.rules {
            for word in rule.words.union(rule.accentedWords) {
                #expect(owners[word] == nil, "\(word) is in \(owners[word] ?? "") and \(rule.icon)")
                owners[word] = rule.icon
            }
        }
    }
}
