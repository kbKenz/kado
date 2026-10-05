import SwiftUI
import KadoCore

/// The chrome every Insights card shares: a title row, then the card's
/// content, on the secondary surface.
///
/// The title is its own VoiceOver heading and carries the card's
/// identifier, so it stays a leaf whatever the content does with its
/// own elements.
struct InsightsCard<Content: View>: View {
    let kind: InsightsCardKind
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Color.kadoBackgroundSecondary,
            in: RoundedRectangle(cornerRadius: KadoRadius.sheet, style: .continuous)
        )
    }

    private var header: some View {
        Label {
            Text(kind.title)
                .accessibilityIdentifier(AccessibilityID.Insights.card(kind.rawValue))
        } icon: {
            Image(systemName: kind.symbolName)
                .accessibilityHidden(true)
        }
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(Color.kadoForegroundSecondary)
        .accessibilityAddTraits(.isHeader)
    }
}

#Preview("Card") {
    InsightsCard(kind: .focus) {
        Text("Start a session from Now to see your focus time.")
            .font(.subheadline)
            .foregroundStyle(Color.kadoForeground)
    }
    .padding()
    .background(Color.kadoBackground)
}

#Preview("Dark") {
    VStack(spacing: 16) {
        InsightsCard(kind: .highlights) {
            Label(InsightsHighlight.streakRecord(habitName: "Read", days: 12).sentence, systemImage: "flame.fill")
                .font(.subheadline)
        }
        InsightsCard(kind: .goals) {
            Text("No data yet")
                .font(.subheadline)
                .foregroundStyle(Color.kadoForegroundSecondary)
        }
    }
    .padding()
    .background(Color.kadoBackground)
    .preferredColorScheme(.dark)
}
