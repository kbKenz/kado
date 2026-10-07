import SwiftData
import SwiftUI
import KadoCore

/// A place in the Reflect archive, pushed on Overview's stack.
enum ReflectionRoute: Hashable {
    case month(ReflectionMonth)
    case question(String)
}

/// Overview's Reflect section: this month's check-in, a year ago, and
/// every month written so far, by month, by question or as trends.
struct ReflectScreen: View {
    @Binding var path: NavigationPath

    @Environment(\.modelContext) private var modelContext
    @Environment(\.calendar) private var calendar
    @Environment(\.notificationScheduler) private var notificationScheduler

    @Query private var records: [ReflectionRecord]
    @AppStorage(ReflectionDefaults.archiveModeKey) private var archiveMode: ReflectArchiveMode = .months
    @AppStorage(ReflectionDefaults.remindersKey) private var remindersEnabled = true

    @State private var checkIn: CheckInSheet?
    @State private var search = ""
    @State private var lockUnavailable = false

    private struct CheckInSheet: Identifiable {
        let month: ReflectionMonth
        var id: Int { month.id }
    }

    private var lock: ReflectionLockState { .shared }

    var body: some View {
        content
            .reflectionLockGate()
            .navigationDestination(for: ReflectionRoute.self) { route in
            switch route {
            case .month(let month): ReflectionMonthView(month: month, path: $path)
            case .question(let id): ReflectionQuestionHistoryView(questionID: id)
            }
        }
        .toolbar {
            // Hidden while locked: the menu turns the lock off.
            if !lock.isLocked {
                ToolbarItem(placement: .primaryAction) { settingsMenu }
            }
        }
        .fullScreenCover(item: $checkIn) { sheet in
            ReflectionCheckInView(month: sheet.month)
        }
        .alert("Set a passcode to lock reflections", isPresented: $lockUnavailable) {
            Button("Close", role: .cancel) {}
        } message: {
            Text("The lock uses Face ID, Touch ID or your device passcode. Set one in the Settings app first.")
        }
    }

    private var entries: [ReflectionEntry] { records.mergedEntries }

    @ViewBuilder
    private var content: some View {
        let entries = entries
        let planner = ReflectionPlanner(calendar: calendar)
        let checkInMonth = planner.checkInMonth(now: .now, entries: entries)
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if search.isEmpty {
                    ReflectCheckInCard(
                        month: checkInMonth,
                        entry: entries.first { $0.month == checkInMonth },
                        stepCount: planner.steps(for: checkInMonth, entries: entries).count - 2,
                        calendar: calendar,
                        onOpen: { checkIn = CheckInSheet(month: checkInMonth) }
                    )
                    if let yearAgo = ReflectionArchive.yearAgo(of: checkInMonth, in: entries) {
                        Button { path.append(ReflectionRoute.month(yearAgo.month)) } label: {
                            ReflectionYearAgoCard(entry: yearAgo, calendar: calendar)
                        }
                        .buttonStyle(.plain)
                    }
                    archive(entries)
                } else {
                    ReflectSearchResults(hits: ReflectionArchive.search(search, in: entries), calendar: calendar) { hit in
                        path.append(ReflectionRoute.month(hit.month))
                    }
                }
            }
            .frame(maxWidth: 640, alignment: .leading)
            .padding()
            .frame(maxWidth: .infinity)
        }
        .searchable(text: $search, prompt: Text("Search reflections"))
    }

    @ViewBuilder
    private func archive(_ entries: [ReflectionEntry]) -> some View {
        let written = entries.filter { !$0.answers.isEmpty }
        if written.isEmpty {
            ContentUnavailableView {
                Label("Your reflections will be here", systemImage: "book.closed")
            } description: {
                Text("Each month, answer the same few questions about your life. Months from now, read them back and see what changed.")
            }
            .accessibilityIdentifier(AccessibilityID.Reflect.empty)
        } else {
            Picker("Show", selection: $archiveMode) {
                Text("Months").tag(ReflectArchiveMode.months)
                Text("Questions").tag(ReflectArchiveMode.questions)
                Text("Trends").tag(ReflectArchiveMode.trends)
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier(AccessibilityID.Reflect.archivePicker)
            switch archiveMode {
            case .months:
                ReflectMonthList(entries: written, calendar: calendar) { path.append(ReflectionRoute.month($0)) }
            case .questions:
                ReflectQuestionList(entries: written, calendar: calendar) { path.append(ReflectionRoute.question($0)) }
            case .trends:
                ReflectionTrendsView(entries: written, calendar: calendar)
            }
        }
    }

    private var settingsMenu: some View {
        Menu {
            Toggle(isOn: Binding(get: { remindersEnabled }, set: setReminders)) {
                Label("Monthly reminder", systemImage: "bell")
            }
            .accessibilityIdentifier(AccessibilityID.Reflect.reminderToggle)
            Toggle(isOn: Binding(get: { lock.isEnabled }, set: setLock)) {
                Label("Lock with Face ID", systemImage: "faceid")
            }
            .accessibilityIdentifier(AccessibilityID.Reflect.lockToggle)
        } label: {
            Label("Reflection settings", systemImage: "ellipsis.circle")
        }
        .accessibilityIdentifier(AccessibilityID.Reflect.settingsMenu)
    }

    // MARK: - Actions

    /// Both ways ask for Face ID: on, to prove the user can open it
    /// again; off, so only the owner can remove it.
    private func setLock(_ on: Bool) {
        Task {
            if on {
                if await !lock.enable() { lockUnavailable = true }
            } else {
                await lock.disable()
            }
        }
    }

    private func setReminders(_ on: Bool) {
        remindersEnabled = on
        if on {
            let scheduler = notificationScheduler
            Task { _ = await scheduler.requestAuthorizationIfNeeded() }
        }
        ReflectionReminders.sync(using: modelContext)
    }
}

