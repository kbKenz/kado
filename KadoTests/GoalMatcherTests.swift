import Foundation
import Testing
@testable import KadoCore

@Suite("Goal matcher")
struct GoalMatcherTests {
    private let cambridge = GoalCandidate(id: UUID(), name: "Get into Cambridge")
    private let marathon = GoalCandidate(id: UUID(), name: "Run a marathon")

    @Test("A title that names the goal's place gets that goal")
    func cambridgeExamples() {
        let goals = [cambridge, marathon]
        #expect(GoalMatcher.bestGoal(for: "Contact professors at Cambridge", among: goals) == cambridge.id)
        #expect(GoalMatcher.bestGoal(for: "Email Cambridge admissions", among: goals) == cambridge.id)
        #expect(GoalMatcher.bestGoal(for: "Train for the marathon", among: goals) == marathon.id)
    }

    @Test("No shared word, no goal")
    func noMatch() {
        #expect(GoalMatcher.bestGoal(for: "Buy milk", among: [cambridge, marathon]) == nil)
        #expect(GoalMatcher.bestGoal(for: "", among: [cambridge, marathon]) == nil)
        #expect(GoalMatcher.bestGoal(for: "Cambridge", among: []) == nil)
    }

    @Test("A tie for the best score gives no goal")
    func tie() {
        let learn = GoalCandidate(id: UUID(), name: "Learn Spanish")
        let exam = GoalCandidate(id: UUID(), name: "Pass the Spanish exam")
        #expect(GoalMatcher.bestGoal(for: "Spanish vocabulary", among: [learn, exam]) == nil)
        // One more shared word breaks the tie.
        #expect(GoalMatcher.bestGoal(for: "Spanish exam revision", among: [learn, exam]) == exam.id)
    }

    @Test("The goal with the most shared words wins")
    func mostSharedWords() {
        let trip = GoalCandidate(id: UUID(), name: "Japan trip")
        let language = GoalCandidate(id: UUID(), name: "Japanese language exam")
        let title = "Book a Japanese language class"
        #expect(GoalMatcher.bestGoal(for: title, among: [trip, language]) == language.id)
    }

    @Test("Case and accents are ignored")
    func folding() {
        let school = GoalCandidate(id: UUID(), name: "Entrer à l'école")
        #expect(GoalMatcher.bestGoal(for: "Réviser pour l'ÉCOLE", among: [school, marathon]) == school.id)
        #expect(GoalMatcher.bestGoal(for: "visit CAMBRIDGE", among: [cambridge, marathon]) == cambridge.id)
    }

    @Test("A plural matches its singular, both ways")
    func plurals() {
        let thesis = GoalCandidate(id: UUID(), name: "Finish my chapters")
        #expect(GoalMatcher.bestGoal(for: "Draft chapter two", among: [thesis]) == thesis.id)
        #expect(GoalMatcher.bestGoal(for: "Marathons in spring", among: [cambridge, marathon]) == marathon.id)
        let notes = GoalCandidate(id: UUID(), name: "Class notes")
        #expect(GoalMatcher.bestGoal(for: "Read about classes", among: [notes]) == notes.id)
    }

    @Test("Common words and words under 4 letters never link a title to a goal")
    func stopWords() {
        let english = GoalCandidate(id: UUID(), name: "Make time for the family")
        #expect(GoalMatcher.bestGoal(for: "Make a list for the trip", among: [english]) == nil)
        let french = GoalCandidate(id: UUID(), name: "Faire plus de sport avec mes amis")
        #expect(GoalMatcher.bestGoal(for: "Faire plus de courses avec mes enfants", among: [french]) == nil)
        // "Run" has 3 letters: too short to link.
        #expect(GoalMatcher.bestGoal(for: "Run", among: [marathon]) == nil)
        #expect(GoalMatcher.significantWords("Get into Cambridge") == ["cambridge"])
    }

    @Test("Only whole words are shared")
    func wholeWords() {
        let art = GoalCandidate(id: UUID(), name: "Start painting")
        #expect(GoalMatcher.bestGoal(for: "Paint the fence", among: [art]) == nil)
        #expect(GoalMatcher.bestGoal(for: "Painting class", among: [art]) == art.id)
    }
}
