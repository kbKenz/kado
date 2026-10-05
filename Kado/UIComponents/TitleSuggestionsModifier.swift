import KadoCore
import SwiftUI

extension View {
    /// Runs title suggestions for a form: the word tier 300 ms after the
    /// last keystroke (at once on Return or for an empty title), then,
    /// when the words left a field empty, the on-device model 700 ms
    /// after the last keystroke. A keystroke, Save (`freeze()`) or
    /// closing the form cancels a request; an answer for an old title
    /// is dropped.
    ///
    /// Apply it to the form itself, so it lives as long as the sheet.
    func titleSuggestions(_ draft: SuggestionDraft, title: String, goals: [SuggestionGoal]) -> some View {
        modifier(TitleSuggestionsModifier(draft: draft, title: title, goals: goals))
    }
}

struct TitleSuggestionsModifier: ViewModifier {
    let draft: SuggestionDraft
    let title: String
    let goals: [SuggestionGoal]

    @Environment(\.itemSuggester) private var suggester
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Built in `.onAppear`: the environment is not readable when
    /// `@State` is seeded.
    @State private var runner: ItemSuggestionRunner?

    /// Delay before the word tier, after the last keystroke.
    static let wordDelay: Duration = .milliseconds(300)
    /// Further delay before the model, so it starts 700 ms after the
    /// last keystroke.
    static let modelDelay: Duration = .milliseconds(400)

    private struct RunKey: Equatable {
        let title: String
        let goals: [SuggestionGoal]
    }

    func body(content: Content) -> some View {
        content
            .onAppear {
                if runner == nil { runner = ItemSuggestionRunner(suggester: suggester) }
                if suggester.isAvailable { suggester.prewarm() }
            }
            .onSubmit { applyWords(title) }
            .task(id: RunKey(title: title, goals: goals)) {
                await run(for: title)
            }
    }

    private func run(for title: String) async {
        if !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            do { try await Task.sleep(for: Self.wordDelay) } catch { return }
        }
        applyWords(title)
        guard draft.wantsModel, suggester.isAvailable else { return }
        do { try await Task.sleep(for: Self.modelDelay) } catch { return }
        let runner = runner ?? ItemSuggestionRunner(suggester: suggester)
        self.runner = runner
        let request = ItemSuggestionRequest(title: title, kind: draft.kind, goals: goals)
        guard let suggestion = await runner.suggestion(for: request), !Task.isCancelled else { return }
        withAnimation(animation) {
            draft.applyModel(suggestion, for: title)
        }
        announce()
    }

    private func applyWords(_ title: String) {
        withAnimation(animation) {
            draft.applyWords(title: title, goals: goals)
        }
        announce()
    }

    private func announce() {
        guard let text = draft.takeAnnouncement() else { return }
        AccessibilityNotification.Announcement(text).post()
    }

    /// The strip fades in; nothing moves under Reduce Motion.
    private var animation: Animation? {
        reduceMotion ? nil : KadoMotion.base
    }
}

// MARK: - Previews

/// A title field with live suggestions, as the forms use it. Type
/// "contact proffesors at cambrrdgige" or "Read 20 pages".
private struct TitleSuggestionsPreview: View {
    let kind: ItemSuggestionKind
    @State private var title: String
    @State private var draft: SuggestionDraft

    init(kind: ItemSuggestionKind, title: String) {
        self.kind = kind
        _title = State(initialValue: title)
        _draft = State(initialValue: SuggestionDraft(kind: kind))
    }

    private let goals = [SuggestionGoal(name: "Get into Cambridge"), SuggestionGoal(name: "Run a marathon", category: .fitness)]

    var body: some View {
        Form {
            Section {
                TextField("Task title", text: $title)
                if !draft.chips.isEmpty {
                    SuggestionStrip(draft: draft)
                }
            }
            CategoryPickerSection(
                selection: Binding(get: { draft.category }, set: { draft.userSetCategory($0) }),
                isSuggested: draft.categoryOrigin == .suggested,
                identifier: AccessibilityID.Suggestion.taskCategory
            )
        }
        .titleSuggestions(draft, title: title, goals: goals)
    }
}

#Preview("Task title") {
    TitleSuggestionsPreview(kind: .task, title: "contact proffesors at cambrrdgige")
        .kadoTheme()
}

#Preview("Dark") {
    TitleSuggestionsPreview(kind: .habit, title: "Morning run")
        .kadoTheme()
        .preferredColorScheme(.dark)
}