/// This month's check-in: its state and the button to open it.
struct ReflectCheckInCard: View {
    let month: ReflectionMonth
    let entry: ReflectionEntry?
    /// Questions in the check-in, without the intro and finish screens.
    let stepCount: Int
    let calendar: Calendar
    let onOpen: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("MONTHLY CHECK-IN")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.kadoForegroundSecondary)
            Text(verbatim: month.title(in: calendar))
                .font(.title.weight(.semibold))
                .foregroundStyle(Color.kadoForeground)
            status
                .foregroundStyle(Color.kadoForegroundSecondary)
            Button(action: onOpen) {
                Group {
                    if entry?.isComplete == true {
                        Label("Read or edit", systemImage: "pencil")
                    } else if entry?.answers.isEmpty == false {
                        Label("Continue", systemImage: "play.fill")
                    } else {
                        Label("Start check-in", systemImage: "square.and.pencil")
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .accessibilityIdentifier(AccessibilityID.Reflect.checkInButton)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color.kadoBackgroundSecondary, in: RoundedRectangle(cornerRadius: KadoRadius.card))
    }

    @ViewBuilder
    private var status: some View {
        if let entry, entry.isComplete {
            Label("Done. You can still add to it.", systemImage: "checkmark.circle.fill")
        } else if let entry, !entry.answers.isEmpty {
            Text("In progress: \(entry.answers.count) answers so far.")
        } else {
            Text("About 15 minutes: ratings, a few honest questions, and one deep question.")
        }
    }
}

/// Months, newest first: the word, the overall rating, and draft state.
struct ReflectMonthList: View {
    let entries: [ReflectionEntry]
    let calendar: Calendar
    let onOpen: (ReflectionMonth) -> Void

    var body: some View {
        LazyVStack(spacing: 8) {
            ForEach(entries) { entry in
                Button { onOpen(entry.month) } label: { row(entry) }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier(AccessibilityID.Reflect.monthRow(entry.month.id))
            }
        }
    }

    private func row(_ entry: ReflectionEntry) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: entry.month.title(in: calendar))
                    .font(.headline)
                    .foregroundStyle(Color.kadoForeground)
                if let word = entry.word {
                    Text(verbatim: "“\(word)”")
                        .font(.subheadline.italic())
                        .foregroundStyle(Color.kadoForeground)
                }
                if let problem = entry.text(ReflectionCatalog.problemID) {
                    Text(verbatim: problem)
                        .font(.footnote)
                        .foregroundStyle(Color.kadoForegroundSecondary)
                        .lineLimit(2)
                }
                if !entry.isComplete {
                    Text("Draft")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.kadoAccent)
                }
            }
            Spacer(minLength: 8)
            if let overall = entry.overall {
                ReflectionScoreBadge(value: overall)
            }
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
        .padding()
        .background(Color.kadoBackgroundSecondary, in: RoundedRectangle(cornerRadius: KadoRadius.card))
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// "7" in a circle, for the overall rating.
struct ReflectionScoreBadge: View {
    let value: Double

