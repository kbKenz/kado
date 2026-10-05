import KadoCore
import SwiftUI

/// The Category row of the task, habit and goal forms: "None" and the 11
/// named categories, each with its symbol. Other is a display fallback
/// and is never offered.
struct CategoryPickerSection: View {
    @Binding var selection: ItemCategory?
    /// Shows the "Suggested" caption: the app filled the row in.
    var isSuggested: Bool = false
    /// One of `AccessibilityID.Suggestion`'s category pickers.
    let identifier: String

    /// Every category a person can pick, in the enum's order.
    static let choices: [ItemCategory] = ItemCategory.allCases.filter { $0 != .other }

    var body: some View {
        Section {
            Picker("Category", selection: $selection) {
                Text("None").tag(Optional<ItemCategory>.none)
                ForEach(Self.choices) { category in
                    Label(category.localizedName, systemImage: category.symbolName)
                        .tag(Optional(category))
                }
            }
            // A selected Label is not read as the picker's value on its
            // own, so name it: "Category, Study".
            .accessibilityValue(selection.map { Text($0.localizedName) } ?? Text("None"))
            .accessibilityIdentifier(identifier)
        } footer: {
            if isSuggested {
                SuggestedCaption(identifier: AccessibilityID.Suggestion.categoryBadge)
            }
        }
        .listRowBackground(Color.kadoBackgroundSecondary)
    }
}

#Preview("Suggested") {
    @Previewable @State var category: ItemCategory? = .study
    Form {
        CategoryPickerSection(selection: $category, isSuggested: true, identifier: AccessibilityID.Suggestion.taskCategory)
    }
    .scrollContentBackground(.hidden)
    .background(Color.kadoBackground)
    .kadoTheme()
}

#Preview("Dark") {
    @Previewable @State var category: ItemCategory? = nil
    Form {
        CategoryPickerSection(selection: $category, identifier: AccessibilityID.Suggestion.habitCategory)
    }
    .scrollContentBackground(.hidden)
    .background(Color.kadoBackground)
    .kadoTheme()
    .preferredColorScheme(.dark)
}
