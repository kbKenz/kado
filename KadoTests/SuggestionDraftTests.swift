import Foundation
import Testing
@testable import Kado
import KadoCore

/// The ownership rules of title suggestions: what the app may fill in,
/// what it may only offer, and what it never touches again.
@MainActor
@Suite("SuggestionDraft")
struct SuggestionDraftTests {
    let cambridge = SuggestionGoal(name: "Get into Cambridge", updatedAt: .now)
    let marathon = SuggestionGoal(name: "Run a marathon", category: .fitness)
    let ielts = SuggestionGoal(name: "Move abroad", details: "Pass the IELTS with a good score")
    let thesis = SuggestionGoal(name: "Finish the thesis", category: .study)
    let paused = SuggestionGoal(name: "Learn Spanish", isActive: false)

    var goals: [SuggestionGoal] { [cambridge, marathon, ielts, thesis, paused] }

    // MARK: - Word tier, new items

    @Test("A typed title with typos fills the category and a strongly matched goal")
    func cambridgeExample() {
        let draft = SuggestionDraft(kind: .task)
        draft.applyWords(title: "contact proffesors at cambrrdgige", goals: goals)
        #expect(draft.goalID == cambridge.id)
        #expect(draft.goalOrigin == .suggested)
        #expect(draft.category == .study)
        #expect(draft.categoryOrigin == .suggested)
        #expect(draft.chips == [
            SuggestionChip(value: .category(.study), isApplied: true),
            SuggestionChip(value: .goal(cambridge.id), isApplied: true)
        ])
        #expect(draft.canUndo)
    }

    @Test("A weak goal match is offered, never applied; a tap applies it as the person's choice")
    func weakMatchIsOffered() throws {
        let draft = SuggestionDraft(kind: .task)
        draft.applyWords(title: "Book the IELTS", goals: goals)
        #expect(draft.goalID == nil)
        #expect(draft.goalOrigin == .default)
        let chip = try #require(draft.chips.first { $0.field == .goal })
        #expect(chip == SuggestionChip(value: .goal(ielts.id), isApplied: false))
        draft.accept(chip)
        #expect(draft.goalID == ielts.id)
        #expect(draft.goalOrigin == .user)
        #expect(!draft.chips.contains { $0.field == .goal })
    }

    @Test("A new strong match replaces a suggested goal; no match puts the defaults back")
    func suggestionsFollowTheTitle() {
        let draft = SuggestionDraft(kind: .task)
        draft.applyWords(title: "Email Cambridge", goals: goals)
        #expect(draft.goalID == cambridge.id)
        draft.applyWords(title: "Marathon training plan", goals: goals)
        #expect(draft.goalID == marathon.id)
        #expect(draft.goalOrigin == .suggested)
        draft.applyWords(title: "zzz qwerty", goals: goals)
        #expect(draft.goalID == nil)
        #expect(draft.goalOrigin == .default)
        #expect(draft.category == nil)
        #expect(draft.categoryOrigin == .default)
        #expect(draft.chips.isEmpty)
    }

    @Test("A cleared title puts every suggested field back to its default")
    func clearedTitle() {
        let task = SuggestionDraft(kind: .task)
        task.applyWords(title: "contact proffesors at cambrrdgige", goals: goals)
        task.applyWords(title: "   ", goals: goals)
        #expect(task.goalID == nil)
        #expect(task.goalOrigin == .default)
        #expect(task.category == nil)
        #expect(task.categoryOrigin == .default)
        #expect(task.chips.isEmpty)

        let habit = SuggestionDraft(kind: .habit)
        habit.applyWords(title: "Morning run", goals: [])
        #expect(habit.icon == "figure.run")
        habit.applyWords(title: "", goals: [])
        #expect(habit.icon == HabitIcon.default)
        #expect(habit.iconOrigin == .default)
        #expect(habit.color == SuggestionDraft.defaultColor)
        #expect(habit.colorOrigin == .default)
        #expect(habit.category == nil)
    }

    @Test("Inactive goals are never suggested")
    func inactiveGoals() {
        let draft = SuggestionDraft(kind: .task)
        draft.applyWords(title: "Spanish vocabulary", goals: goals)
        #expect(draft.goalID == nil)
        #expect(!draft.chips.contains { $0.field == .goal })
    }

    // MARK: - The person's changes

    @Test("Any change by the person locks the field, even back to No goal or None")
    func userChangesLock() {
        let draft = SuggestionDraft(kind: .task)
        draft.applyWords(title: "Email Cambridge", goals: goals)
        draft.userSetGoal(nil)
        #expect(draft.goalOrigin == .user)
        draft.applyWords(title: "Email Cambridge admissions", goals: goals)
        #expect(draft.goalID == nil)
        #expect(!draft.chips.contains { $0.field == .goal })

        draft.userSetCategory(nil)
        draft.applyWords(title: "Study for the exam", goals: goals)
        #expect(draft.category == nil)
        #expect(draft.categoryOrigin == .user)

        let other = SuggestionDraft(kind: .task)
        other.userSetCategory(.work)
        other.applyWords(title: "Study for the exam", goals: goals)
        #expect(other.category == .work)
    }

    @Test("Choosing the circle icon locks the icon too")
    func circleIconLocks() {
        let draft = SuggestionDraft(kind: .habit)
        draft.userSetIcon(HabitIcon.default)
        draft.applyWords(title: "Read 20 pages", goals: [])
        #expect(draft.icon == HabitIcon.default)
        #expect(draft.iconOrigin == .user)
        #expect(!draft.chips.contains { $0.field == .icon })
    }

    @Test("A task's category follows its goal's own category, unless the person chose one")
    func taskFollowsGoalCategory() {
        let draft = SuggestionDraft(kind: .task)
        draft.applyWords(title: "Draft chapter two", goals: goals)
        draft.userSetGoal(marathon.id)
        #expect(draft.category == .fitness)
        #expect(draft.categoryOrigin == .suggested)
        // A suggested goal carries its category over the keywords
        // ("report" and "meeting" are work words).
        let suggested = SuggestionDraft(kind: .task)
        suggested.applyWords(title: "Thesis report meeting", goals: goals)
        #expect(suggested.goalID == thesis.id)
        #expect(suggested.category == .study)
        // A goal without a category leaves the keyword category.
        suggested.userSetGoal(cambridge.id)
        #expect(suggested.category == .work)
        // The person's category never follows.
        let chosen = SuggestionDraft(kind: .task)
        chosen.applyWords(title: "", goals: goals)
        chosen.userSetCategory(.money)
        chosen.userSetGoal(marathon.id)
        #expect(chosen.category == .money)
    }

    @Test("Habits do not follow the goal's category")
    func habitsKeepTheirCategory() {
        let draft = SuggestionDraft(kind: .habit)
        draft.applyWords(title: "", goals: goals)
        draft.userSetGoal(marathon.id)
        #expect(draft.category == nil)
    }

    @Test("A form opened from a goal keeps that goal as the person's choice")
    func presetGoal() {
        let draft = SuggestionDraft(kind: .task)
        draft.presetGoal(thesis.id)
        draft.applyWords(title: "", goals: goals)
        #expect(draft.goalOrigin == .user)
        #expect(draft.category == .study)
        draft.applyWords(title: "Email Cambridge", goals: goals)
        #expect(draft.goalID == thesis.id)
        #expect(draft.category == .study)
        #expect(!draft.chips.contains { $0.field == .goal })
    }

    // MARK: - Habits

    @Test("A habit gets its icon from a keyword, and its colour from its category")
    func habitIconAndColour() {
        let read = SuggestionDraft(kind: .habit)
        read.applyWords(title: "Read 20 pages", goals: [])
        #expect(read.icon == "book.fill")
        #expect(read.iconOrigin == .suggested)
        #expect(read.category == nil)
        #expect(read.color == SuggestionDraft.defaultColor)
        #expect(read.colorOrigin == .default)

        let run = SuggestionDraft(kind: .habit)
        run.applyWords(title: "Morning run", goals: [])
        #expect(run.icon == "figure.run")
        #expect(run.category == .fitness)
        #expect(run.color == .orange)
        #expect(run.colorOrigin == .suggested)
        #expect(run.chips.map(\.field) == [.category, .icon, .color])
    }

    @Test("Without a keyword icon, a habit takes its category's icon, even a chosen category")
    func iconFallsBackToCategory() {
        let rent = SuggestionDraft(kind: .habit)
        rent.applyWords(title: "Pay rent", goals: [])
        #expect(rent.category == .money)
        #expect(rent.icon == "creditcard.fill")
        #expect(rent.color == .green)

        let chosen = SuggestionDraft(kind: .habit)
        chosen.userSetCategory(.sleep)
        #expect(chosen.icon == "bed.double.fill")
        #expect(chosen.iconOrigin == .suggested)
        #expect(chosen.color == .teal)
        chosen.userSetColor(.red)
        chosen.userSetCategory(.study)
        #expect(chosen.icon == "graduationcap.fill")
        #expect(chosen.color == .red)
    }

    // MARK: - Undo

    @Test("Undo puts every applied field back to its default and locks it")
    func undo() {
        let draft = SuggestionDraft(kind: .habit)
        draft.applyWords(title: "Run the marathon", goals: [marathon])
        #expect(draft.goalID == marathon.id)
        #expect(draft.category == .fitness)
        #expect(draft.icon == "figure.run")
        draft.undo()
        #expect(draft.category == nil)
        #expect(draft.goalID == nil)
        #expect(draft.icon == HabitIcon.default)
        #expect(draft.color == SuggestionDraft.defaultColor)
        #expect([draft.categoryOrigin, draft.goalOrigin, draft.iconOrigin, draft.colorOrigin] == [.user, .user, .user, .user])
        #expect(!draft.canUndo)
        #expect(draft.chips.isEmpty)
        draft.applyWords(title: "Run the marathon again", goals: [marathon])
        #expect(draft.category == nil)
        #expect(draft.goalID == nil)
        #expect(draft.chips.isEmpty)
    }

    @Test("Undo leaves the person's own choices alone")
    func undoKeepsUserValues() {
        let draft = SuggestionDraft(kind: .task)
        draft.userSetCategory(.work)
        draft.applyWords(title: "Email Cambridge", goals: goals)
        draft.undo()
        #expect(draft.category == .work)
        #expect(draft.goalID == nil)
    }

    // MARK: - Edit forms

    @Test("An edit form never applies anything; it offers chips for empty fields")
    func editFormOffersOnly() {
        let draft = SuggestionDraft(kind: .task, isEditing: true)
        draft.load(category: nil, goalID: nil)
        draft.applyWords(title: "contact proffesors at cambrrdgige", goals: goals)
        #expect(draft.category == nil)
        #expect(draft.goalID == nil)
        #expect(draft.chips == [
            SuggestionChip(value: .category(.study), isApplied: false),
            SuggestionChip(value: .goal(cambridge.id), isApplied: false)
        ])
        #expect(!draft.canUndo)
        #expect(draft.takeAnnouncement() == nil)
    }

    @Test("An edit form offers the resolved category: the goal's first, never Other")
    func editFormResolvesCategory() {
        let draft = SuggestionDraft(kind: .task, isEditing: true)
        draft.load(category: nil, goalID: marathon.id)
        draft.applyWords(title: "Study for the exam", goals: goals)
        #expect(draft.chips == [SuggestionChip(value: .category(.fitness), isApplied: false)])

        let nothing = SuggestionDraft(kind: .task, isEditing: true)
        nothing.load(category: nil, goalID: nil)
        nothing.applyWords(title: "zzz qwerty", goals: goals)
        #expect(nothing.chips.isEmpty)
    }

    @Test("Saved values are the person's: no chips for them")
    func editFormKeepsSavedValues() {
        let draft = SuggestionDraft(kind: .habit, isEditing: true)
        draft.load(category: .work, goalID: thesis.id, icon: "star.fill", color: .red)
        draft.applyWords(title: "Morning run", goals: goals)
        #expect(draft.category == .work)
        #expect(draft.goalID == thesis.id)
        #expect(draft.icon == "star.fill")
        #expect(draft.color == .red)
        #expect(draft.chips.isEmpty)

        let circle = SuggestionDraft(kind: .habit, isEditing: true)
        circle.load(category: nil, goalID: nil, icon: HabitIcon.default, color: .blue)
        circle.applyWords(title: "Read 20 pages", goals: [])
        #expect(circle.icon == HabitIcon.default)
        #expect(circle.chips == [SuggestionChip(value: .icon("book.fill"), isApplied: false)])
        circle.accept(circle.chips[0])
        #expect(circle.icon == "book.fill")
        #expect(circle.iconOrigin == .user)
    }

    // MARK: - Model tier

    @Test("The model fills an empty category and icon, and only offers its goal")
    func modelFillsWhatWordsLeft() {
        let draft = SuggestionDraft(kind: .habit)
        draft.applyWords(title: "IELTS lessons", goals: [cambridge])
        #expect(draft.category == .study)
        #expect(draft.icon == "graduationcap.fill")
        #expect(draft.wantsModel)
        draft.applyModel(ModelItemSuggestion(category: .work, goalID: cambridge.id, icon: "star.fill"), for: "IELTS lessons")
        // The words' category stays; the model's icon fills the empty one.
        #expect(draft.category == .study)
        #expect(draft.icon == "star.fill")
        #expect(draft.iconOrigin == .suggested)
        #expect(draft.goalID == nil)
        #expect(draft.chips.contains(SuggestionChip(value: .goal(cambridge.id), isApplied: false)))
    }

    @Test("The model's category fills an untouched, empty category")
    func modelCategory() {
        let draft = SuggestionDraft(kind: .task)
        draft.applyWords(title: "Book IELTS test", goals: goals)
        #expect(draft.category == nil)
        draft.applyModel(ModelItemSuggestion(category: .study), for: "Book IELTS test")
        #expect(draft.category == .study)
        #expect(draft.categoryOrigin == .suggested)
    }

    @Test("A model answer for an old title is dropped")
    func staleModelAnswer() {
        let draft = SuggestionDraft(kind: .task)
        draft.applyWords(title: "Book IELTS test", goals: goals)
        draft.applyWords(title: "Book IELTS test now", goals: goals)
        draft.applyModel(ModelItemSuggestion(category: .study), for: "Book IELTS test")
        #expect(draft.category == nil)
        // And the next title drops an answer that was applied.
        draft.applyModel(ModelItemSuggestion(category: .study), for: "Book IELTS test now")
        #expect(draft.category == .study)
        draft.applyWords(title: "Book IELTS test now please", goals: goals)
        #expect(draft.category == nil)
    }

    @Test("A model goal that is also a strong word match stays applied, with no chip")
    func modelGoalMatchesWords() {
        let draft = SuggestionDraft(kind: .task)
        draft.applyWords(title: "Email Cambridge", goals: goals)
        draft.applyModel(ModelItemSuggestion(goalID: cambridge.id), for: "Email Cambridge")
        #expect(draft.goalID == cambridge.id)
        #expect(draft.chips.filter { $0.field == .goal } == [SuggestionChip(value: .goal(cambridge.id), isApplied: true)])
    }

    @Test("The model is asked only when the words left a field empty")
    func wantsModel() {
        let full = SuggestionDraft(kind: .task)
        full.applyWords(title: "Thesis meeting", goals: goals)
        #expect(full.category != nil && full.goalID != nil)
        #expect(!full.wantsModel)

        let empty = SuggestionDraft(kind: .task)
        empty.applyWords(title: "Book IELTS test", goals: goals)
        #expect(empty.wantsModel)

        // No word of 4 letters or more: nothing to ask about.
        let short = SuggestionDraft(kind: .task)
        short.applyWords(title: "Do it", goals: goals)
        #expect(!short.wantsModel)

        let locked = SuggestionDraft(kind: .goal)
        locked.userSetCategory(nil)
        locked.applyWords(title: "Get into Cambridge", goals: [])
        #expect(!locked.wantsModel)
    }

    // MARK: - Saving and VoiceOver

    @Test("While frozen for a save, nothing changes")
    func freeze() {
        let draft = SuggestionDraft(kind: .task)
        draft.freeze()
        draft.applyWords(title: "Email Cambridge", goals: goals)
        #expect(draft.goalID == nil)
        #expect(!draft.wantsModel)
        draft.thaw()
        draft.applyWords(title: "Email Cambridge", goals: goals)
        #expect(draft.goalID == cambridge.id)
        draft.applyWords(title: "Book IELTS test", goals: goals)
        #expect(draft.category == nil)
        draft.freeze()
        draft.applyModel(ModelItemSuggestion(category: .study), for: "Book IELTS test")
        #expect(draft.category == nil)
    }

    @Test("One announcement for each newly applied set")
    func announcements() throws {
        let draft = SuggestionDraft(kind: .task)
        draft.applyWords(title: "Email Cambridge", goals: goals)
        let first = try #require(draft.takeAnnouncement())
        #expect(first.contains("Get into Cambridge"))
        #expect(first.hasSuffix("Undo is available."))
        #expect(draft.takeAnnouncement() == nil)
        // The same set again: nothing new to say.
        draft.applyWords(title: "Email Cambridge today", goals: goals)
        #expect(draft.takeAnnouncement() == nil)
        // A new value joins the set.
        draft.applyWords(title: "Email Cambridge about the exam", goals: goals)
        let second = try #require(draft.takeAnnouncement())
        #expect(second.contains("Study"))
        // Losing a value is not announced.
        draft.applyWords(title: "Cambridge", goals: goals)
        #expect(draft.category == nil)
        #expect(draft.takeAnnouncement() == nil)
    }

    @Test("A goal form suggests only a category")
    func goalForm() {
        let draft = SuggestionDraft(kind: .goal)
        draft.applyWords(title: "Run a marathon", goals: goals)
        #expect(draft.category == .fitness)
        #expect(draft.goalID == nil)
        #expect(draft.icon == HabitIcon.default)
        #expect(draft.chips == [SuggestionChip(value: .category(.fitness), isApplied: true)])
    }
}