    var body: some View {
        Text(verbatim: "\(Int(value))")
            .font(.headline.monospacedDigit())
            .foregroundStyle(Color.kadoForeground)
            .frame(minWidth: 40, minHeight: 40)
            .background(Color.kadoAccent.opacity(0.08 + 0.05 * value), in: Circle())
            .accessibilityLabel(Text("Overall \(Int(value)) / 10"))
    }
}

/// Every question, with how many months answered it.
struct ReflectQuestionList: View {
    let entries: [ReflectionEntry]
    let calendar: Calendar
    let onOpen: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            section(Text("Ratings"), ReflectionCatalog.ratings)
            section(Text("Every month"), ReflectionCatalog.core)
            section(Text("Deep questions"), ReflectionCatalog.deep, showMonth: true)
        }
    }

    private func section(_ title: Text, _ questions: [ReflectionQuestion], showMonth: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            title
                .font(.caption.weight(.semibold))
                .textCase(.uppercase)
                .foregroundStyle(Color.kadoForegroundSecondary)
                .accessibilityAddTraits(.isHeader)
            VStack(spacing: 0) {
                ForEach(Array(questions.enumerated()), id: \.element.id) { index, question in
                    if index > 0 { Divider().padding(.leading) }
                    Button { onOpen(question.id) } label: {
                        row(question, monthNumber: showMonth ? index + 1 : nil)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier(AccessibilityID.Reflect.questionRow(question.id))
                }
            }
            .background(Color.kadoBackgroundSecondary, in: RoundedRectangle(cornerRadius: KadoRadius.card))
        }
    }

    private func row(_ question: ReflectionQuestion, monthNumber: Int?) -> some View {
        let count = entries.filter { $0.answer(question.id) != nil }.count
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: question.title)
                    .foregroundStyle(Color.kadoForeground)
                if let monthNumber {
                    Text(verbatim: calendar.standaloneMonthSymbols[monthNumber - 1])
                        .font(.caption)
                        .foregroundStyle(Color.kadoForegroundSecondary)
                }
            }
            Spacer()
            Text("\(count) months")
                .font(.footnote)
                .foregroundStyle(Color.kadoForegroundSecondary)
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
        .padding(.horizontal)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// Search matches: the month, the question and the answer.
struct ReflectSearchResults: View {
    let hits: [ReflectionArchive.Hit]
    let calendar: Calendar
    let onOpen: (ReflectionArchive.Hit) -> Void

    var body: some View {
        if hits.isEmpty {
            ContentUnavailableView.search
        } else {
            LazyVStack(alignment: .leading, spacing: 8) {
                ForEach(hits) { hit in
                    Button { onOpen(hit) } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(verbatim: hit.month.title(in: calendar))
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Color.kadoForegroundSecondary)
                            Text(verbatim: ReflectionCatalog.question(id: hit.questionID)?.title ?? hit.prompt)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Color.kadoForeground)
                            Text(verbatim: hit.text)
                                .foregroundStyle(Color.kadoForeground)
                                .lineLimit(4)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .background(Color.kadoBackgroundSecondary, in: RoundedRectangle(cornerRadius: KadoRadius.card))
                        .accessibilityElement(children: .combine)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

#Preview("Reflect") {
    NavigationStack {
        ReflectScreen(path: .constant(NavigationPath()))
    }
    .modelContainer(ReflectionPreviewData.container)
    .kadoTheme()
}

#Preview("Reflect, empty, Dark") {
    NavigationStack {
        ReflectScreen(path: .constant(NavigationPath()))
    }
    .modelContainer(PreviewContainer.emptyContainer())
    .kadoTheme()
    .preferredColorScheme(.dark)
}
