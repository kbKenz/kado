import SwiftUI
import KadoCore

/// Up to four facts the calculator picked, one sentence each.
struct InsightsHighlightsCard: View {
    let highlights: [InsightsHighlight]

    @ScaledMetric(relativeTo: .subheadline) private var iconWidth: CGFloat = 22

    var body: some View {
        InsightsCard(kind: .highlights) {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(highlights.enumerated()), id: \.offset) { _, highlight in
                    row(highlight)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(highlights.map(\.sentence).joined(separator: ". ")))
        }
    }

    private func row(_ highlight: InsightsHighlight) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: highlight.symbolName)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.kadoAccent)
                .frame(width: iconWidth)
            Text(highlight.sentence)
                .font(.subheadline)
                .foregroundStyle(Color.kadoForeground)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

#Preview("Highlights") {
    InsightsHighlightsCard(highlights: InsightsPreviewData.rich.highlights)
        .padding()
        .background(Color.kadoBackground)
}

#Preview("Dark") {
    ScrollView {
        InsightsHighlightsCard(highlights: InsightsPreviewData.everyHighlight)
            .padding()
    }
    .background(Color.kadoBackground)
    .preferredColorScheme(.dark)
}
