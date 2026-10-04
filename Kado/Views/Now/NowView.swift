import SwiftData
import SwiftUI
import KadoCore

/// The Now tab: one thing to work on, its tracked time, and what is next.
struct NowView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dayBoundary) private var dayBoundary
    @Environment(\.frequencyEvaluator) private var frequencyEvaluator

    // Observed only so the view re-reads after any change; the builder
    // fetches its own records and returns values.
    @Query private var sessions: [WorkSessionRecord]
    @Query private var blocks: [ScheduleBlockRecord]
    @Query private var tasks: [TaskRecord]
    @Query private var completions: [CompletionRecord]

    @State private var confirmingFinish = false
    @State private var showingStartSomething = false
    @State private var detail: NowItem?
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            // Re-resolve every minute so suggestions move with the clock.
            TimelineView(.everyMinute) { context in
                let input = (try? builder.build(now: context.date, in: modelContext))
                    ?? NowInputBuilder.Input(blocks: [], openSession: nil, startCandidates: [])
                let screen = NowResolver(boundary: dayBoundary)
                    .resolve(now: context.date, blocks: input.blocks, openSession: input.openSession)
                ScrollView {
                    VStack(alignment: .leading, spacing: 32) {
                        main(screen.state, now: context.date)
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
            .background(Color.kadoBackground.ignoresSafeArea())
            .navigationTitle("Now")
        }
        .confirmationDialog("Finish this session?", isPresented: $confirmingFinish, titleVisibility: .visible) {
            Button("Done") { finish(markDone: true) }
                .accessibilityIdentifier(AccessibilityID.Now.finishDone)
            Button("Not yet") { finish(markDone: false) }
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
        .alert("Unable to update", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("Close", role: .cancel) {}
        } message: { Text(errorMessage ?? "") }
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
        VStack(alignment: .leading, spacing: 4) {
            Text("Up next").font(.subheadline).foregroundStyle(Color.kadoForegroundSecondary)
            Text("\(block.item.title) — \(block.start, format: .dateTime.hour().minute())")
                .font(.body)
                .foregroundStyle(Color.kadoForeground)
        }
        .accessibilityElement(children: .combine)
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

    private func run(_ action: () throws -> Void) {
        do { try action() } catch { errorMessage = error.localizedDescription }
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
