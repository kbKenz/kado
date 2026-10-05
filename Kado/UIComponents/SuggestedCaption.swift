import KadoCore
import SwiftUI

/// The small "Suggested" mark under a field the app filled in from the
/// title. It goes away as soon as the person changes the field.
struct SuggestedCaption: View {
    /// One of `AccessibilityID.Suggestion`'s badges.
    let identifier: String

    var body: some View {
        // An HStack, not a Label: a Label in a list keeps the icon in
        // the row's icon column, far from its word.
        HStack(spacing: 4) {
            Image(systemName: "wand.and.stars")
                .accessibilityHidden(true)
            Text("Suggested")
        }
        .font(.caption)
        .foregroundStyle(Color.kadoForegroundSecondary)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(identifier)
    }
}

#Preview("Caption") {
    Form {
        Section {
            Text("Get into Cambridge")
        } footer: {
            SuggestedCaption(identifier: AccessibilityID.Suggestion.goalBadge)
        }
    }
    .kadoTheme()
}

#Preview("Dark") {
    Form {
        Section {
            Text("Study")
        } footer: {
            SuggestedCaption(identifier: AccessibilityID.Suggestion.categoryBadge)
        }
    }
    .kadoTheme()
    .preferredColorScheme(.dark)
}
