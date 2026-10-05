import KadoCore
import SwiftData
import SwiftUI

/// Reused by task and habit forms. A selected archived goal remains
/// visible so editing another field cannot silently discard its link.
struct GoalPickerSection: View {
    @Binding var selectedGoalID: UUID?
    /// Shows the "Suggested" caption: the app chose the goal from the
    /// title, and the person has not touched the picker since.
    var isSuggested: Bool = false
    @Query(sort: \GoalRecord.name) private var records: [GoalRecord]
    @State private var showingNewGoal = false

    var body: some View {
        Section {
            Picker("Goal", selection: $selectedGoalID) {
                Text("No goal").tag(Optional<UUID>.none)
                ForEach(choices) { item in
                    Text(item.archivedAt == nil ? item.name : String(localized: "\(item.name) (Archived)"))
                        .tag(Optional(item.id))
                }
                if let selectedGoalID, !choices.contains(where: { $0.id == selectedGoalID }) {
                    Text("Unavailable goal").tag(Optional(selectedGoalID))
                }
            }
            .accessibilityIdentifier(AccessibilityID.Goals.picker)
            Button { showingNewGoal = true } label: {
                Label("Create a goal", systemImage: "plus")
            }
            .accessibilityIdentifier(AccessibilityID.Goals.pickerCreate)
        } header: { Text("Goal (optional)") }
        footer: {
            VStack(alignment: .leading, spacing: 6) {
                if isSuggested {
                    SuggestedCaption(identifier: AccessibilityID.Suggestion.goalBadge)
                }
                if choices.first(where: { $0.id == selectedGoalID })?.archivedAt != nil {
                    Text("This goal is archived. Its existing links are preserved.")
                } else {
                    Text("Connect this item to something you want to achieve.")
                }
            }
        }
        .listRowBackground(Color.kadoBackgroundSecondary)
        .sheet(isPresented: $showingNewGoal) {
            GoalFormView(onSaved: { selectedGoalID = $0 })
        }
    }

    private var choices: [GoalListItem] {
        records.map { GoalListItem($0) }.filter { $0.archivedAt == nil || $0.id == selectedGoalID }
    }
}

#Preview("Goal picker") {
    Form { GoalPickerSection(selectedGoalID: .constant(GoalPreviewContainer.healthGoalID), isSuggested: true) }
        .modelContainer(GoalPreviewContainer.shared)
        .kadoTheme()
}

#Preview("Dark") {
    Form { GoalPickerSection(selectedGoalID: .constant(GoalPreviewContainer.archivedGoalID)) }
        .modelContainer(GoalPreviewContainer.shared)
        .kadoTheme()
        .preferredColorScheme(.dark)
}
