import OSLog
import SwiftData
import SwiftUI
import KadoCore

/// One month read back: the word, the ratings, Kado's numbers and every
/// answer, in the order they were asked.
struct ReflectionMonthView: View {
    let month: ReflectionMonth
    @Binding var path: NavigationPath

    @Environment(\.modelContext) private var modelContext
    @Environment(\.calendar) private var calendar
    @Query private var records: [ReflectionRecord]

    @State private var editing = false
    @State private var confirmingDelete = false
    @State private var stats: ReflectionMonthStats = .empty

    private static let logger = Logger(subsystem: "dev.scastiel.kado", category: "reflect")

    init(month: ReflectionMonth, path: Binding<NavigationPath>) {
        self.month = month
        _path = path
        let year = month.year
        let number = month.month
        _records = Query(filter: #Predicate<ReflectionRecord> { $0.year == year && $0.month == number })
    }

    var body: some View {
        let entry = records.mergedEntries.first
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if let entry {
                    header(entry)
                    ratings(entry)
                    if !stats.isEmpty { ReflectionStatsGrid(stats: stats) }
                    answers(entry)
                } else {
                    ContentUnavailableView("Nothing written for this month", systemImage: "book.closed")
                }
            }
            .frame(maxWidth: 640, alignment: .leading)
            .padding()
            .frame(maxWidth: .infinity)
        }
        .background(Color.kadoBackground.ignoresSafeArea())
        .reflectionLockGate()
        .navigationTitle(month.title(in: calendar))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // No edit or delete while locked.
            if !ReflectionLockState.shared.isLocked {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button { editing = true } label: { Label("Edit answers", systemImage: "pencil") }
                            .accessibilityIdentifier(AccessibilityID.Reflect.edit)
                        Button(role: .destructive) { confirmingDelete = true } label: {
                            Label("Delete this month", systemImage: "trash")
                        }
                    } label: {
                        Label("More", systemImage: "ellipsis.circle")
                    }
                }
            }
        }
        .fullScreenCover(isPresented: $editing) {
            ReflectionCheckInView(month: month)
        }
        .confirmationDialog(
            String(localized: "Delete this month's reflection?"),
            isPresented: $confirmingDelete, titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive, action: delete)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Every answer for this month is removed. This cannot be undone.")
        }
        .task(id: month) {
            stats = ReflectionStatsBuilder(calendar: calendar).stats(for: month, in: modelContext)
        }
    }

    private func header(_ entry: ReflectionEntry) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let word = entry.word {
                Text(verbatim: "“\(word)”")
                    .font(.largeTitle.italic())
                    .foregroundStyle(Color.kadoForeground)
            }
            if let completed = entry.completedAt {
                Text("Written \(completed, format: .dateTime.day().month(.wide).year())")
                    .font(.footnote)
                    .foregroundStyle(Color.kadoForegroundSecondary)
            } else {
                Text("Draft: not finished yet")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color.kadoAccent)
            }
        }
    }

    @ViewBuilder
    private func ratings(_ entry: ReflectionEntry) -> some View {
        let rated = ReflectionCatalog.ratings.compactMap { question in
            entry.answer(question.id)?.rating.map { (question, $0) }
        }
        if !rated.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(rated, id: \.0.id) { question, value in
                    HStack(spacing: 12) {
                        Text(verbatim: question.title)
                            .frame(minWidth: 110, alignment: .leading)
                            .foregroundStyle(Color.kadoForeground)
                        ProgressView(value: value, total: 10)
                            .tint(Color.kadoAccent)
                        Text(verbatim: "\(Int(value))")
                            .font(.body.monospacedDigit())
                            .foregroundStyle(Color.kadoForegroundSecondary)
                            .frame(minWidth: 24, alignment: .trailing)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text(verbatim: question.title))
                    .accessibilityValue(Text("\(Int(value)) of 10"))
                }
            }
            .padding()
            .background(Color.kadoBackgroundSecondary, in: RoundedRectangle(cornerRadius: KadoRadius.card))
        }
    }

    /// Answers in catalog order; an answer to a retired question last,
    /// under the words it was asked with.
    @ViewBuilder
    private func answers(_ entry: ReflectionEntry) -> some View {
        let order = ReflectionCatalog.followUps + ReflectionCatalog.core + ReflectionCatalog.deep
        let known = Set(ReflectionCatalog.all.map(\.id))
        let listed = order.compactMap { question in entry.answer(question.id).map { (question.id, $0) } }
        let retired = entry.answers.values
            .filter { !known.contains($0.questionID) }
            .sorted { $0.questionID < $1.questionID }
            .map { ($0.questionID, $0) }
        VStack(alignment: .leading, spacing: 20) {
            ForEach(listed + retired, id: \.0) { _, answer in
                ReflectionAnswerView(answer: answer)
            }
        }
    }

    private func delete() {
        do {
            try ReflectionStore(context: modelContext).delete(month)
            ReflectionReminders.sync(using: modelContext)
            if !path.isEmpty { path.removeLast() }
        } catch {
            let nsError = error as NSError
            Self.logger.error("Reflection delete failed: \(nsError.domain, privacy: .public) \(nsError.code, privacy: .public)")
        }
    }
}

/// One answer under the question as it was asked.
struct ReflectionAnswerView: View {
    let answer: ReflectionAnswer

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(verbatim: answer.prompt.isEmpty ? (ReflectionCatalog.question(id: answer.questionID)?.prompt ?? "") : answer.prompt)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.kadoForegroundSecondary)
            if let status = answer.status {
                Label(status.title, systemImage: status.symbol)
                    .font(.headline)
                    .foregroundStyle(Color.kadoAccent)
            }
            if !answer.trimmedText.isEmpty {
                Text(verbatim: answer.trimmedText)
                    .foregroundStyle(Color.kadoForeground)
                    .textSelection(.enabled)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

#Preview("Month") {
    NavigationStack {
        ReflectionMonthView(month: ReflectionPreviewData.entries[0].month, path: .constant(NavigationPath()))
    }
    .modelContainer(ReflectionPreviewData.container)
    .kadoTheme()
}

#Preview("Month, Dark XXXL") {
    NavigationStack {
        ReflectionMonthView(month: ReflectionPreviewData.entries[0].month, path: .constant(NavigationPath()))
    }
    .modelContainer(ReflectionPreviewData.container)
    .kadoTheme()
    .preferredColorScheme(.dark)
    .dynamicTypeSize(.accessibility2)
}
