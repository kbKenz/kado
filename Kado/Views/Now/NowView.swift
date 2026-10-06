import OSLog
import SwiftData
import SwiftUI
import KadoCore

/// The Now tab: what runs now, what was paused today, and what is next.
///
/// This view holds what it presents (the start sheet, the detail
/// sheet, the error alert); `NowContent` reads the
/// store and draws the cards. Kept apart so the store is read once per
/// data change or day, not on every minute tick or presentation.
struct NowView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dayBoundary) private var dayBoundary
    // Read so returning to the foreground re-reads the store at once.
    @Environment(\.scenePhase) private var scenePhase

    /// The start sheet, with the candidates it lists. An item rather
    /// than a flag with the list beside it: `.sheet(isPresented:)`
    /// builds its content from a body pass that may predate the list.
    @State private var startSheet: StartSheet?
    @State private var detail: NowItem?
    @State private var showingError = false
    @State private var errorMessage: LocalizedStringResource = "Couldn't save your change. Try again."
    /// Set while the sheet closes; shown from `onDismiss`, because an alert
    /// raised while a sheet is still leaving can be dropped.
    @State private var pendingAlert: LocalizedStringResource?

    fileprivate static let logger = Logger(subsystem: "dev.scastiel.kado", category: "now")

    var body: some View {
        NavigationStack {
            // Ticks every minute to notice the rollover; `NowContent`
            // keeps its own clock for the cards.
            TimelineView(.everyMinute) { context in
                // `max` with the wall clock: after backgrounding, the first
                // frame can carry a stale `context.date`.
                let now = max(context.date, .now)
                NowContent(
                    day: dayBoundary.startOfDay(for: now),
                    loadedAt: now,
                    scenePhase: scenePhase,
                    actions: contentActions
                )
                .equatable()
            }
            .background(Color.kadoBackground.ignoresSafeArea())
            .navigationTitle("Now")
            // On the stack, not inside the TimelineView branch the clock rebuilds.
            .sheet(item: $startSheet, onDismiss: showPendingAlert) { sheet in
                StartSomethingSheet(
                    candidates: sheet.candidates,
                    onPick: { item in
                        startSheet = nil
                        afterSheet { try commands.start(item, blockID: nil) }
                    },
                    onCreatedTask: { id in
                        startSheet = nil
                        afterSheet { try commands.startTask(id, blockID: commands.todaysBlockID(forTask: id)) }
                    },
                    onCreatedHabit: { id in
                        startSheet = nil
                        afterSheet { try commands.startHabit(id, blockID: nil) }
                    }
                )
            }
        }
        .modifier(NowPresentations(
            detail: $detail,
            showingError: $showingError,
            errorMessage: errorMessage
        ))
    }

    /// Each one only writes this view's state. `NowContent` keeps the
    /// closures from an earlier pass when it skips an update, so they
    /// must not read anything that pass captured.
    private var contentActions: NowContent.Actions {
        NowContent.Actions(
            showDetail: { detail = $0 },
            startSomething: { candidates in
                startSheet = StartSheet(candidates: candidates)
            },
            reportFailure: {
                errorMessage = "Couldn't save your change. Try again."
                showingError = true
            }
        )
    }

    private var commands: NowCommands {
        NowCommands(context: modelContext, boundary: dayBoundary)
    }

    /// Alerts once the sheet has closed, so the alert isn't dropped.
    private func afterSheet(_ action: () throws -> Void) {
        let context = modelContext
        guard NowCommands.run({
            try action()
            // Starting pauses what ran, which can log a timer habit's time.
            WidgetReloader.reloadAll(using: context)
        }) else { return }
        pendingAlert = "Couldn't save your change. Try again."
    }

    private func showPendingAlert() {
        guard let message = pendingAlert else { return }
        pendingAlert = nil
        errorMessage = message
        showingError = true
    }
}

/// What the start sheet lists, loaded once when it is requested.
private struct StartSheet: Identifiable {
    let id = UUID()
    let candidates: [NowItem]
}

/// The cards, read from the store once per data change.
///
/// Its queries are what re-render it after a save; `NowInputBuilder`
/// fetches its own records and returns values. `day` and `scenePhase`
/// are the only inputs that re-read the store from the parent, so a
/// minute tick or a presentation on `NowView` costs nothing here — the
/// minute only moves `NowResolver`, which runs in the inner clock.
struct NowContent: View, Equatable {
    let day: Date
    /// When the parent built this value. Only a lower bound for the
    /// load: a pass the parent did not cause keeps an older one.
    let loadedAt: Date
    let scenePhase: ScenePhase
    let actions: Actions

    struct Actions {
        var showDetail: (NowItem) -> Void
        var startSomething: ([NowItem]) -> Void
        var reportFailure: () -> Void
    }

