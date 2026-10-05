import OSLog
import SwiftData
import SwiftUI
import KadoCore

/// The Overview tab's History mode: every day something was done, one
/// section per day, newest first by default, loaded a page at a time as
/// the user scrolls.
///
/// Reads the same values as the Insights (`InsightsInputBuilder`), so a
/// task's category and a habit's goal resolve the same way on both.
/// The store is read again only when a record changes; a new search or
/// filter re-runs `HistoryBuilder` on the values already read, off the
/// main actor.
///
/// Tapping a task opens its form; tapping a habit pushes its detail.
/// A long-press offers the one correction History needs: mark a task
/// not done, or delete a habit record.
///
/// This view watches the store and makes the corrections;
/// `HistoryContent` holds the search, the filters and the list. Typing
/// then re-renders the list alone, and never walks every record again.
struct HistoryScreen: View {
    @Binding var path: NavigationPath
    /// What the History last showed, kept across a mode switch.
    let cache: OverviewCache

    @Environment(\.modelContext) private var modelContext
    @Environment(\.calendar) private var calendar

    // Read so a change to the store triggers a new read, and so a
    // correction resolves its record against the store as it is now.
    @Query private var habitRecords: [HabitRecord]
    @Query private var completionRecords: [CompletionRecord]
    @Query private var taskRecords: [TaskRecord]
    @Query private var sessionRecords: [WorkSessionRecord]
    @Query private var goalRecords: [GoalRecord]

    @State private var errorMessage: String?

    var body: some View {
        HistoryContent(
            path: $path,
            cache: cache,
            storeKey: storeKey,
            markTaskNotDone: markTaskNotDone,
            deleteHabitRecord: deleteHabitRecord
        )
        .alert("Couldn't save", isPresented: errorBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    /// Changes whenever a record the History reads changes.
    private var storeKey: Int {
        var hasher = Hasher()
        for record in completionRecords {
            hasher.combine(record.id)
            hasher.combine(record.value)
            hasher.combine(record.date)
            hasher.combine(record.note)
        }
        for record in taskRecords {
            hasher.combine(record.id)
            hasher.combine(record.updatedAt)
            hasher.combine(record.completedAt)
            hasher.combine(record.categoryRaw)
        }
        for record in sessionRecords {
            hasher.combine(record.id)
            hasher.combine(record.endedAt)
            hasher.combine(record.pausedSeconds)
        }
        for record in habitRecords {
            hasher.combine(record.id)
            hasher.combine(record.name)
            hasher.combine(record.icon)
            hasher.combine(record.color)
            hasher.combine(record.categoryRaw)
        }
        for record in goalRecords {
            hasher.combine(record.id)
            hasher.combine(record.name)
        }
        return hasher.finalize()
    }

    // MARK: - Corrections

    private func markTaskNotDone(_ id: UUID) {
        guard let record = taskRecords.first(where: { $0.id == id }) else { return }
        record.completedAt = nil
        record.updatedAt = .now
        save()
    }

    private func deleteHabitRecord(_ id: UUID) {
        guard let record = completionRecords.first(where: { $0.id == id }) else { return }
        CompletionLogger(calendar: calendar).delete(record, in: modelContext)
        save()
        WidgetReloader.reloadAll(using: modelContext)
    }

    private func save() {
        do { try modelContext.save() }
        catch {
            modelContext.rollback()
            errorMessage = error.localizedDescription
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
    }
}

/// The History's list, search and filters. See `HistoryScreen`.
private struct HistoryContent: View {
    @Binding var path: NavigationPath
    let cache: OverviewCache
    /// Moves whenever a record the History reads changes.
    let storeKey: Int
    let markTaskNotDone: (UUID) -> Void
    let deleteHabitRecord: (UUID) -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(\.calendar) private var calendar
    @Environment(\.civilToday) private var civilToday
    @Environment(\.dayBoundary) private var dayBoundary

    @AppStorage(OverviewModeDefaults.historyKindKey) private var kind: HistoryKind = .all
    @AppStorage(OverviewModeDefaults.historyDayOrderKey) private var dayOrder: HistoryDayOrder = .newestFirst
    @AppStorage(OverviewModeDefaults.historyItemOrderKey) private var itemOrder: HistoryItemOrder = .time
    /// Not remembered: a category pick is a quick look, not a setting.
    @State private var categories: Set<ItemCategory> = []
    @State private var search = ""

    /// The values last read from the store, and a counter that moves
    /// each time they are read again.
    @State private var input: InsightsInput?
    @State private var inputRevision = 0
    /// Worked out once per read rather than on every keystroke.
    @State private var availableCategories: [ItemCategory] = []
    @State private var firstDay: Date?
    /// The days for the current query. Kept while new ones compute, so
    /// the list never flashes empty.
    @State private var days: [HistoryDay]?
    /// What `days` was computed for.
    @State private var daysKey: ComputeKey?
    @State private var editingTaskID: EditingTask?
    @State private var showsJump = false

    private static let logger = Logger(subsystem: "dev.scastiel.kado", category: "history")
    /// How long typing has to pause before the list is filtered again.
    private static let searchDebounce: Duration = .milliseconds(250)

    struct EditingTask: Identifiable {
        let id: UUID
    }

    var body: some View {
        content
            .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .automatic), prompt: Text("Search history"))
            .toolbar { toolbar }
            .navigationDestination(for: HabitRoute.self) { route in
                HabitDetailLoader(habitID: route.id)
            }
            .sheet(item: $editingTaskID) { task in
                TaskFormView(taskID: task.id)
            }
            .sheet(isPresented: $showsJump) {
                HistoryJumpSheet(range: jumpRange) { day in
                    jumpTarget = day
                }
            }
            .task(id: InputKey(civilToday: civilToday, data: storeKey)) { readInput() }
            .task(id: computeKey) { await compute() }
    }

    /// Set by the jump sheet; the feed scrolls to it and clears it.
    @State private var jumpTarget: Date?

    @ViewBuilder
    private var content: some View {
        if let shown {
            HistoryFeed(
                days: shown.days,
                query: query,
                availableCategories: shown.availableCategories,
                firstDay: shown.firstDay,
                kind: $kind,
                categories: $categories,
                jumpTarget: $jumpTarget,
                actions: actions
            )
        } else {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.kadoBackground.ignoresSafeArea())
        }
    }

