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
struct HistoryScreen: View {
    @Binding var path: NavigationPath

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

    // Read only so a change to the store triggers a new read.
    @Query private var habitRecords: [HabitRecord]
    @Query private var completionRecords: [CompletionRecord]
    @Query private var taskRecords: [TaskRecord]
    @Query private var sessionRecords: [WorkSessionRecord]
    @Query private var goalRecords: [GoalRecord]

    /// The values last read from the store, and a counter that moves
    /// each time they are read again.
    @State private var input: InsightsInput?
    @State private var inputRevision = 0
    /// The days for the current query. Kept while new ones compute, so
    /// the list never flashes empty.
    @State private var days: [HistoryDay]?
    @State private var editingTaskID: EditingTask?
    @State private var showsJump = false
    @State private var errorMessage: String?

    private static let logger = Logger(subsystem: "dev.scastiel.kado", category: "history")

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
            .alert("Couldn't save", isPresented: errorBinding) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
            .task(id: inputKey) { readInput() }
            .task(id: computeKey) { await compute() }
    }

    /// Set by the jump sheet; the feed scrolls to it and clears it.
    @State private var jumpTarget: Date?

    @ViewBuilder
    private var content: some View {
        if let days, let input {
            HistoryFeed(
                days: days,
                query: query,
                availableCategories: availableCategories(in: input),
                firstDay: firstDay(in: input),
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

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .topBarTrailing) {
            Button {
                showsJump = true
            } label: {
                Label("Go to date", systemImage: "calendar")
            }
            .disabled(days?.isEmpty ?? true)
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

    /// Changes whenever a record the History reads changes.
    private var inputKey: InputKey {
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
        return InputKey(civilToday: civilToday, data: hasher.finalize())
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
    }

    private func readInput() {
        if UITestSupport.showsInsightsFixture {
            input = HistoryPreviewData.input
            inputRevision += 1
            return
        }
        do {
            input = try InsightsInputBuilder(civilToday: civilToday, calendar: calendar).build(in: modelContext)
            inputRevision += 1
        } catch {
            Self.logger.error("History read failed: \(error.localizedDescription, privacy: .public)")
            input = InsightsInput()
            inputRevision += 1
        }
    }

    private func compute() async {
        guard let input else { return }
        let query = query
        let calendar = calendar
        let dayBoundary = dayBoundary
        let result = await Task.detached(priority: .userInitiated) {
            HistoryBuilder.days(input: input, query: query, calendar: calendar, dayBoundary: dayBoundary)
        }.value
        guard !Task.isCancelled else { return }
        days = result
    }

    /// Categories with at least one done item, in category order, so a
    /// chip never leads to an empty page.
    private func availableCategories(in input: InsightsInput) -> [ItemCategory] {
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
        let shown = days?.map(\.day) ?? []
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
        HistoryScreen(path: .constant(NavigationPath()))
            .navigationTitle("Overview")
    }
    .modelContainer(PreviewContainer.shared)
}

#Preview("Dark") {
    NavigationStack {
        HistoryScreen(path: .constant(NavigationPath()))
            .navigationTitle("Overview")
    }
    .modelContainer(PreviewContainer.shared)
    .preferredColorScheme(.dark)
}
