import Charts
import SwiftData
import SwiftUI
import KadoCore

/// One question across the months, newest first. A rating shows as a
/// chart; the biggest problem and the intention show what became of them.
struct ReflectionQuestionHistoryView: View {
    let questionID: String

    @Environment(\.calendar) private var calendar
    @Query private var records: [ReflectionRecord]

    private var question: ReflectionQuestion? { ReflectionCatalog.question(id: questionID) }

    var body: some View {
        let entries = records.mergedEntries
        let items = ReflectionArchive.history(of: questionID, in: entries)
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if let question {
                    Text(verbatim: question.prompt)
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(Color.kadoForeground)
                        .accessibilityAddTraits(.isHeader)
                }
                if question?.kind == .rating {
                    ReflectionRatingChart(
                        series: [(question?.title ?? "", ReflectionArchive.series(of: questionID, in: entries))],
                        calendar: calendar
                    )
                }
                if items.isEmpty {
                    ContentUnavailableView("No answers yet", systemImage: "text.bubble")
                } else {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(items) { item in row(item) }
                    }
                }
            }
            .frame(maxWidth: 640, alignment: .leading)
            .padding()
            .frame(maxWidth: .infinity)
        }
        .background(Color.kadoBackground.ignoresSafeArea())
        .reflectionLockGate()
        .navigationTitle(question?.title ?? "")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func row(_ item: ReflectionArchive.Item) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(verbatim: item.month.title(in: calendar))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.kadoForegroundSecondary)
                Spacer()
                if let outcome = item.outcome, let when = item.outcomeMonth {
                    Label {
                        Text("\(outcome.title) by \(when.monthName(in: calendar))")
                    } icon: {
                        Image(systemName: outcome.symbol)
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.kadoAccent)
                }
            }
            if let rating = item.answer.rating {
                Text("\(Int(rating)) / 10")
                    .font(.title3.monospacedDigit())
                    .foregroundStyle(Color.kadoForeground)
            }
            if let status = item.answer.status {
                Label(status.title, systemImage: status.symbol)
                    .foregroundStyle(Color.kadoAccent)
            }
            if !item.answer.trimmedText.isEmpty {
                Text(verbatim: item.answer.trimmedText)
                    .foregroundStyle(Color.kadoForeground)
                    .textSelection(.enabled)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color.kadoBackgroundSecondary, in: RoundedRectangle(cornerRadius: KadoRadius.card))
        .accessibilityElement(children: .combine)
    }
}

/// Ratings over the months: one line per rating, 1 to 10.
struct ReflectionRatingChart: View {
    let series: [(title: String, points: [(month: ReflectionMonth, value: Double)])]
    let calendar: Calendar

    var body: some View {
        let plotted = series.filter { !$0.points.isEmpty }
        if plotted.contains(where: { $0.points.count >= 1 }) {
            Chart {
                ForEach(plotted, id: \.title) { line in
                    ForEach(line.points, id: \.month) { point in
                        LineMark(
                            x: .value("Month", point.month.firstDay(in: calendar), unit: .month),
                            y: .value("Rating", point.value)
                        )
                        .foregroundStyle(by: .value("Rating", line.title))
                        .interpolationMethod(.monotone)
                        PointMark(
                            x: .value("Month", point.month.firstDay(in: calendar), unit: .month),
                            y: .value("Rating", point.value)
                        )
                        .foregroundStyle(by: .value("Rating", line.title))
                    }
                }
            }
            .chartYScale(domain: 1...10)
            .chartYAxis { AxisMarks(values: [1, 5, 10]) }
            .chartLegend(plotted.count > 1 ? .visible : .hidden)
            .frame(height: 220)
            .padding()
            .background(Color.kadoBackgroundSecondary, in: RoundedRectangle(cornerRadius: KadoRadius.card))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(accessibilitySummary))
        }
    }

    /// "Overall: September 6, October 8." for VoiceOver.
    private var accessibilitySummary: String {
        series.filter { !$0.points.isEmpty }.map { line in
            let values = line.points.map { "\($0.month.monthName(in: calendar)) \(Int($0.value))" }
            return "\(line.title): \(values.formatted(.list(type: .and)))"
        }.joined(separator: ". ")
    }
}

/// The Trends tab: every rating over the months, and the months' words.
struct ReflectionTrendsView: View {
    let entries: [ReflectionEntry]
    let calendar: Calendar

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("RATINGS")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.kadoForegroundSecondary)
            ReflectionRatingChart(
                series: ReflectionCatalog.ratings.map { ($0.title, ReflectionArchive.series(of: $0.id, in: entries)) },
                calendar: calendar
            )
            averages
            words
        }
    }

    /// The average of each rating over every month that has it.
    private var averages: some View {
        let rows = ReflectionCatalog.ratings.compactMap { question -> (String, Double)? in
            let values = ReflectionArchive.series(of: question.id, in: entries).map(\.value)
            guard !values.isEmpty else { return nil }
            return (question.title, values.reduce(0, +) / Double(values.count))
        }
        return VStack(alignment: .leading, spacing: 8) {
            ForEach(rows, id: \.0) { title, average in
                HStack {
                    Text(verbatim: title).foregroundStyle(Color.kadoForeground)
                    Spacer()
                    Text("Average \(average, format: .number.precision(.fractionLength(1)))")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(Color.kadoForegroundSecondary)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }

    @ViewBuilder
    private var words: some View {
        let words = entries.sorted { $0.month < $1.month }.compactMap { entry in entry.word.map { (entry.month, $0) } }
        if !words.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("WORDS OF THE MONTHS")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.kadoForegroundSecondary)
                ForEach(words, id: \.0) { month, word in
                    HStack(alignment: .firstTextBaseline) {
                        Text(verbatim: month.title(in: calendar))
                            .font(.footnote)
                            .foregroundStyle(Color.kadoForegroundSecondary)
                            .frame(minWidth: 120, alignment: .leading)
                        Text(verbatim: word)
                            .italic()
                            .foregroundStyle(Color.kadoForeground)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }
}

#Preview("Question history") {
    NavigationStack {
        ReflectionQuestionHistoryView(questionID: ReflectionCatalog.problemID)
    }
    .modelContainer(ReflectionPreviewData.container)
    .kadoTheme()
}

#Preview("Trends, Dark") {
    ScrollView {
        ReflectionTrendsView(entries: ReflectionPreviewData.entries, calendar: .current)
            .padding()
    }
    .background(Color.kadoBackground)
    .preferredColorScheme(.dark)
}
