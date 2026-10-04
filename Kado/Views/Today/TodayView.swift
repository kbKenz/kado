import SwiftData
import SwiftUI
import KadoCore

/// The Today tab — shows the day picked in the day strip (today by
/// default): lists habits due that day and handles tap-to-toggle
/// for binary and negative habits, inline counter / timer logging,
/// and a long-press context menu for the secondary actions
/// (specific-value sheets, edit, archive).
///
/// Every piece of state this view retains — the list rows, the
/// navigation path, the presented sheet, the pending archive
/// confirmation — holds a habit **id**, never a `HabitRecord`. A
/// dev-mode `ModelContainer` swap invalidates every managed object the
/// previous store vended, and SwiftUI re-reads its retained data
/// during the next list diff, which traps inside SwiftData. Ids
/// survive the swap; records don't (issue #63).
struct TodayView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.frequencyEvaluator) private var frequencyEvaluator
    @Environment(\.streakCalculator) private var streakCalculator
    @Environment(\.habitScoreCalculator) private var scoreCalculator
    @Environment(\.reviewPromptService) private var reviewPromptService
    @Environment(\.tipNudge) private var tipNudge
    @Environment(\.appearanceAnnouncement) private var appearanceAnnouncement
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.calendar) private var calendar
    @Environment(\.today) private var today
    @Environment(\.civilToday) private var civilToday
    @Environment(\.dayBoundary) private var dayBoundary

    @Query(
        filter: #Predicate<HabitRecord> { $0.archivedAt == nil },
        sort: \HabitRecord.sortOrder
    )
    private var activeHabits: [HabitRecord]

    @Query(
        filter: #Predicate<TaskRecord> { $0.archivedAt == nil && $0.externalCancelledAt == nil },
        sort: \TaskRecord.createdAt
    )
    private var activeTasks: [TaskRecord]

    @State private var path = NavigationPath()
    @State private var sheet: TodaySheet?
    @State private var confirmingArchiveOf: UUID?
    @State private var deletingTaskID: UUID?
    @State private var taskError: String?
    /// The latest `−` / `+` / `+5m` tap, for the haptic. Recorded by
    /// the mutation rather than observed on the row: a row keyed on
    /// its own value ticks when the day rolls over or a sync lands,
    /// and misses the tap that moves it between sections (a new
    /// `ForEach` identity sees no old → new).
    @State private var quickLog: QuickLogEvent?

    /// The card in the slot at the bottom of the list, if any — the
    /// Appearance announcement or the tip nudge, never both
    /// (`TodayCard`). Seeded in `.onAppear` rather than in the
    /// property's initial value, because `@State` is set up before the
    /// environment is injected and would capture the `@Entry` defaults
    /// instead of whatever the app injected (CLAUDE.md, SwiftUI
    /// section).
    @State private var card: TodayCard?

    /// The day the list shows. `nil` means today, so the selection
    /// follows the rollover instead of sticking to yesterday.
    @State private var selectedDay: Date?

    /// Single source of truth for sheets the Today surface presents.
    /// Replaces the boolean soup that would otherwise emerge from
    /// New / Edit / Log-counter / Log-timer running in parallel.
    enum TodaySheet: Identifiable {
        case newHabit
        case newTask
        case editTask(UUID)
        case editHabit(UUID)
        case logCounter(UUID, Date)
        case logTimer(UUID, Date)
        /// The Tip Jar, reached from the nudge at the bottom of the
        /// list. A sheet rather than a `navigationDestination`, so the
        /// detour doesn't leave the Tip Jar sitting on Today's
        /// navigation stack once it's done.
        case tipJar
        /// Settings › Appearance, reached from the announcement card.
        /// A sheet for the same reason as the Tip Jar.
        case appearance

        var id: String {
            switch self {
            case .newHabit: "new"
            case .newTask: "new-task"
            case .editTask(let id): "edit-task-\(id)"
            case .editHabit(let habitID): "edit-\(habitID)"
            case .logCounter(let habitID, let day): "counter-\(habitID)-\(day.timeIntervalSinceReferenceDate)"
            case .logTimer(let habitID, let day): "timer-\(habitID)-\(day.timeIntervalSinceReferenceDate)"
            case .tipJar: "tip-jar"
            case .appearance: "appearance"
            }
        }
    }

    var body: some View {
        // Snapshotted once per pass, so the strip's cells share it
        // instead of each re-snapshotting every habit.
        let days = stripDays
        let progressInput = stripProgressInput
        NavigationStack(path: $path) {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.kadoBackground.ignoresSafeArea())
                .safeAreaInset(edge: .top, spacing: 0) {
                    DayStrip(
                        days: days,
                        selection: stripSelection,
                        today: today,
                        progress: { stripProgress(for: $0, input: progressInput) }
                    )
                    // A horizontal ScrollView is greedy vertically and
                    // would take the whole inset, pushing the list away.
                    .fixedSize(horizontal: false, vertical: true)
                    .background(Color.kadoBackground, ignoresSafeAreaEdges: [])
                }
                .onChange(of: today) { _, newToday in
                    // A day picked while it was in the future follows
                    // today again once it becomes today.
                    if let selectedDay, calendar.isDate(selectedDay, inSameDayAs: newToday) {
                        self.selectedDay = nil
                    }
                }
                .onChange(of: days) { _, days in
                    if let selectedDay,
                       let clamped = DayStripRange.clamp(selectedDay, to: days),
                       clamped != selectedDay {
                        self.selectedDay = calendar.isDate(clamped, inSameDayAs: today) ? nil : clamped
                    }
                }
                .navigationTitle(titleText)
                .navigationDestination(for: HabitRoute.self) { route in
                    HabitDetailLoader(habitID: route.id)
                }
                .toolbar {
                    if dayKind != .today {
                        ToolbarItem(placement: .topBarLeading) {
                            Button("Today") { selectedDay = nil }
                                .accessibilityIdentifier(AccessibilityID.Today.jumpToTodayButton)
                        }
                    }
                    ToolbarItem(placement: .primaryAction) {
                        Menu {
                            Button { sheet = .newTask } label: {
                                Label("New task", systemImage: "checklist")
                            }
                            .accessibilityIdentifier(AccessibilityID.Today.newTaskButton)
                            Button { sheet = .newHabit } label: {
                                Label("New habit", systemImage: "repeat")
                            }
                            .accessibilityIdentifier(AccessibilityID.Today.newHabitButton)
                        } label: {
                            Label("Add", systemImage: "plus")
                        }
                        .accessibilityIdentifier(AccessibilityID.Today.addButton)
                    }
                }
                .onAppear(perform: refreshCard)
                // Re-asked after every sheet, because two of them retire
                // a card: a tip taken in the Tip Jar retires the nudge,
                // opening Appearance retires the announcement, and Today
                // is already on screen so nothing else would prompt it
                // to look again.
                .sheet(item: $sheet, onDismiss: refreshCard) { sheet in
                    sheetContent(for: sheet)
                }
                .confirmationDialog(
                    String(localized: "Archive this habit?"),
                    isPresented: archiveDialogBinding,
                    titleVisibility: .visible,
                    presenting: confirmingArchiveOf
                ) { habitID in
                    Button(String(localized: "Archive"), role: .destructive) {
                        archive(habitID)
                    }
                    .accessibilityIdentifier(AccessibilityID.Today.archiveConfirmButton)
                    Button(String(localized: "Cancel"), role: .cancel) {}
                } message: { _ in
                    Text("Archived habits leave Today but keep their history. You can find them in Settings › Archived habits.")
                }
                .confirmationDialog("Remove this task?", isPresented: taskDeleteBinding, titleVisibility: .visible, presenting: pendingTaskDeletion) { item in
                    Button(item.isFromGoogle ? String(localized: "Remove from planner") : String(localized: "Delete task"), role: .destructive) { deleteTask(item.id) }
                        .accessibilityIdentifier(AccessibilityID.Tasks.deleteConfirm)
                    Button("Cancel", role: .cancel) {}
                } message: { item in
                    Text(item.isFromGoogle
                        ? String(localized: "The imported task and its completion history will be archived. The event stays in Google Calendar.")
                        : String(localized: "This removes the task and its planned calendar blocks."))
                }
                .alert("Unable to update task", isPresented: taskErrorBinding) {
                    Button("Close", role: .cancel) {}
                } message: { Text(taskError ?? "") }
        }
    }

    // MARK: - Selected day

    private var displayedDay: Date {
        selectedDay.map { calendar.startOfDay(for: $0) } ?? today
    }

    private var dayKind: TodayDayKind {
        TodayDayKind(day: displayedDay, today: today, calendar: calendar)
    }

    private var titleText: Text {
        dayKind == .today
            ? Text("Today")
            : Text(displayedDay, format: .dateTime.weekday(.abbreviated).month(.abbreviated).day())
    }

    /// From the earliest thing the user created or logged to 60 days
    /// ahead.
    private var stripDays: [Date] {
        let habitDates = activeHabits.flatMap { habit in
            [habit.createdAt] + (habit.completions ?? []).map(\.date)
        }
        let taskDates = activeTasks.map(\.createdAt)
        return DayStripRange.days(from: (habitDates + taskDates).min(), today: today, calendar: calendar)
    }

    private var stripSelection: Binding<Date> {
        Binding(
            get: { displayedDay },
            set: { newDay in
                selectedDay = calendar.isDate(newDay, inSameDayAs: today) ? nil : newDay
            }
        )
    }

    private struct StripProgressInput {
        let habits: [Habit]
        let completions: [UUID: [Completion]]
    }

    private var stripProgressInput: StripProgressInput {
        StripProgressInput(
            habits: activeHabits.map(\.snapshot),
            completions: Dictionary(
                activeHabits.map { ($0.id, ($0.completions ?? []).compactMap(\.snapshot)) },
                uniquingKeysWith: { first, _ in first }
            )
        )
    }

    private func stripProgress(for day: Date, input: StripProgressInput) -> DayProgress {
        DayStripProgress.progress(
            on: day,
            isFuture: TodayDayKind(day: day, today: today, calendar: calendar) == .future,
            habits: input.habits,
            completions: input.completions,
            evaluator: frequencyEvaluator,
            calendar: calendar
        )
    }

    @ViewBuilder
    private func sheetContent(for sheet: TodaySheet) -> some View {
        switch sheet {
        case .newHabit:
            NewHabitFormView(model: NewHabitFormModel())
        case .newTask:
            TaskFormView(defaultDay: dayKind == .future ? displayedDay : nil)
        case .editTask(let id):
            TaskFormView(taskID: id)
        case .editHabit(let habitID):
            if let record = record(for: habitID) {
                NewHabitFormView(model: NewHabitFormModel(editing: record))
            } else {
                HabitUnavailableView()
            }
        case .logCounter(let habitID, let day):
            if let record = record(for: habitID) {
                CounterLogSheet(habit: record, day: day)
            } else {
                HabitUnavailableView()
            }
        case .logTimer(let habitID, let day):
            if let record = record(for: habitID) {
                TimerLogSheet(habit: record, day: day)
            } else {
                HabitUnavailableView()
            }
        case .tipJar:
            NavigationStack {
                TipJarView()
                    .toolbar { closeButton }
            }
        case .appearance:
            NavigationStack {
                AppearanceView()
                    .toolbar { closeButton }
            }
        }
    }

    private var closeButton: some ToolbarContent {
        ToolbarItem(placement: .confirmationAction) {
            // Not "Done": that key already exists in the catalog as a
            // habit's completed-day label ("Fait" in French), which
            // would read as nonsense on a dismiss button.
            Button("Close") { self.sheet = nil }
        }
    }

    @ViewBuilder
    private var content: some View {
        if activeHabits.isEmpty && activeTasks.isEmpty {
            ContentUnavailableView {
                Label("No plans yet", systemImage: "list.bullet.clipboard")
            } description: {
                Text("Build your day with one-off tasks and recurring habits.")
            } actions: {
                Button { sheet = .newTask } label: {
                    Label("Create a task", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                Button {
                    sheet = .newHabit
                } label: {
                    Label("Create a habit", systemImage: "repeat")
                }
                .buttonStyle(.bordered)
            }
        } else {
            let (due, allOther) = sections
            // A future day lists only what its schedule asks for.
            let other = dayKind == .future ? [] : allOther
            let tasks = taskSections
            List {
                if dayKind == .today {
                    // Sampled once and passed down: letting the guard and
                    // the view each read `.now` lets them straddle the
                    // rollover and leave an empty, space-taking row.
                    let now = Date.now
                    if TodayDayCaption.isBeforeRollover(dayBoundary, now: now) {
                        TodayDayCaption(boundary: dayBoundary, now: now)
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 6, trailing: 20))
                    }
                }
                taskSectionViews(tasks)
                if due.isEmpty && other.isEmpty && tasks.isEmpty {
                    emptyDaySection
                }
                habitSectionViews(due: due, other: other)
                if dayKind == .today {
                    cardSection
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.kadoBackground.ignoresSafeArea())
            .quickLogFeedback(quickLog)
            .refreshable {
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private var taskSections: TaskDaySections {
        // Task planning uses civil days, while the habit rows use the
        // user's custom habit-day boundary.
        TaskDaySections.make(
            for: dayKind == .today ? civilToday : displayedDay,
            kind: dayKind,
            items: activeTasks.map { TaskListItem($0) },
            calendar: calendar
        )
    }

    private var taskDueHeader: LocalizedStringKey {
        switch dayKind {
        case .today: "Tasks today & overdue"
        case .past: "Due"
        case .future: "Planned"
        }
    }

    private var taskCompletedHeader: LocalizedStringKey {
        dayKind == .today ? "Tasks completed today" : "Completed that day"
    }

    @ViewBuilder
    private func taskSectionViews(_ tasks: TaskDaySections) -> some View {
        // On a past day the completed tasks come first, as the spec lists them.
        if dayKind == .past, !tasks.completed.isEmpty {
            Section(taskCompletedHeader) {
                ForEach(tasks.completed) { taskRow($0) }
            }
        }
        if !tasks.due.isEmpty {
            Section(taskDueHeader) {
                ForEach(tasks.due) { taskRow($0) }
            }
        }
        if dayKind == .today, !tasks.inbox.isEmpty {
            Section {
                ForEach(tasks.inbox) { taskRow($0) }
            } header: { Text("Task inbox") }
            footer: { Text("Tasks without a day. Tap a task to schedule it.") }
        }
        if dayKind == .today, !tasks.completed.isEmpty {
            Section(taskCompletedHeader) {
                ForEach(tasks.completed) { taskRow($0) }
            }
        }
    }

    @ViewBuilder
    private var emptyDaySection: some View {
        Section {
            if dayKind == .today {
                Text("Nothing planned for today")
                    .foregroundStyle(Color.kadoForegroundSecondary)
                Text("Future tasks appear on their day in Calendar.")
                    .font(.footnote)
                    .foregroundStyle(Color.kadoForegroundSecondary)
            } else {
                Text("Nothing on this day")
                    .foregroundStyle(Color.kadoForegroundSecondary)
            }
        }
        .listRowBackground(Color.kadoBackgroundSecondary)
    }

    @ViewBuilder
    private func habitSectionViews(due: [TodayRow], other: [TodayRow]) -> some View {
        let canReorder = dayKind == .today
        if !due.isEmpty {
            Section {
                ForEach(due) { row($0) }
                    .onMove(perform: canReorder ? { moveHabits(due, from: $0, to: $1) } : nil)
            } header: {
                Text(dayKind == .today ? "Habits today" : "Habits")
                    .foregroundStyle(Color.kadoForegroundSecondary)
            }
        }
        if !other.isEmpty {
            Section {
                ForEach(other) { row($0) }
                    .onMove(perform: canReorder ? { moveHabits(other, from: $0, to: $1) } : nil)
            } header: {
                Text(dayKind == .today ? "Not scheduled today" : "Not scheduled that day")
                    .foregroundStyle(Color.kadoForegroundSecondary)
            } footer: {
                // Archive is a today-only action, so the hint is too.
                if dayKind == .today {
                    Text("Tap to open detail, or long-press to edit or archive.")
                        .foregroundStyle(Color.kadoForegroundSecondary)
                }
            }
        }
    }

    @ViewBuilder
    private var cardSection: some View {
        switch card {
        case .appearanceAnnouncement:
            Section {
                AppearanceAnnouncementBanner(
                    onOpen: { sheet = .appearance },
                    onHide: hideAppearanceAnnouncement
                )
                .todayNoticeCardRow()
            }
        case .tipNudge:
            Section {
                TipNudgeBanner(
                    onTip: { sheet = .tipJar },
                    onHide: hideTipNudge
                )
                .todayNoticeCardRow()
            }
        case nil:
            EmptyView()
        }
    }

    private func taskRow(_ item: TaskListItem) -> some View {
        TaskRowView(item: item,
            onToggle: { toggleTask(item.id) },
            onEdit: { sheet = .editTask(item.id) },
            onDelete: { deletingTaskID = item.id })
            .listRowBackground(Color.kadoBackgroundSecondary)
            .swipeActions(edge: .trailing) {
                Button(role: .destructive) { deletingTaskID = item.id } label: {
                    Label(item.isFromGoogle ? String(localized: "Remove from planner") : String(localized: "Delete task"), systemImage: "trash")
                }
            }
            .swipeActions(edge: .leading) {
                Button { toggleTask(item.id) } label: {
                    Label(item.isComplete ? String(localized: "Mark incomplete") : String(localized: "Complete task"), systemImage: "checkmark.circle")
                }
                .tint(Color.kadoAccent)
            }
    }

    private var pendingTaskDeletion: TaskListItem? {
        guard let deletingTaskID, let record = activeTasks.first(where: { $0.id == deletingTaskID }) else { return nil }
        return TaskListItem(record)
    }

    private var taskDeleteBinding: Binding<Bool> {
        Binding(get: { deletingTaskID != nil }, set: { if !$0 { deletingTaskID = nil } })
    }

    private var taskErrorBinding: Binding<Bool> {
        Binding(get: { taskError != nil }, set: { if !$0 { taskError = nil } })
    }

    private func toggleTask(_ id: UUID) {
        guard let record = activeTasks.first(where: { $0.id == id }) else { return }
        // A task done on a past day is stamped with that day; today and
        // future days stamp now (a task done early was done now).
        record.completedAt = record.completedAt == nil
            ? (dayKind == .past ? dayBoundary.loggingInstant(for: .now, on: displayedDay) : .now)
            : nil
        record.updatedAt = .now
        saveTaskChanges()
    }

    private func deleteTask(_ id: UUID) {
        guard let record = activeTasks.first(where: { $0.id == id }) else { return }
        if record.externalEventID != nil {
            record.archivedAt = .now
            record.updatedAt = .now
        } else {
            modelContext.delete(record)
        }
        deletingTaskID = nil
        saveTaskChanges()
    }

    private func saveTaskChanges() {
        do { try modelContext.save() }
        catch {
            modelContext.rollback()
            taskError = error.localizedDescription
        }
    }

    @ViewBuilder
    private func row(_ item: TodayRow) -> some View {
        let state = HabitRowState.resolve(
            habit: item.habit,
            completions: item.completions,
            calendar: calendar,
            asOf: displayedDay
        )
        NavigationLink(value: HabitRoute(id: item.id)) {
            HabitRowView(
                habit: item.habit,
                state: state,
                streak: streakCalculator.current(
                    for: item.habit, completions: item.completions, asOf: displayedDay
                ),
                scorePercent: Int(
                    (scoreCalculator.currentScore(
                        for: item.habit, completions: item.completions, asOf: displayedDay
                    ) * 100).rounded()
                ),
                onToggle: dayKind.allowsHabitLogging && canToggle(item) ? { toggle(item.id) } : nil,
                onCounterIncrement: dayKind.allowsHabitLogging && isCounter(item) ? { incrementCounter(item.id) } : nil,
                onCounterDecrement: dayKind.allowsHabitLogging && isCounter(item) ? { decrementCounter(item.id) } : nil,
                onTimerAddFiveMinutes: dayKind.allowsHabitLogging && isTimer(item) ? { addFiveMinutes(item.id) } : nil,
                onLogSpecificValue: dayKind.allowsHabitLogging ? logSheetCallback(for: item) : nil,
                onOpenDetail: { path.append(HabitRoute(id: item.id)) },
                onEdit: { sheet = .editHabit(item.id) },
                onArchive: dayKind == .today ? { confirmingArchiveOf = item.id } : nil
            )
        }
        .listRowBackground(Color.kadoBackgroundSecondary)
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            if dayKind.allowsHabitLogging, canSwipeUndo(item, state: state) {
                Button(role: .destructive) {
                    toggle(item.id)
                } label: {
                    Label("Undo", systemImage: "arrow.uturn.backward")
                }
            }
        }
    }

    /// The two Today sections, snapshotted from the live records.
    ///
    /// The split rule — "the schedule asks for it today, or the user
    /// already logged progress today anyway", which keeps a row
    /// visible with its tick once a daysPerWeek rolling quota
    /// saturates — lives on `FrequencyEvaluating` so this view and the
    /// widget snapshot can't drift apart.
    private var sections: (due: [TodayRow], other: [TodayRow]) {
        TodayRow.sections(
            from: activeHabits,
            on: displayedDay,
            evaluator: frequencyEvaluator,
            calendar: calendar
        )
    }

    /// Resolves a row back to the live managed object it was
    /// snapshotted from, against whichever store is mounted now.
    /// Returns `nil` when the habit isn't there any more — archived
    /// from another surface, or left behind by a dev-mode store swap.
    private func record(for habitID: UUID) -> HabitRecord? {
        activeHabits.first { $0.id == habitID }
    }

    private var archiveDialogBinding: Binding<Bool> {
        Binding(
            get: { confirmingArchiveOf != nil },
            set: { if !$0 { confirmingArchiveOf = nil } }
        )
    }

    // MARK: - Type predicates

    private func canToggle(_ item: TodayRow) -> Bool {
        switch item.habit.type {
        case .binary, .negative: true
        case .counter, .timer: false
        }
    }

    private func isCounter(_ item: TodayRow) -> Bool {
        if case .counter = item.habit.type { return true }
        return false
    }

    private func isTimer(_ item: TodayRow) -> Bool {
        if case .timer = item.habit.type { return true }
        return false
    }

    /// Trailing-swipe Undo only applies to binary / negative when the
    /// day is already marked. Counter / timer get their undo from the
    /// row's own `−` button (counter) or the "Log specific value…"
    /// menu item, so a swipe action would be redundant.
    private func canSwipeUndo(_ item: TodayRow, state: HabitRowState) -> Bool {
        guard state.status == .complete else { return false }
        switch item.habit.type {
        case .binary, .negative: return true
        case .counter, .timer: return false
        }
    }

    private func logSheetCallback(for item: TodayRow) -> (() -> Void)? {
        switch item.habit.type {
        case .counter: return { sheet = .logCounter(item.id, displayedDay) }
        case .timer: return { sheet = .logTimer(item.id, displayedDay) }
        case .binary, .negative: return nil
        }
    }

    // MARK: - Actions

    /// The instant to stamp on anything logged right now, pinned to
    /// the day these rows were rendered for. Keeps a tap consistent
    /// with what the user was looking at when they made it.
    private var loggingInstant: Date {
        dayBoundary.loggingInstant(for: .now, on: displayedDay)
    }

    private func moveHabits(_ section: [TodayRow], from source: IndexSet, to destination: Int) {
        var reordered = section
        reordered.move(fromOffsets: source, toOffset: destination)

        let (due, other) = sections
        let isDueSection = section.first.map { first in
            due.contains { $0.id == first.id }
        } == true

        let finalOrder: [TodayRow]
        if isDueSection {
            finalOrder = reordered + other
        } else {
            finalOrder = due + reordered
        }

        let recordsByID = Dictionary(
            activeHabits.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        for (index, item) in finalOrder.enumerated() {
            recordsByID[item.id]?.sortOrder = index
        }
        try? modelContext.save()
        WidgetReloader.reloadAll(using: modelContext)
    }

    private func toggle(_ habitID: UUID) {
        guard let record = record(for: habitID) else { return }
        CompletionToggler(calendar: calendar)
            .toggleToday(for: record, on: loggingInstant, in: modelContext)
        try? modelContext.save()
        WidgetReloader.reloadAll(using: modelContext)
        checkMilestones(for: record)
    }

    private func incrementCounter(_ habitID: UUID) {
        guard let record = record(for: habitID) else { return }
        let logger = CompletionLogger(calendar: calendar)
        let before = logger.value(for: record, on: loggingInstant)
        logger.incrementCounter(for: record, on: loggingInstant, in: modelContext)
        recordQuickLog(for: record, from: before, to: before + 1)
        try? modelContext.save()
        WidgetReloader.reloadAll(using: modelContext)
        checkMilestones(for: record)
    }

    private func decrementCounter(_ habitID: UUID) {
        guard let record = record(for: habitID) else { return }
        let logger = CompletionLogger(calendar: calendar)
        let before = logger.value(for: record, on: loggingInstant)
        logger.decrementCounter(for: record, on: loggingInstant, in: modelContext)
        recordQuickLog(for: record, from: before, to: max(0, before - 1))
        try? modelContext.save()
        WidgetReloader.reloadAll(using: modelContext)
    }

    private func addFiveMinutes(_ habitID: UUID) {
        guard let record = record(for: habitID) else { return }
        let logger = CompletionLogger(calendar: calendar)
        let before = logger.value(for: record, on: loggingInstant)
        logger.incrementCounter(for: record, on: loggingInstant, by: 300, in: modelContext)
        recordQuickLog(for: record, from: before, to: before + 300)
        try? modelContext.save()
        WidgetReloader.reloadAll(using: modelContext)
        checkMilestones(for: record)
    }

    /// The step is known here exactly — `+1`, `−1` floored at zero,
    /// `+300` — so the haptic is derived from the mutation, not read
    /// back from a store that may still hold a just-deleted record.
    private func recordQuickLog(for record: HabitRecord, from old: Double, to new: Double) {
        guard let event = QuickLogEvent.next(after: quickLog, type: record.type, oldValue: old, newValue: new) else {
            return
        }
        quickLog = event
    }

    private func checkMilestones(for record: HabitRecord) {
        guard dayKind == .today else { return }
        let snap = record.snapshot
        let comps = (record.completions ?? []).compactMap(\.snapshot)
        let streak = streakCalculator.current(for: snap, completions: comps, asOf: today)
        if streak == 7 || streak == 30 {
            reviewPromptService.recordMilestone(.streak(days: streak))
        }

        // Re-snapshotted after the save, so this sees the mutation that
        // just landed rather than the pre-tap rows. Through
        // `DayProgress` so "all done" means the same thing here as it
        // does for the confetti and the lock-screen ring — in
        // particular, a day with nothing scheduled is not a milestone.
        let due = sections.due
        let completed = due.filter { item in
            HabitRowState.resolve(
                habit: item.habit,
                completions: item.completions,
                calendar: calendar,
                asOf: today
            ).isDone(for: item.habit)
        }.count
        if DayProgress(completed: completed, total: due.count).isComplete {
            reviewPromptService.recordMilestone(.allHabitsComplete)
        }
    }

    // MARK: - Bottom card

    /// Asks both services what is due and lets `TodayCard` pick. Every
    /// rule either service applies is one-way, so a dismissed card
    /// never comes back.
    private func refreshCard() {
        card = TodayCard.resolve(
            announcementRetiredAt: appearanceAnnouncement.retiredAt(),
            tipNudgeDue: tipNudge.shouldShow(),
            now: .now,
            calendar: calendar
        )
    }

    private func hideTipNudge() {
        tipNudge.hide()
        withAnimation(reduceMotion ? nil : KadoMotion.base) {
            card = nil
        }
    }

    /// Takes the card away rather than re-resolving: the tip nudge
    /// isn't due until tomorrow anyway, and resolving would only say so.
    private func hideAppearanceAnnouncement() {
        appearanceAnnouncement.retire()
        withAnimation(reduceMotion ? nil : KadoMotion.base) {
            card = nil
        }
    }

    private func archive(_ habitID: UUID) {
        guard let record = record(for: habitID) else { return }
        HabitLifecycle().archive(record, at: loggingInstant, in: modelContext)
        WidgetReloader.reloadAll(using: modelContext)
    }
}

#Preview("Populated") {
    TodayView()
        .modelContainer(PreviewContainer.shared)
}

#Preview("No habits") {
    TodayView()
        .modelContainer(PreviewContainer.emptyContainer())
}

#Preview("Nothing due today") {
    TodayView()
        .modelContainer(PreviewContainer.noneDueTodayContainer())
}

#Preview("Appearance announcement") {
    TodayView()
        .modelContainer(PreviewContainer.shared)
        .environment(\.appearanceAnnouncement, StubAppearanceAnnouncementService())
        .environment(\.tipNudge, StubTipNudgeService())
}

#Preview("Tip nudge") {
    TodayView()
        .modelContainer(PreviewContainer.shared)
        .environment(\.appearanceAnnouncement, StubAppearanceAnnouncementService(retiredAt: .distantPast))
        .environment(\.tipNudge, StubTipNudgeService())
}

#Preview("Tip nudge — Dark") {
    TodayView()
        .modelContainer(PreviewContainer.shared)
        .environment(\.appearanceAnnouncement, StubAppearanceAnnouncementService(retiredAt: .distantPast))
        .environment(\.tipNudge, StubTipNudgeService())
        .preferredColorScheme(.dark)
}

#Preview("Dark") {
    TodayView()
        .modelContainer(PreviewContainer.shared)
        .preferredColorScheme(.dark)
}