    /// What the feed shows: this screen's own result, else, until the
    /// first one lands, the last one Overview kept for the same query.
    private var shown: (days: [HistoryDay], availableCategories: [ItemCategory], firstDay: Date?)? {
        if let days, input != nil {
            return (days, availableCategories, firstDay)
        }
        if let kept = cache.history(for: query, startHour: dayBoundary.startHour, civilToday: civilToday) {
            return (kept.days, kept.availableCategories, kept.firstDay)
        }
        return nil
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .topBarTrailing) {
            Button {
                showsJump = true
            } label: {
                Label("Go to date", systemImage: "calendar")
            }
            .disabled(shown?.days.isEmpty ?? true)
            .accessibilityIdentifier(AccessibilityID.History.jumpButton)

            Menu {
                Picker("Days", selection: $dayOrder) {
                    Text("Newest first").tag(HistoryDayOrder.newestFirst)
                    Text("Oldest first").tag(HistoryDayOrder.oldestFirst)
                }
                Picker("Within a day", selection: $itemOrder) {
                    Label("By time", systemImage: "clock").tag(HistoryItemOrder.time)
                    Label("By category", systemImage: "square.grid.2x2").tag(HistoryItemOrder.category)
                    Label("By name", systemImage: "textformat").tag(HistoryItemOrder.name)
                }
            } label: {
                Label("Sort", systemImage: "arrow.up.arrow.down")
            }
            .accessibilityIdentifier(AccessibilityID.History.sortMenu)
        }
    }

    // MARK: - Query and data

    private var query: HistoryQuery {
        HistoryQuery(kind: kind, categories: categories, search: search, dayOrder: dayOrder, itemOrder: itemOrder)
    }

    private struct InputKey: Equatable {
        var civilToday: Date
        var data: Int
    }

    private var computeKey: ComputeKey {
        ComputeKey(query: query, revision: inputRevision, startHour: dayBoundary.startHour)
    }

    private struct ComputeKey: Equatable {
        var query: HistoryQuery
        var revision: Int
        var startHour: Int

        /// Whether `self` is `other` with only the search text changed.
        func differsOnlyInSearch(from other: ComputeKey) -> Bool {
            var same = other
            same.query.search = query.search
            return same == self && other.query.search != query.search
        }
    }

    private func readInput() {
        let read: InsightsInput
        if UITestSupport.showsInsightsFixture {
            read = HistoryPreviewData.input
        } else {
            do {
                // The History never shows goal progress.
                read = try InsightsInputBuilder(civilToday: civilToday, calendar: calendar)
                    .build(in: modelContext, includeGoalProgress: false)
            } catch {
                Self.logger.error("History read failed: \(error.localizedDescription, privacy: .public)")
                read = InsightsInput()
            }
        }
        input = read
        availableCategories = Self.availableCategories(in: read)
        firstDay = firstDay(in: read)
        inputRevision += 1
    }

    private func compute() async {
        guard let input else { return }
        let key = computeKey
        // Each keystroke restarts this task, which cancels the sleep:
        // the list is filtered once typing pauses, not per character.
        if let daysKey, key.differsOnlyInSearch(from: daysKey) {
            try? await Task.sleep(for: Self.searchDebounce)
            guard !Task.isCancelled else { return }
        }
        let query = key.query
        let calendar = calendar
        let dayBoundary = dayBoundary
        let work = Task.detached(priority: .userInitiated) {
            HistoryBuilder.days(input: input, query: query, calendar: calendar, dayBoundary: dayBoundary)
        }
        let result = await withTaskCancellationHandler {
            await work.value
        } onCancel: {
            work.cancel()
        }
        // A newer query or read has started: its result wins.
        guard !Task.isCancelled else { return }
        days = result
        daysKey = key
        cache.store(OverviewCache.History(
            civilToday: civilToday,
            startHour: key.startHour,
            query: query,
            days: result,
            availableCategories: availableCategories,
            firstDay: firstDay
        ))
    }

    /// Categories with at least one done item, in category order, so a
    /// chip never leads to an empty page.
    private static func availableCategories(in input: InsightsInput) -> [ItemCategory] {
        var present = Set<ItemCategory>()
        for task in input.tasks where task.completedAt != nil && !task.isCancelled {
            present.insert(task.category)
        }
        for habit in input.habits where habit.completions.contains(where: { $0.value > 0 }) {
            present.insert(habit.category)
        }
        return ItemCategory.allCases.filter(present.contains)
    }

    /// The oldest day with anything done, whatever the filters.
    private func firstDay(in input: InsightsInput) -> Date? {
        let taskDays = input.tasks.compactMap(\.completedAt)
        let habitDays = input.habits.flatMap { $0.completions.filter { $0.value > 0 }.map(\.date) }
        return (taskDays + habitDays).min().map { calendar.startOfDay(for: $0) }
    }

    private var jumpRange: ClosedRange<Date> {
        let shown = shown?.days.map(\.day) ?? []
        let first = shown.min() ?? civilToday
        let last = max(shown.max() ?? civilToday, civilToday)
        return first...last
    }

    // MARK: - Actions

    private var actions: HistoryActions {
        HistoryActions(
            openTask: { editingTaskID = EditingTask(id: $0) },
            openHabit: { path.append(HabitRoute(id: $0)) },
            markTaskNotDone: markTaskNotDone,
            deleteHabitRecord: deleteHabitRecord
        )
    }
}

/// What a History row can ask the screen to do. Every closure takes an
/// id, never a record (see "views address habits by UUID" in CLAUDE.md).
struct HistoryActions {
    var openTask: (UUID) -> Void = { _ in }
    var openHabit: (UUID) -> Void = { _ in }
    var markTaskNotDone: (UUID) -> Void = { _ in }
    /// Takes the completion's id.
    var deleteHabitRecord: (UUID) -> Void = { _ in }
}

#Preview("Populated") {
    NavigationStack {
        HistoryScreen(path: .constant(NavigationPath()), cache: OverviewCache())
            .navigationTitle("Overview")
    }
    .modelContainer(PreviewContainer.shared)
}

#Preview("Dark") {
    NavigationStack {
        HistoryScreen(path: .constant(NavigationPath()), cache: OverviewCache())
            .navigationTitle("Overview")
    }
    .modelContainer(PreviewContainer.shared)
    .preferredColorScheme(.dark)
}