    nonisolated static func == (lhs: NowContent, rhs: NowContent) -> Bool {
        lhs.day == rhs.day && lhs.scenePhase == rhs.scenePhase
    }

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dayBoundary) private var dayBoundary
    @Environment(\.frequencyEvaluator) private var frequencyEvaluator

    // These queries only trigger a re-render after data changes; the
    // builder fetches its own records and returns values.
    @Query(filter: #Predicate<WorkSessionRecord> { $0.endedAt == nil }) private var sessions: [WorkSessionRecord]
    @Query private var blocks: [ScheduleBlockRecord]
    @Query private var tasks: [TaskRecord]
    @Query private var habits: [HabitRecord]
    @Query private var completions: [CompletionRecord]

    /// Readable column width, so iPad does not stretch the cards.
    private static let maxContentWidth: CGFloat = 560

    var body: some View {
        // Not `loadedAt` alone: a data change or a new day boundary
        // re-runs this body with the props of the last pass that was
        // not skipped, and that instant can be hours old. Under a moved
        // "Day starts at" it can even fall on the previous logical day.
        // `max` keeps the parent's clock when it runs ahead of `.now`.
        let input = loadInput(now: max(loadedAt, .now))
        // Re-resolve every minute so suggestions move with the clock.
        TimelineView(.everyMinute) { context in
            content(input, now: max(context.date, .now))
        }
    }

    @ViewBuilder
    private func content(_ input: Result<NowInputBuilder.Input, Error>, now: Date) -> some View {
        switch input {
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
                        main(screen.state, input: input, now: now)
                        if !input.paused.isEmpty {
                            NowPausedList(
                                items: input.paused, glyphs: input.glyphs,
                                isSomethingRunning: input.openSession != nil,
                                onContinue: { item in run { try commands.continue(item) } },
                                onDone: { item in run { try commands.complete(item) } },
                                onOpen: { actions.showDetail($0) }
                            )
                        }
                        if let next = screen.upNext { upNext(next, glyph: input.glyphs[next.item.id]) }
                        // Always offered: starting something else pauses what runs.
                        startSomethingButton(input.startCandidates)
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
            NowView.logger.error("Now input failed: \(nsError.domain, privacy: .public) \(nsError.code, privacy: .public)")
            return .failure(error)
        }
    }

    @ViewBuilder
    private func main(_ state: NowState, input: NowInputBuilder.Input, now: Date) -> some View {
        let glyphs = input.glyphs
        switch state {
        case .running(let open, let range):
            let progress = input.runningProgress ?? NowProgress(item: open.item, runs: [], countedSeconds: 0)
            NowSessionCard(
                open: open, plannedRange: range, progress: progress, now: now, glyph: glyphs[open.item.id],
                onTitle: { actions.showDetail(open.item) },
                onPause: { run { try commands.tracker.pause(in: modelContext) } },
                onDone: progress.canMarkDone ? { run { try commands.complete(open.item) } } : nil
            )
        case .suggestedCurrent(let block):
            NowSuggestionCard(block: block, isCurrent: true, now: now, glyph: glyphs[block.item.id],
                              onTitle: { actions.showDetail(block.item) }) {
                run { try commands.start(block.item, blockID: block.id) }
            }
        case .suggestedNext(let block):
            NowSuggestionCard(block: block, isCurrent: false, now: now, glyph: glyphs[block.item.id],
                              onTitle: { actions.showDetail(block.item) }) {
                run { try commands.start(block.item, blockID: block.id) }
            }
        case .empty:
            // Paused work is what to show then; the empty state would
            // say there is nothing to do.
            if input.paused.isEmpty {
                // ContentUnavailableView fills the height it is offered, which
                // would push the button to the bottom: size it to its content.
                NowEmptyState()
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// The New buttons work without candidates, so a failed load still
    /// opens the sheet (with none). The candidates are the ones this
    /// pass loaded, which is the store as it is now.
    private func startSomethingButton(_ candidates: [NowItem]) -> some View {
        Button("Start something…") { actions.startSomething(candidates) }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .frame(maxWidth: .infinity, alignment: .center)
            .accessibilityIdentifier(AccessibilityID.Now.startSomething)
    }

    private func upNext(_ block: NowBlock, glyph: ItemGlyph?) -> some View {
        let time = block.start.formatted(date: .omitted, time: .shortened)
        return VStack(alignment: .leading, spacing: 4) {
            Text("Up next").font(.subheadline).foregroundStyle(Color.kadoForegroundSecondary)
            // One line when it fits; otherwise the time goes under the
            // title, so a long title or large text is not squeezed.
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    upNextTitle(block, glyph: glyph)
                    upNextTime(block)
                }
                VStack(alignment: .leading, spacing: 2) {
                    upNextTitle(block, glyph: glyph)
                    upNextTime(block)
                }
            }
            .font(.body)
            .foregroundStyle(Color.kadoForeground)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(localized: "Up next: \(block.item.title) at \(time)"))
        .accessibilityIdentifier(AccessibilityID.Now.upNext)
    }

    private func upNextTitle(_ block: NowBlock, glyph: ItemGlyph?) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            if let glyph { ItemGlyphView(glyph: glyph) }
            Text(verbatim: block.item.title)
        }
    }

    private func upNextTime(_ block: NowBlock) -> some View {
        Text(block.start, format: .dateTime.hour().minute())
            .foregroundStyle(Color.kadoForegroundSecondary)
    }

    private var builder: NowInputBuilder {
        NowInputBuilder(boundary: dayBoundary, evaluator: frequencyEvaluator)
    }

    private var commands: NowCommands {
        NowCommands(context: modelContext, boundary: dayBoundary)
    }

    /// Pausing, switching or finishing can log a habit's time, so
    /// widgets and reminders refresh after a successful save.
    private func run(_ action: () throws -> Void) {
        let context = modelContext
        if NowCommands.run({
            try action()
            WidgetReloader.reloadAll(using: context)
        }) { actions.reportFailure() }
    }
}

