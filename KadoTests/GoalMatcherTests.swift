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

    @Test("A typed title with typos still finds the goal, as a strong match")
    func typoTolerance() {
        let goals = [cambridge, marathon]
        let typed = GoalMatcher.match("contact proffesors at cambrrdgige", among: goals)
        #expect(typed == GoalMatch(goalID: cambridge.id, isStrong: true))
        let clean = GoalMatcher.match("Contact professors at Cambridge", among: goals)
        #expect(clean == GoalMatch(goalID: cambridge.id, isStrong: true))
        // "cambrrdgige" is 3 edits from "cambridge"; 9 letters allow 3.
        #expect(GoalMatcher.matches("cambrrdgige", "cambridge"))
        #expect(TitleText.editDistance("cambrrdgige", "cambridge") == 3)
    }

    @Test("Words must start with the same letter to be a typo of each other")
    func firstLetterRule() {
        let japan = GoalCandidate(id: UUID(), name: "Heading to Japan")
        #expect(GoalMatcher.match("Reading list", among: [japan]) == nil)
        #expect(!GoalMatcher.matches("reading", "heading"))
    }

    @Test("The allowance grows with the shorter word: none under 5 letters, 1 up to 7, a third from 8")
    func allowance() {
        // Under 5 letters: equal only.
        #expect(!GoalMatcher.matches("book", "boot"))
        #expect(GoalMatcher.matches("book", "book"))
        // 5 to 7 letters: one edit.
        #expect(GoalMatcher.matches("spanish", "spansh"))
        #expect(!GoalMatcher.matches("spanish", "spnsh"))
        // A swap of two letters is one edit (optimal string alignment).
        #expect(GoalMatcher.matches("thesis", "tehsis"))
        #expect(GoalMatcher.matches("french", "frnech"))
        // 8 letters and more: a third of the shorter word, rounded down.
        #expect(GoalMatcher.matches("marathon", "marahtno"))
        #expect(!GoalMatcher.matches("marathon", "mxrxthxx"))
    }

    @Test("A prefix counts from 5 letters on the shorter word")
    func prefixRule() {
        #expect(GoalMatcher.matches("professor", "professors"))
        #expect(GoalMatcher.matches("paint", "painting"))
        // "pain" is a prefix of "painting" but has only 4 letters.
        #expect(!GoalMatcher.matches("pain", "painting"))
        let art = GoalCandidate(id: UUID(), name: "Start painting")
        #expect(GoalMatcher.bestGoal(for: "Paint the fence", among: [art]) == art.id)
        #expect(GoalMatcher.bestGoal(for: "Pain relief", among: [art]) == nil)
    }

    @Test("A word that two goals share never decides")
    func sharedWords() {
        let visit = GoalCandidate(id: UUID(), name: "Visit Cambridge friends")
        #expect(GoalMatcher.match("Contact professors at Cambridge", among: [cambridge, visit]) == nil)
        // A typo of the shared word does not decide either.
        #expect(GoalMatcher.match("Cambrige trip", among: [cambridge, visit]) == nil)
        // Another word can still decide.
        #expect(GoalMatcher.match("Call Cambridge friends", among: [cambridge, visit])?.goalID == visit.id)
    }

    @Test("A tie for the best score gives no goal")
    func tie() {
        let learn = GoalCandidate(id: UUID(), name: "Learn Spanish")
        let exam = GoalCandidate(id: UUID(), name: "Pass the Spanish exam")
        #expect(GoalMatcher.bestGoal(for: "Spanish vocabulary", among: [learn, exam]) == nil)
        // One more shared word breaks the tie.
        #expect(GoalMatcher.bestGoal(for: "Spanish exam revision", among: [learn, exam]) == exam.id)
        let guitar = GoalCandidate(id: UUID(), name: "Guitar practice")
        let piano = GoalCandidate(id: UUID(), name: "Piano lessons")
        #expect(GoalMatcher.match("Guitar and piano", among: [guitar, piano]) == nil)
    }

    @Test("Name words weigh 2 and details words 1; a details-only match is weak")
    func weights() {
        let ielts = GoalCandidate(id: UUID(), name: "Move abroad", details: "Pass the IELTS with a 7.5 score")
        let weak = GoalMatcher.match("Book the IELTS", among: [ielts, marathon])
        #expect(weak == GoalMatch(goalID: ielts.id, isStrong: false))
        #expect(GoalMatcher.bestGoal(for: "Book the IELTS", among: [ielts, marathon]) == nil)
        // A name word (2) beats a details word (1).
        let thesis = GoalCandidate(id: UUID(), name: "Finish the thesis")
        let writing = GoalCandidate(id: UUID(), name: "Daily writing", details: "Two chapters a week")
        #expect(GoalMatcher.match("Thesis chapters", among: [thesis, writing]) == GoalMatch(goalID: thesis.id, isStrong: true))
        // A word shared between one goal's details and another's name
        // decides for neither.
        let journal = GoalCandidate(id: UUID(), name: "Journal more", details: "Morning pages")
        let review = GoalCandidate(id: UUID(), name: "Morning routine")
        #expect(GoalMatcher.match("Morning pages", among: [journal, review]) == GoalMatch(goalID: journal.id, isStrong: false))
    }

    @Test("A word in both the name and the details counts once, at the name's weight")
    func countsOnce() {
        let goal = GoalCandidate(id: UUID(), name: "Cambridge", details: "Cambridge, Cambridge")
        let other = GoalCandidate(id: UUID(), name: "Learn Spanish", details: "Spanish exam")
        // cambridge: 2. spanish (2) + exam (1) = 3 for the other goal.
        #expect(GoalMatcher.match("Cambridge Spanish exam", among: [goal, other])?.goalID == other.id)
    }

    @Test("No shared word, no goal")
    func noMatch() {
        #expect(GoalMatcher.bestGoal(for: "Buy milk", among: [cambridge, marathon]) == nil)
        #expect(GoalMatcher.bestGoal(for: "", among: [cambridge, marathon]) == nil)
        #expect(GoalMatcher.bestGoal(for: "Cambridge", among: []) == nil)
        #expect(GoalMatcher.match("", among: [cambridge]) == nil)
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
        // "thèse" folds to "these", which must not be read as the
        // English word.
        let these = GoalCandidate(id: UUID(), name: "Finir ma these")
        #expect(GoalMatcher.match("Réviser la thèse", among: [these, marathon]) == GoalMatch(goalID: these.id, isStrong: true))
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

    @Test("The edit distance counts insertions, deletions, substitutions and swaps")
    func editDistance() {
        #expect(TitleText.editDistance("", "") == 0)
        #expect(TitleText.editDistance("abc", "") == 3)
        #expect(TitleText.editDistance("kitten", "sitting") == 3)
        #expect(TitleText.editDistance("ab", "ba") == 1)
        #expect(TitleText.editDistance("ca", "abc") == 3)
        #expect(TitleText.editDistance("proffesor", "professor") == 2)
    }
}
