import OSLog
import SwiftData
import SwiftUI
import KadoCore

/// The monthly check-in: one screen per step, answers saved as the user
/// moves on or leaves, so it can be finished later. Reads what it needs
/// itself, so any surface can present it with just a month.
struct ReflectionCheckInView: View {
    let month: ReflectionMonth
    /// Called after Finish saves, before the view dismisses itself.
    var onFinished: () -> Void = {}

    @Environment(\.modelContext) private var modelContext
    @Environment(\.calendar) private var calendar
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.notificationScheduler) private var notificationScheduler

    @State private var steps: [ReflectionStep] = []
    @State private var index = 0
    @State private var drafts: [String: ReflectionAnswer] = [:]
    /// What is stored, to save only what changed.
    @State private var saved: [String: ReflectionAnswer] = [:]
    @State private var stats: ReflectionMonthStats = .empty
    @State private var yearAgo: ReflectionEntry?
    @State private var loaded = false
    @State private var showingError = false

    private static let logger = Logger(subsystem: "dev.scastiel.kado", category: "reflect")

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ProgressView(value: Double(index), total: Double(max(steps.count - 1, 1)))
                    .tint(Color.kadoAccent)
                    .padding(.horizontal)
                    .accessibilityHidden(true)
                ScrollView {
                    if loaded, steps.indices.contains(index) {
                        stepView(steps[index])
                            .frame(maxWidth: 600, alignment: .leading)
                            .padding()
                            .frame(maxWidth: .infinity)
                            .id(steps[index].id)
                            .transition(.opacity)
                    }
                }
                .scrollDismissesKeyboard(.interactively)
                if loaded { bottomBar }
            }
            .background(Color.kadoBackground.ignoresSafeArea())
            .navigationTitle(month.title(in: calendar))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { close() }
                        .accessibilityIdentifier(AccessibilityID.Reflect.close)
                }
            }
            .alert("Couldn't save your answers", isPresented: $showingError) {
                Button("Close", role: .cancel) {}
            } message: {
                Text("Try again in a moment.")
            }
        }
        // However it was opened (Reflect, the Today card, a reminder),
        // a check-in shows past answers, so it is behind the lock too.
        .reflectionLockGate()
        .interactiveDismissDisabled()
        .task { load() }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { saveAll() }
        }
    }

    // MARK: - Steps

    @ViewBuilder
    private func stepView(_ step: ReflectionStep) -> some View {
        switch step {
        case .intro:
            ReflectionIntroStep(month: month, stats: stats, yearAgo: yearAgo, calendar: calendar)
        case .ratings(let questions):
            VStack(alignment: .leading, spacing: 28) {
                stepTitle(String(localized: "Rate your month"), detail: String(localized: "From 1 (very bad) to 10 (excellent). Tap again to clear."))
                ForEach(questions) { question in
                    ReflectionRatingPicker(question: question, value: ratingBinding(question))
                }
            }
        case .followUp(let question, let quoted, let source, let options):
            ReflectionFollowUpStep(
                question: question, quoted: quoted, sourceMonth: source.monthName(in: calendar), options: options,
                status: statusBinding(question, quoted: quoted, source: source),
                note: textBinding(question, prompt: followUpPrompt(question, quoted: quoted, source: source), source: source)
            )
        case .question(let question):
            ReflectionQuestionStep(
                question: question,
                isDeep: question.id.hasPrefix("deep."),
                text: textBinding(question, prompt: question.prompt)
            )
        case .finish:
            ReflectionFinishStep(
                month: month.monthName(in: calendar),
                answered: drafts.values.filter { !$0.isEmpty }.count,
                intention: drafts[ReflectionCatalog.intentionID]?.trimmedText
            )
        }
    }

    private func stepTitle(_ title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(verbatim: title)
                .font(.title2.weight(.semibold))
                .foregroundStyle(Color.kadoForeground)
            Text(verbatim: detail)
                .foregroundStyle(Color.kadoForegroundSecondary)
        }
    }

    // MARK: - Bottom bar

    private var bottomBar: some View {
        HStack(spacing: 12) {
            if index > 0 {
                Button { go(to: index - 1) } label: {
                    // The word would wrap at accessibility sizes; the
                    // label still reads "Back" to VoiceOver.
                    if dynamicTypeSize.isAccessibilitySize {
                        Label("Back", systemImage: "chevron.left").labelStyle(.iconOnly)
                    } else {
                        Label("Back", systemImage: "chevron.left")
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .accessibilityIdentifier(AccessibilityID.Reflect.back)
            }
            Spacer()
            if steps.indices.contains(index) {
                switch steps[index] {
                case .intro:
                    Button("Begin") { go(to: index + 1) }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .accessibilityIdentifier(AccessibilityID.Reflect.next)
                case .finish:
                    Button("Finish") { finish() }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .accessibilityIdentifier(AccessibilityID.Reflect.finish)
                default:
                    Button { go(to: index + 1) } label: {
                        if isAnswered(steps[index]) { Text("Next") } else { Text("Skip") }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .accessibilityIdentifier(AccessibilityID.Reflect.next)
                }
            }
        }
        // One line each: a word broken over two lines in a pill reads worse
        // than slightly smaller text.
        .lineLimit(1)
        .minimumScaleFactor(0.6)
        .padding()
        .background(Color.kadoBackground)
    }

    private func isAnswered(_ step: ReflectionStep) -> Bool {
        switch step {
        case .ratings(let questions): questions.contains { drafts[$0.id]?.rating != nil }
        case .followUp(let question, _, _, _), .question(let question): !(drafts[question.id]?.isEmpty ?? true)
        case .intro, .finish: true
        }
    }

    private func go(to newIndex: Int) {
        saveAll()
        withAnimation(.easeInOut(duration: 0.2)) {
            index = min(max(newIndex, 0), steps.count - 1)
        }
    }

    // MARK: - Bindings

    private func ratingBinding(_ question: ReflectionQuestion) -> Binding<Double?> {
        Binding(
            get: { drafts[question.id]?.rating },
            set: { value in
                var answer = drafts[question.id] ?? ReflectionAnswer(questionID: question.id)
                answer.prompt = question.prompt
                answer.rating = value
                drafts[question.id] = answer
            }
        )
    }

    private func textBinding(_ question: ReflectionQuestion, prompt: String, source: ReflectionMonth? = nil) -> Binding<String> {
        Binding(
            get: { drafts[question.id]?.text ?? "" },
            set: { text in
                var answer = drafts[question.id] ?? ReflectionAnswer(questionID: question.id)
                answer.prompt = prompt
                answer.sourceMonth = source
                answer.text = text
                drafts[question.id] = answer
            }
        )
    }

    private func statusBinding(
        _ question: ReflectionQuestion, quoted: String, source: ReflectionMonth
    ) -> Binding<ReflectionFollowUpStatus?> {
        Binding(
            get: { drafts[question.id]?.status },
            set: { status in
                var answer = drafts[question.id] ?? ReflectionAnswer(questionID: question.id)
                answer.prompt = followUpPrompt(question, quoted: quoted, source: source)
                answer.sourceMonth = source
                answer.status = status
                drafts[question.id] = answer
            }
        )
    }

    /// The follow-up as it reads back later, with the quoted answer.
    private func followUpPrompt(_ question: ReflectionQuestion, quoted: String, source: ReflectionMonth) -> String {
        let name = source.monthName(in: calendar)
        return question.id == ReflectionCatalog.followUpProblemID
            ? String(localized: "In \(name), my biggest problem was “\(quoted)”. Now it is…")
            : String(localized: "In \(name), my intention was “\(quoted)”. Did I do it?")
    }

    // MARK: - Load and save

    private func load() {
        guard !loaded else { return }
        let store = ReflectionStore(context: modelContext)
        let entries = (try? store.entries()) ?? []
        let entry = entries.first { $0.month == month }
        steps = ReflectionPlanner(calendar: calendar).steps(for: month, entries: entries)
        drafts = entry?.answers ?? [:]
        saved = drafts
        stats = ReflectionStatsBuilder(calendar: calendar).stats(for: month, in: modelContext)
        yearAgo = ReflectionArchive.yearAgo(of: month, in: entries)
        // A check-in already started opens where its answers end.
        if let entry, !entry.isComplete, !entry.answers.isEmpty,
           let last = steps.lastIndex(where: { step in entry.answers[step.id] != nil || stepHasAnswer(step, entry) }) {
            index = min(last + 1, steps.count - 1)
        }
        loaded = true
    }

    private func stepHasAnswer(_ step: ReflectionStep, _ entry: ReflectionEntry) -> Bool {
        if case .ratings(let questions) = step { return questions.contains { entry.answers[$0.id] != nil } }
        return false
    }

    /// Writes every draft that changed since the last save. False, with
    /// the alert up, when a save failed: the drafts stay in memory.
    @discardableResult
    private func saveAll() -> Bool {
        let store = ReflectionStore(context: modelContext)
        do {
            for (id, draft) in drafts where saved[id] != draft {
                try store.save(draft, for: month)
                saved[id] = draft
            }
            return true
        } catch {
            let nsError = error as NSError
            Self.logger.error("Reflection save failed: \(nsError.domain, privacy: .public) \(nsError.code, privacy: .public)")
            showingError = true
            return false
        }
    }

    /// Stays open when the answers could not be saved, so they are not lost.
    private func close() {
        guard saveAll() else { return }
        ReflectionReminders.sync(using: modelContext)
        dismiss()
    }

    private func finish() {
        guard saveAll() else { return }
        do {
            try ReflectionStore(context: modelContext).complete(month)
        } catch {
            let nsError = error as NSError
            Self.logger.error("Reflection finish failed: \(nsError.domain, privacy: .public) \(nsError.code, privacy: .public)")
            showingError = true
            return
        }
        ReflectionReminders.sync(using: modelContext)
        // The reminder is on by default; the first finished check-in is
        // the moment to ask for the permission it needs (asked once).
        // UI runs skip it: a system alert would cover the app.
        if ReflectionDefaults.remindersEnabled && !UITestSupport.isRunningUITests {
            let scheduler = notificationScheduler
            Task { _ = await scheduler.requestAuthorizationIfNeeded() }
        }
        onFinished()
        dismiss()
    }
}

#Preview("Check-in") {
    ReflectionCheckInView(month: ReflectionMonth(containing: .now, calendar: .current))
        .modelContainer(PreviewContainer.shared)
        .kadoTheme()
}

#Preview("Check-in, Dark") {
    ReflectionCheckInView(month: ReflectionMonth(containing: .now, calendar: .current))
        .modelContainer(PreviewContainer.shared)
        .kadoTheme()
        .preferredColorScheme(.dark)
}