/// What a tap on Now does to the store, against the caller's own
/// context and day boundary. Resolves records by UUID at the moment of
/// the action.
private struct NowCommands {
    let context: ModelContext
    let boundary: DayBoundary

    var tracker: WorkSessionTracker { WorkSessionTracker(boundary: boundary) }

    func start(_ item: NowItem, blockID: UUID?) throws {
        switch item {
        case .task(let id, _): try startTask(id, blockID: blockID)
        case .habit(let id, _): try startHabit(id, blockID: blockID)
        }
    }

    func startTask(_ id: UUID, blockID: UUID?) throws {
        guard let task = try context.fetch(FetchDescriptor<TaskRecord>(predicate: #Predicate { $0.id == id })).first else { return }
        try tracker.start(task: task, block: try block(blockID), in: context)
    }

    func startHabit(_ id: UUID, blockID: UUID?) throws {
        guard let habit = try context.fetch(FetchDescriptor<HabitRecord>(predicate: #Predicate { $0.id == id })).first else { return }
        try tracker.start(habit: habit, block: try block(blockID), in: context)
    }

    /// Starts `item` again, linked to its block today if it has one.
    func `continue`(_ item: NowItem) throws {
        switch item {
        case .task(let id, _): try startTask(id, blockID: todaysBlockID(forTask: id))
        case .habit(let id, _): try startHabit(id, blockID: todaysBlockID(forHabit: id))
        }
    }

    func complete(_ item: NowItem) throws {
        switch item {
        case .task(let id, _):
            guard let task = try context.fetch(FetchDescriptor<TaskRecord>(predicate: #Predicate { $0.id == id })).first else { return }
            try tracker.complete(task: task, in: context)
        case .habit(let id, _):
            guard let habit = try context.fetch(FetchDescriptor<HabitRecord>(predicate: #Predicate { $0.id == id })).first else { return }
            try tracker.complete(habit: habit, in: context)
        }
    }

    private func block(_ id: UUID?) throws -> ScheduleBlockRecord? {
        guard let id else { return nil }
        return try context.fetch(FetchDescriptor<ScheduleBlockRecord>(predicate: #Predicate { $0.id == id })).first
    }

    /// A new task's planned block, when it starts today: the session links
    /// to it, so the card shows the planned range. A block on another day
    /// is not linked.
    func todaysBlockID(forTask id: UUID) -> UUID? {
        guard let task = try? context.fetch(FetchDescriptor<TaskRecord>(predicate: #Predicate { $0.id == id })).first else { return nil }
        return todaysBlockID(in: task.scheduleBlocks ?? [])
    }

    func todaysBlockID(forHabit id: UUID) -> UUID? {
        guard let habit = try? context.fetch(FetchDescriptor<HabitRecord>(predicate: #Predicate { $0.id == id })).first else { return nil }
        return todaysBlockID(in: habit.scheduleBlocks ?? [])
    }

    private func todaysBlockID(in blocks: [ScheduleBlockRecord]) -> UUID? {
        let today = boundary.startOfDay(for: .now)
        return blocks.first { block in
            guard let start = block.startAt else { return false }
            return boundary.startOfDay(for: start) == today
        }?.id
    }

    /// Runs `action` and says whether to alert. A stale tap (the session
    /// was closed elsewhere) is a no-op: the screen already re-renders
    /// to the real state. Anything else is logged and alerts.
    static func run(_ action: () throws -> Void) -> Bool {
        do {
            try action()
            return false
        } catch WorkSessionTracker.TrackerError.noOpenSession {
            return false
        } catch {
            let nsError = error as NSError
            NowView.logger.error("Now action failed: \(nsError.domain, privacy: .public) \(nsError.code, privacy: .public)")
            return true
        }
    }
}

/// The title's detail sheet and the error alert.
private struct NowPresentations: ViewModifier {
    @Binding var detail: NowItem?
    @Binding var showingError: Bool
    let errorMessage: LocalizedStringResource

    func body(content: Content) -> some View {
        content
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
