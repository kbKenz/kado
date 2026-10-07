import SwiftUI
import KadoCore

/// The first screen: the month in Kado's numbers, and a year ago.
struct ReflectionIntroStep: View {
    let month: ReflectionMonth
    let stats: ReflectionMonthStats
    let yearAgo: ReflectionEntry?
    let calendar: Calendar

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Look back at \(month.monthName(in: calendar))")
                    .font(.largeTitle.weight(.semibold))
                    .foregroundStyle(Color.kadoForeground)
                Text("About 15 minutes. Skip any question. Your answers save as you go, so you can finish later.")
                    .foregroundStyle(Color.kadoForegroundSecondary)
            }
            if !stats.isEmpty {
                ReflectionStatsGrid(stats: stats)
            }
            if let yearAgo {
                ReflectionYearAgoCard(entry: yearAgo, calendar: calendar)
            }
        }
    }
}

/// Kado's numbers for a month, as four tiles.
struct ReflectionStatsGrid: View {
    let stats: ReflectionMonthStats

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("YOUR MONTH IN KADŌ")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.kadoForegroundSecondary)
                .accessibilityAddTraits(.isHeader)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 8)], spacing: 8) {
                tile(value: Text("\(stats.tasksDone)"), label: Text("Tasks done"))
                tile(value: Text("\(stats.habitCheckIns)"), label: Text("Habit check-ins"))
                tile(value: Text(verbatim: focusText), label: Text("Focus time"))
                tile(value: Text("\(stats.activeDays)"), label: Text("Active days"))
            }
        }
    }

    private var focusText: String {
        let minutes = Int(stats.focusSeconds / 60)
        return Duration.seconds(minutes * 60).formatted(.units(allowed: [.hours, .minutes], width: .abbreviated))
    }

    private func tile(value: Text, label: Text) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            value
                .font(.title2.monospacedDigit().weight(.semibold))
                .foregroundStyle(Color.kadoForeground)
            label
                .font(.footnote)
                .foregroundStyle(Color.kadoForegroundSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.kadoBackgroundSecondary, in: RoundedRectangle(cornerRadius: KadoRadius.card))
        .accessibilityElement(children: .combine)
    }
}

/// What was written in the same month a year before.
struct ReflectionYearAgoCard: View {
    let entry: ReflectionEntry
    let calendar: Calendar

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("A YEAR AGO · \(entry.month.title(in: calendar).uppercased())")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.kadoForegroundSecondary)
            if let word = entry.word {
                Text(verbatim: "“\(word)”")
                    .font(.title3.italic())
                    .foregroundStyle(Color.kadoForeground)
            }
            if let overall = entry.overall {
                Text("Overall \(Int(overall)) / 10")
                    .font(.subheadline)
                    .foregroundStyle(Color.kadoForegroundSecondary)
            }
            if let problem = entry.text(ReflectionCatalog.problemID) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Biggest problem then")
                        .font(.footnote)
                        .foregroundStyle(Color.kadoForegroundSecondary)
                    Text(verbatim: problem)
                        .foregroundStyle(Color.kadoForeground)
                        .lineLimit(4)
                }
            }
            if let dreams = entry.text("core.dreams") {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Dreams then")
                        .font(.footnote)
                        .foregroundStyle(Color.kadoForegroundSecondary)
                    Text(verbatim: dreams)
                        .foregroundStyle(Color.kadoForeground)
                        .lineLimit(4)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color.kadoBackgroundSecondary, in: RoundedRectangle(cornerRadius: KadoRadius.card))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(AccessibilityID.Reflect.yearAgo)
    }
}

/// One question with a text answer, dictation included.
struct ReflectionQuestionStep: View {
    let question: ReflectionQuestion
    let isDeep: Bool
    @Binding var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if isDeep {
                Label("This month's deep question", systemImage: "sparkles")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.kadoAccent)
            }
            Text(verbatim: question.prompt)
                .font(.title2.weight(.semibold))
                .foregroundStyle(Color.kadoForeground)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            if question.id == ReflectionCatalog.wordID {
                TextField(question.hint, text: $text)
                    .font(.title3)
                    .textFieldStyle(.plain)
                    .padding(12)
                    .background(Color.kadoBackgroundSecondary, in: RoundedRectangle(cornerRadius: KadoRadius.card))
                    .accessibilityIdentifier(AccessibilityID.Reflect.answer(question.id))
                    .assistedInput($text, identifier: AccessibilityID.Reflect.answer(question.id))
            } else {
                ReflectionTextEditor(text: $text, placeholder: question.hint.isEmpty
                    ? String(localized: "Write freely. Nobody else reads this.")
                    : question.hint, identifier: AccessibilityID.Reflect.answer(question.id))
            }
        }
    }
}

