import SwiftUI
import KadoCore

/// Everything since the first record: days, times done, tasks done,
/// focus hours and the best streak ever.
struct InsightsAllTimeCard: View {
    let allTime: InsightsAllTime

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// A film runs about two hours, for the one light-hearted line.
    private static let filmLength: TimeInterval = 2 * 60 * 60

    var body: some View {
        InsightsCard(kind: .allTime) {
            VStack(alignment: .leading, spacing: 14) {
                if let since = sinceText {
                    Text(since)
                        .font(.subheadline)
                        .foregroundStyle(Color.kadoForegroundSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                LazyVGrid(columns: columns, alignment: .leading, spacing: 14) {
                    InsightsStat(value: InsightsFormat.count(allTime.habitTimesDone), label: "Times done")
                    InsightsStat(value: InsightsFormat.count(allTime.tasksDone), label: "Tasks done")
                    InsightsStat(value: InsightsFormat.duration(allTime.focusSeconds), label: "Focus")
                    if let best = allTime.bestStreak {
                        InsightsStat(value: bestStreakText(best), label: "Best streak")
                    }
                }
                if let films = filmsText {
                    Label {
                        Text(films)
                            .fixedSize(horizontal: false, vertical: true)
                    } icon: {
                        Image(systemName: "film")
                    }
                    .font(.footnote)
                    .foregroundStyle(Color.kadoForegroundSecondary)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(summary))
        }
    }

    private var columns: [GridItem] {
        let count = dynamicTypeSize.isAccessibilitySize ? 1 : 2
        return Array(repeating: GridItem(.flexible(), spacing: 12, alignment: .topLeading), count: count)
    }

    /// "Since Jan 3, 2026 · 101 days".
    private var sinceText: String? {
        guard let firstDay = allTime.firstDay else { return nil }
        let date = firstDay.formatted(date: .abbreviated, time: .omitted)
        return String(localized: "Since \(date) · \(allTime.daysSinceStart) days", comment: "Insights All time: the day of the first record, then days since then. The values are a date and a count.")
    }

    /// "Meditate · 41 days".
    private func bestStreakText(_ best: InsightsNamedCount) -> String {
        String(localized: "\(best.name) · \(best.count) days", comment: "Insights All time: the habit with the best streak ever and that streak in days.")
    }

    /// "That's about 106 films' worth of focus", from four hours on.
    private var filmsText: String? {
        guard allTime.focusSeconds >= 2 * Self.filmLength else { return nil }
        let films = Int((allTime.focusSeconds / Self.filmLength).rounded(.down))
        return String(localized: "That's about \(films) films' worth of focus", comment: "Insights All time: a light comparison of all focus time with two-hour films.")
    }

    private var summary: String {
        var parts: [String] = []
        if let firstDay = allTime.firstDay {
            let date = firstDay.formatted(date: .long, time: .omitted)
            parts.append(String(localized: "Since \(date), \(allTime.daysSinceStart) days", comment: "Insights All time, VoiceOver: the day of the first record, then days since then."))
        }
        parts.append(String(localized: "\(allTime.habitTimesDone) times done", comment: "Insights All time, VoiceOver: habit days done since the start."))
        parts.append(String(localized: "\(allTime.tasksDone) tasks done", comment: "Insights, VoiceOver: a count of tasks completed."))
        parts.append(String(localized: "\(InsightsFormat.duration(allTime.focusSeconds)) of focus", comment: "Insights: total session time. The value is a duration such as 12h 40m."))
        if let best = allTime.bestStreak {
            parts.append(String(localized: "Best streak: \(best.name), \(best.count) days", comment: "Insights All time, VoiceOver: the habit with the best streak ever and that streak in days."))
        }
        if let films = filmsText {
            parts.append(films)
        }
        return parts.map { $0 + "." }.joined(separator: " ")
    }
}

#Preview("All time") {
    InsightsAllTimeCard(allTime: InsightsPreviewData.rich.allTime)
        .padding()
        .background(Color.kadoBackground)
}

#Preview("Dark") {
    VStack(spacing: 16) {
        InsightsAllTimeCard(allTime: InsightsPreviewData.rich.allTime)
        InsightsAllTimeCard(allTime: InsightsPreviewData.sparse.allTime)
    }
    .padding()
    .background(Color.kadoBackground)
    .preferredColorScheme(.dark)
}
