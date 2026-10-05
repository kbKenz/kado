import SwiftUI
import KadoCore

/// A number over its caption: "31" above "Done". The figures the
/// Insights cards line up in rows and grids.
struct InsightsStat: View {
    let value: String
    let label: LocalizedStringKey

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.title3.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(Color.kadoForeground)
                .fixedSize(horizontal: false, vertical: true)
            Text(label)
                .font(.caption)
                .foregroundStyle(Color.kadoForegroundSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Stats side by side, or stacked when the text is too large for a
/// row (accessibility sizes).
struct InsightsStatRow<Content: View>: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ViewBuilder var content: Content

    var body: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 12) { content }
        } else {
            HStack(alignment: .top, spacing: 12) { content }
        }
    }
}

#Preview("Stats") {
    InsightsStatRow {
        InsightsStat(value: "31", label: "Sessions")
        InsightsStat(value: "29m", label: "Average")
        InsightsStat(value: "1h 52m", label: "Longest")
    }
    .padding()
    .background(Color.kadoBackgroundSecondary)
}

#Preview("Dark") {
    InsightsStatRow {
        InsightsStat(value: "1,240", label: "Times done")
        InsightsStat(value: "214", label: "Tasks done")
    }
    .padding()
    .background(Color.kadoBackgroundSecondary)
    .preferredColorScheme(.dark)
}