/// A multi-line answer with a placeholder and dictation.
struct ReflectionTextEditor: View {
    @Binding var text: String
    let placeholder: String
    let identifier: String

    var body: some View {
        ZStack(alignment: .topLeading) {
            if text.isEmpty {
                Text(verbatim: placeholder)
                    .foregroundStyle(Color.kadoForegroundSecondary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 8)
                    .accessibilityHidden(true)
            }
            TextEditor(text: $text)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 180)
                .accessibilityLabel(Text(verbatim: placeholder))
                .accessibilityIdentifier(identifier)
        }
        .padding(8)
        .background(Color.kadoBackgroundSecondary, in: RoundedRectangle(cornerRadius: KadoRadius.card))
        .assistedInput($text, identifier: identifier)
    }
}

/// A choice about an earlier answer, quoted, with an optional note.
struct ReflectionFollowUpStep: View {
    let question: ReflectionQuestion
    let quoted: String
    let sourceMonth: String
    let options: [ReflectionFollowUpStatus]
    @Binding var status: ReflectionFollowUpStatus?
    @Binding var note: String

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                Group {
                    if question.id == ReflectionCatalog.followUpProblemID {
                        Text("In \(sourceMonth), your biggest problem was:")
                    } else {
                        Text("In \(sourceMonth), your intention was:")
                    }
                }
                .foregroundStyle(Color.kadoForegroundSecondary)
                Text(verbatim: "“\(quoted)”")
                    .font(.title3.italic())
                    .foregroundStyle(Color.kadoForeground)
                    .padding(.leading, 12)
                    .overlay(alignment: .leading) {
                        Rectangle().fill(Color.kadoAccent).frame(width: 3)
                    }
            }
            Text(verbatim: question.prompt)
                .font(.title2.weight(.semibold))
                .foregroundStyle(Color.kadoForeground)
                .accessibilityAddTraits(.isHeader)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) { optionButtons }
                VStack(alignment: .leading, spacing: 8) { optionButtons }
            }
            ReflectionTextEditor(
                text: $note,
                placeholder: String(localized: "Add a note (optional)"),
                identifier: AccessibilityID.Reflect.answer(question.id)
            )
        }
    }

    private var optionButtons: some View {
        ForEach(options, id: \.self) { option in
            let selected = status == option
            Button {
                status = selected ? nil : option
            } label: {
                Label(option.title, systemImage: option.symbol)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                        selected ? Color.kadoAccent : Color.kadoBackgroundSecondary,
                        in: Capsule()
                    )
                    .foregroundStyle(selected ? Color.kadoBackground : Color.kadoForeground)
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(selected ? .isSelected : [])
            .accessibilityIdentifier(AccessibilityID.Reflect.status(option.rawValue))
        }
    }
}

/// The last screen, before Finish.
struct ReflectionFinishStep: View {
    let month: String
    let answered: Int
    let intention: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Image(systemName: "book.closed.fill")
                .font(.largeTitle)
                .foregroundStyle(Color.kadoAccent)
                .accessibilityHidden(true)
            Text("That's \(month).")
                .font(.largeTitle.weight(.semibold))
                .foregroundStyle(Color.kadoForeground)
            Text("You answered \(answered) questions. Finish to save this month to your reflections. You can come back and edit it any time.")
                .foregroundStyle(Color.kadoForegroundSecondary)
            if let intention, !intention.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Your intention for next month")
                        .font(.footnote)
                        .foregroundStyle(Color.kadoForegroundSecondary)
                    Text(verbatim: intention)
                        .font(.title3)
                        .foregroundStyle(Color.kadoForeground)
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.kadoBackgroundSecondary, in: RoundedRectangle(cornerRadius: KadoRadius.card))
            }
        }
    }
}

#Preview("Intro") {
    ReflectionIntroStep(
        month: ReflectionMonth(year: 2026, month: 10),
        stats: ReflectionMonthStats(tasksDone: 42, habitCheckIns: 118, focusSeconds: 61 * 3600, activeDays: 27),
        yearAgo: ReflectionPreviewData.entries.last,
        calendar: .current
    )
    .padding()
    .background(Color.kadoBackground)
}

#Preview("Follow-up, Dark") {
    @Previewable @State var status: ReflectionFollowUpStatus? = .better
    @Previewable @State var note = ""
    ReflectionFollowUpStep(
        question: ReflectionCatalog.followUps[0], quoted: "Not enough sleep before exams",
        sourceMonth: "September", options: ReflectionFollowUpStatus.problemOptions,
        status: $status, note: $note
    )
    .padding()
    .background(Color.kadoBackground)
    .preferredColorScheme(.dark)
}

#Preview("Question") {
    @Previewable @State var text = ""
    ReflectionQuestionStep(question: ReflectionCatalog.deep[3], isDeep: true, text: $text)
        .padding()
        .background(Color.kadoBackground)
}
