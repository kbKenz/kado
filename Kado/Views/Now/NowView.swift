import OSLog
import SwiftData
import SwiftUI
import KadoCore

/// The Now tab: one thing to work on, its tracked time, and what is next.
struct NowView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dayBoundary) private var dayBoundary
    @Environment(\.frequencyEvaluator) private var frequencyEvaluator
    // Read so returning to the foreground re-renders at once.
    @Environment(\.scenePhase) private var scenePhase

    // These queries only trigger a re-render after data changes; the
    // builder fetches its own records and returns values.
    @Query(filter: #Predicate<WorkSessionRecord> { $0.endedAt == nil }) private var sessions: [WorkSessionRecord]
    @Query private var blocks: [ScheduleBlockRecord]
    @Query private var tasks: [TaskRecord]
    @Query private var habits: [HabitRecord]
    @Query private var completions: [CompletionRecord]

    @State private var confirmingFinish = false
    @State private var showingStartSomething = false
    @State private var detail: NowItem?
    @State private var showingError = false
    @State private var errorMessage: LocalizedStringResource = "Couldn't save your change. Try again."
    /// Loaded once when the sheet is requested, not on every body pass.
    @State private var quickStartCandidates: [NowItem] = []
    /// Set while the sheet closes; shown from `onDismiss`, because an alert
    /// raised while a sheet is still leaving can be dropped.
    @State private var pendingAlert: LocalizedStringResource?

    /// Readable column width, so iPad does not stretch the cards.
    private static let maxContentWidth: CGFloat = 560

    private static let logger = Logger(subsystem: "dev.scastiel.kado", category: "now")

    var body: some View {
        NavigationStack {
            // Re-resolve every minute so suggestions move with the clock.
            TimelineView(.everyMinute) { context in
                // `max` with the wall clock: after backgrounding, the first
                // frame can carry a stale `context.date`.
                content(now: max(context.date, .now))
            }
            .background(Color.kadoBackground.ignoresSafeArea())
            .navigationTitle("Now")
            // On the stack, not inside the TimelineView branch the clock rebuilds.
            .sheet(isPresented: $showingStartSomething, onDismiss: showPendingAlert) {
                StartSomethingSheet(
                    candidates: quickStartCandidates,
                    onPick: { item in
                        showingStartSomething = false
                        start(item, blockID: nil, afterSheet: true)
                    },
                    onCreatedTask: { id in
                        showingStartSomething = false
                        startTask(id, blockID: todaysBlockID(forTask: id), afterSheet: true)
                    },
                    onCreatedHabit: { id in
                        showingStartSomething = false
                        startHabit(id, blockID: nil, afterSheet: true)
                    }
                )
            }
        }
        .modifier(NowPresentations(
            confirmingFinish: $confirmingFinish,
            detail: $detail,
            showingError: $showingError,
            errorMessage: errorMessage,
            onFinish: finish
        ))
    }

    @ViewBuilder
    private func content(now: Date) -> some View {
        let _ = scenePhase
        switch loadInput(now: now) {
        case .failure:
            ContentUnavailableView("Couldn't load Now", systemImage: "exclamationmark.triangle", description: Text("Try again in a moment."))
        case .success(let input):
            let screen = NowResolver(boundary: dayBoundary)
                .resolve(now: now, blocks: input.blocks, openSession: input.openSession)
            // The group is centered when it fits and scrolls when it
            // doesn't (large Dynamic Type): `minHeight` is the viewport.
            GeometryReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 32) {
                        main(screen.state, now: now)
                        if let next = screen.upNext { upNext(next) }
                    }
                    .frame(maxWidth: Self.maxContentWidth)
                    .padding()
                    .frame(maxWidth: .infinity, minHeight: proxy.size.height, alignment: .center)
                }
            }
        }
    }

    private func loadInput(now: Date) -> Result<NowInputBuilder.Input, Error> {
        do {
            return .success(try builder.build(now: now, in: modelContext))
        } catch {
            // Domain and code only: no titles or other user data.
            let nsError = error as NSError
            Self.logger.error("Now input failed: \(nsError.domain, privacy: .public) \(nsError.code, privacy: .public)")
            return .failure(error)
        }
    }

    @ViewBuilder
    private func main(_ state: NowState, now: Date) -> some View {
        switch state {
        case .running(let open, let range), .paused(let open, let range):
            NowSessionCard(
                open: open, plannedRange: range, now: now,
                onTitle: { detail = open.item },
                onPause: { run { try tracker.pause(in: modelContext) } },
                onResume: { run { try tracker.resume(in: modelContext) } },
                onFinish: { confirmingFinish = true }
            )
        case .suggestedCurrent(let block):
            NowSuggestionCard(block: block, isCurrent: true, now: now, onTitle: { detail = block.item }) {
                start(block.item, blockID: block.id)
            }
        case .suggestedNext(let block):
            NowSuggestionCard(block: block, isCurrent: false, now: now, onTitle: { detail = block.item }) {
                start(block.item, blockID: block.id)
            }
            startSomethingButton
        case .empty:
            // ContentUnavailableView fills the height it is offered, which
            // would push the button to the bottom: size it to its content.
            NowEmptyState()
                .fixedSize(horizontal: false, vertical: true)
            startSomethingButton
        }
    }

    private var startSomethingButton: some View {
        Button("Start something…", action: presentStartSomething)
            .buttonStyle(.bordered)
            .controlSize(.large)
            .frame(maxWidth: .infinity, alignment: .center)
            .accessibilityIdentifier(AccessibilityID.Now.startSomething)
    }

    private func upNext(_ block: NowBlock) -> some View {
        let time = block.start.formatted(date: .omitted, time: .shortened)
        return VStack(alignment: .leading, spacing: 4) {
            Text("Up next").font(.subheadline).foregroundStyle(Color.kadoForegroundSecondary)
            HStack(spacing: 6) {
                Text(verbatim: block.item.title)
                Text(block.start, format: .dateTime.hour().minute())
                    .foregroundStyle(Color.kadoForegroundSecondary)
            }
            .font(.body)
            .foregroundStyle(Color.kadoForeground)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(localized: "Up next: \(block.item.title) at \(time)"))
        .accessibilityIdentifier(AccessibilityID.Now.upNext)
    }

    private var builder: NowInputBuilder {
        NowInputBuilder(boundary: dayBoundary, evaluator: frequencyEvaluator)
    }

    private var tracker: WorkSessionTracker { WorkSessionTracker(boundary: dayBoundary) }

    /// Finishing can change a habit's day, so widgets and reminders refresh after a successful save.
    private func finish(markDone: Bool) {
        run {
            try tracker.finish(markDone: markDone, in: modelContext)
            WidgetReloader.reloadAll(using: modelContext)
        }
    }

    /// The New buttons work without candidates, so a failed load still opens the sheet.
    private func presentStartSomething() {
        switch loadInput(now: .now) {
        case .success(let input): quickStartCandidates = input.startCandidates
        case .failure: quickStartCandidates = []
        }
        showingStartSomething = true
    }

    private func showPendingAlert() {
        guard let message = pendingAlert else { return }
        pendingAlert = nil
        errorMessage = message
        showingError = true
    }

    /// Resolves the item's records by UUID at the moment of the action.
    private func start(_ item: NowItem, blockID: UUID?, afterSheet: Bool = false) {
        switch item {
        case .task(let id, _): startTask(id, blockID: blockID, afterSheet: afterSheet)
        case .habit(let id, _): startHabit(id, blockID: blockID, afterSheet: afterSheet)
        }
    }

    private func startTask(_ id: UUID, blockID: UUID?, afterSheet: Bool) {
        run(afterSheet: afterSheet) {
            guard let task = try modelContext.fetch(FetchDescriptor<TaskRecord>(predicate: #Predicate { $0.id == id })).first else { return }
            try tracker.start(task: task, block: try block(blockID), in: modelContext)
        }
    }

    private func startHabit(_ id: UUID, blockID: UUID?, afterSheet: Bool) {
        run(afterSheet: afterSheet) {
            guard let habit = try modelContext.fetch(FetchDescriptor<HabitRecord>(predicate: #Predicate { $0.id == id })).first else { return }
            try tracker.start(habit: habit, block: try block(blockID), in: modelContext)
        }
    }

    private func block(_ id: UUID?) throws -> ScheduleBlockRecord? {
        guard let id else { return nil }
        return try modelContext.fetch(FetchDescriptor<ScheduleBlockRecord>(predicate: #Predicate { $0.id == id })).first
    }

    /// A new task's planned block, when it starts today: the session links
    /// to it, so the card shows the planned range. A block on another day
    /// is not linked.
    private func todaysBlockID(forTask id: UUID) -> UUID? {
        guard let task = try? modelContext.fetch(FetchDescriptor<TaskRecord>(predicate: #Predicate { $0.id == id })).first else { return nil }
        let today = dayBoundary.startOfDay(for: .now)
        return (task.scheduleBlocks ?? []).first { block in
            guard let start = block.startAt else { return false }
            return dayBoundary.startOfDay(for: start) == today
        }?.id
    }

    /// A stale tap (the session was opened or closed elsewhere) is a no-op:
    /// the screen already re-renders to the real state. Anything else alerts —
    /// after the sheet has closed when `afterSheet`, so the alert isn't dropped.
    private func run(afterSheet: Bool = false, _ action: () throws -> Void) {
        do {
            try action()
        } catch WorkSessionTracker.TrackerError.sessionAlreadyOpen {
            return
        } catch WorkSessionTracker.TrackerError.noOpenSession {
            return
        } catch {
            report(error, afterSheet: afterSheet)
        }
    }

    /// Logs the failure and alerts, after the sheet has closed when `afterSheet`.
    private func report(_ error: Error, afterSheet: Bool) {
        let nsError = error as NSError
        Self.logger.error("Now action failed: \(nsError.domain, privacy: .public) \(nsError.code, privacy: .public)")
        if afterSheet {
            pendingAlert = "Couldn't save your change. Try again."
        } else {
            errorMessage = "Couldn't save your change. Try again."
            showingError = true
        }
    }
}

/// The finish dialog, the title's detail sheet and the error alert.
private struct NowPresentations: ViewModifier {
    @Binding var confirmingFinish: Bool
    @Binding var detail: NowItem?
    @Binding var showingError: Bool
    let errorMessage: LocalizedStringResource
    let onFinish: (Bool) -> Void

    func body(content: Content) -> some View {
        content
            .confirmationDialog("Finish this session?", isPresented: $confirmingFinish, titleVisibility: .visible) {
                Button("Done") { onFinish(true) }
                    .accessibilityIdentifier(AccessibilityID.Now.finishDone)
                Button("Not yet") { onFinish(false) }
                    .accessibilityIdentifier(AccessibilityID.Now.finishNotYet)
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Done marks it complete. Not yet keeps it open for later.")
            }
            .sheet(item: $detail) { item in
                switch item {
                case .task(let id, _): TaskFormView(taskID: id)
                case .habit(let id, _): NavigationStack { HabitDetailLoader(habitID: id) }
                }
            }
            .alert("Unable to update", isPresented: $showingError) {
                Button("Close", role: .cancel) {}
            } message: {
                Text(errorMessage)
            }
    }
}

/// In-memory store with every type the screen reads, empty: the screen
/// shows its empty state. The other states are previewed on their cards.
@MainActor
private func nowPreviewContainer() -> ModelContainer {
    do {
        return try ModelContainer(
            for: HabitRecord.self, CompletionRecord.self, TaskRecord.self, ScheduleBlockRecord.self,
            GoalRecord.self, WorkSessionRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    } catch {
        fatalError("Failed to construct preview ModelContainer: \(error)")
    }
}

#Preview("Empty") {
    NowView()
        .modelContainer(nowPreviewContainer())
        .kadoTheme()
}

#Preview("Empty, Dark") {
    NowView()
        .modelContainer(nowPreviewContainer())
        .kadoTheme()
        .preferredColorScheme(.dark)
}
