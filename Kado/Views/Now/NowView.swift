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

    private static let logger = Logger(subsystem: "dev.scastiel.kado", category: "now")

    var body: some View {
        NavigationStack {
            // Re-resolve every minute so suggestions move with the clock.
            TimelineView(.everyMinute) { context in
                content(now: context.date)
            }
            .background(Color.kadoBackground.ignoresSafeArea())
            .navigationTitle("Now")
        }
        .modifier(NowPresentations(
            confirmingFinish: $confirmingFinish,
            detail: $detail,
            showingError: $showingError,
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
            ScrollView {
                VStack(alignment: .leading, spacing: 32) {
                    main(screen.state, now: now)
                    if let next = screen.upNext { upNext(next) }
                }
                .padding()
            }
            .sheet(isPresented: $showingStartSomething) {
                StartSomethingSheet(candidates: input.startCandidates) { item in
                    showingStartSomething = false
                    start(item, blockID: nil)
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
            NowEmptyState()
            startSomethingButton
        }
    }

    private var startSomethingButton: some View {
        Button("Start something…") { showingStartSomething = true }
            .buttonStyle(.bordered)
            .controlSize(.large)
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

    /// Resolves the item's records by UUID at the moment of the action.
    private func start(_ item: NowItem, blockID: UUID?) {
        run {
            let block = try blockID.flatMap { id in
                try modelContext.fetch(FetchDescriptor<ScheduleBlockRecord>(predicate: #Predicate { $0.id == id })).first
            }
            switch item {
            case .task(let id, _):
                guard let task = try modelContext.fetch(FetchDescriptor<TaskRecord>(predicate: #Predicate { $0.id == id })).first else { return }
                try tracker.start(task: task, block: block, in: modelContext)
            case .habit(let id, _):
                guard let habit = try modelContext.fetch(FetchDescriptor<HabitRecord>(predicate: #Predicate { $0.id == id })).first else { return }
                try tracker.start(habit: habit, block: block, in: modelContext)
            }
        }
    }

    /// A stale tap (the session was opened or closed elsewhere) is a no-op:
    /// the screen already re-renders to the real state. Anything else alerts.
    private func run(_ action: () throws -> Void) {
        do {
            try action()
        } catch WorkSessionTracker.TrackerError.sessionAlreadyOpen {
            return
        } catch WorkSessionTracker.TrackerError.noOpenSession {
            return
        } catch {
            let nsError = error as NSError
            Self.logger.error("Now action failed: \(nsError.domain, privacy: .public) \(nsError.code, privacy: .public)")
            showingError = true
        }
    }
}

/// The finish dialog, the title's detail sheet and the error alert.
private struct NowPresentations: ViewModifier {
    @Binding var confirmingFinish: Bool
    @Binding var detail: NowItem?
    @Binding var showingError: Bool
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
                Text("Couldn't save your change. Try again.")
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
