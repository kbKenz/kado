import SwiftData
import SwiftUI
import KadoCore

/// The data half of Today: the day strip and the shown day's list (or
/// its calendar), with the actions their rows run.
///
/// Split from `TodayView` for cost. This view snapshots every habit and
/// its completions, which is the expensive part of a pass, so it owns
/// the queries and takes only plain values from its parent: opening a
/// sheet or a dialog re-runs `TodayView.body`, and `.equatable()` keeps
/// that from re-running this one. Its own queries, environment and
/// observed records still update it as before.
///
/// The parent's actions only write the parent's state. Anything that
/// reads the environment runs here, against this view's current
/// values, because SwiftUI keeps the old closures when it skips an
/// update.
struct TodayDayContent: View, Equatable {
    /// The day picked in the strip; `nil` means today (see `TodayView`).
    let selectedDay: Date?
    let card: TodayCard?
    let actions: Actions

    struct Actions {
        var present: (TodayView.TodaySheet) -> Void
        var confirmArchive: (UUID) -> Void
        var confirmTaskDeletion: (UUID) -> Void
        var openDetail: (UUID) -> Void
        var reportTaskError: (String) -> Void
        var select: (Date?) -> Void
        var setCard: (TodayCard?) -> Void
    }

    nonisolated static func == (lhs: TodayDayContent, rhs: TodayDayContent) -> Bool {
        lhs.selectedDay == rhs.selectedDay && lhs.card == rhs.card
    }

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

    /// List or Calendar view of the displayed day; remembered across launches.
    @AppStorage(TodayModeDefaults.key) private var mode: TodayView.Mode = .list

    /// The latest `−` / `+` / `+5m` tap, for the haptic. Recorded by
    /// the mutation rather than observed on the row: a row keyed on
    /// its own value ticks when the day rolls over or a sync lands,
    /// and misses the tap that moves it between sections (a new
    /// `ForEach` identity sees no old → new).
    @State private var quickLog: QuickLogEvent?

    var body: some View {
        // Snapshotted once per pass: the strip's range, its rings and
        // the list all read these rows.
        let rows = activeHabits.map { TodayRow($0) }
        let days = stripDays(rows)
        let progressIndex = DayStripProgress.Index(
            habits: rows.map(\.habit),
            completions: Dictionary(rows.map { ($0.id, $0.completions) }, uniquingKeysWith: { first, _ in first }),
            calendar: calendar
        )
        Group {
            switch mode {
            case .list: content(rows)
            case .calendar: CalendarDayAgenda(day: displayedDay, calendar: calendar)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.kadoBackground.ignoresSafeArea())
        .pinnedTopBar {
            TodayHeader(
                days: days,
                selection: stripSelection,
                today: today,
                progress: { stripProgress(for: $0, index: progressIndex) },
                mode: $mode
            )
        }
        .onChange(of: days) { _, days in
            if let selectedDay,
               let clamped = DayStripRange.clamp(selectedDay, to: days),
               clamped != selectedDay {
                actions.select(calendar.isDate(clamped, inSameDayAs: today) ? nil : clamped)
            }
        }
    }

    // MARK: - Selected day

    private var displayedDay: Date {
        TodayView.displayedDay(selectedDay: selectedDay, today: today, calendar: calendar)
    }

    private var dayKind: TodayDayKind {
        TodayDayKind(day: displayedDay, today: today, calendar: calendar)
    }

    /// From the earliest thing the user created or logged to 60 days
    /// ahead.
    private func stripDays(_ rows: [TodayRow]) -> [Date] {
        let earliest = (rows.map(\.earliestDate) + activeTasks.map(\.createdAt)).min()
        return DayStripRange.days(from: earliest, today: today, calendar: calendar)
    }

    private var stripSelection: Binding<Date> {
        Binding(
            get: { displayedDay },
            set: { newDay in
                actions.select(calendar.isDate(newDay, inSameDayAs: today) ? nil : newDay)
            }
        )
    }

    private func stripProgress(for day: Date, index: DayStripProgress.Index) -> DayProgress {
        DayStripProgress.progress(
            on: day,
            isFuture: TodayDayKind(day: day, today: today, calendar: calendar) == .future,
            index: index,
            evaluator: frequencyEvaluator,
            calendar: calendar
        )
    }

    // MARK: - List

    @ViewBuilder
    private func content(_ rows: [TodayRow]) -> some View {
        if activeHabits.isEmpty && activeTasks.isEmpty {
            ContentUnavailableView {
                Label("No plans yet", systemImage: "list.bullet.clipboard")
            } description: {
                Text("Build your day with one-off tasks and recurring habits.")
            } actions: {
                Button { actions.present(.newTask) } label: {
                    Label("Create a task", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                Button {
                    actions.present(.newHabit)
                } label: {
                    Label("Create a habit", systemImage: "repeat")
                }
                .buttonStyle(.bordered)
            }
        } else {
            let (due, allOther) = sections(from: rows)
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
        let day = dayKind == .today ? civilToday : displayedDay
        let kind = dayKind
        // Only the tasks that can show are snapshotted; `make` then
        // picks from them exactly as it would from all of them.
        let items = activeTasks
            .filter { record in
                TaskDaySections.mayInclude(
                    completedAt: record.completedAt,
                    dueDate: record.dueDate,
                    hasSchedules: { !(record.scheduleBlocks ?? []).isEmpty },
                    on: day,
                    kind: kind,
                    calendar: calendar
                )
            }
            .map { TaskListItem($0) }
        return TaskDaySections.make(for: day, kind: kind, items: items, calendar: calendar)
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
                    onOpen: { actions.present(.appearance) },
                    onHide: hideAppearanceAnnouncement
                )
                .todayNoticeCardRow()
            }
        case .tipNudge:
            Section {
                TipNudgeBanner(
                    onTip: { actions.present(.tipJar) },
                    onHide: hideTipNudge
                )
                .todayNoticeCardRow()
            }
        case .reflectionCheckIn(let month):
            Section {
                ReflectionCheckInBanner(
                    month: month,
                    onStart: { actions.present(.reflectionCheckIn(month)) },
                    onHide: { hideReflectionCheckIn(month) }
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
            onEdit: { actions.present(.editTask(item.id)) },
            onDelete: { actions.confirmTaskDeletion(item.id) })
            .listRowBackground(Color.kadoBackgroundSecondary)
            .swipeActions(edge: .trailing) {
                Button(role: .destructive) { actions.confirmTaskDeletion(item.id) } label: {
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

    private func toggleTask(_ id: UUID) {
        guard let record = activeTasks.first(where: { $0.id == id }) else { return }
        // A task done on a past day is stamped with that day; today and
        // future days stamp now (a task done early was done now).
        record.completedAt = record.completedAt == nil
            ? (dayKind == .past ? dayBoundary.loggingInstant(for: .now, on: displayedDay) : .now)
            : nil
        record.updatedAt = .now
        do { try modelContext.save() }
        catch {
            modelContext.rollback()
            actions.reportTaskError(error.localizedDescription)
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
                onOpenDetail: { actions.openDetail(item.id) },
                onEdit: { actions.present(.editHabit(item.id)) },
                onArchive: dayKind == .today ? { actions.confirmArchive(item.id) } : nil
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

    /// The two Today sections.
    ///
    /// The split rule — "the schedule asks for it today, or the user
    /// already logged progress today anyway", which keeps a row
    /// visible with its tick once a daysPerWeek rolling quota
    /// saturates — lives on `FrequencyEvaluating` so this view and the
    /// widget snapshot can't drift apart.
    private func sections(from rows: [TodayRow]) -> (due: [TodayRow], other: [TodayRow]) {
        TodayRow.sections(
            from: rows,
            on: displayedDay,
            evaluator: frequencyEvaluator,
            calendar: calendar
        )
    }

    /// The same sections, re-snapshotted from the live records, for an
    /// action that has to see a mutation that just landed.
    private var liveSections: (due: [TodayRow], other: [TodayRow]) {
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
        let day = displayedDay
        switch item.habit.type {
        case .counter: return { actions.present(.logCounter(item.id, day)) }
        case .timer: return { actions.present(.logTimer(item.id, day)) }
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

        let (due, other) = liveSections
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
        let due = liveSections.due
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

    private func hideTipNudge() {
        tipNudge.hide()
        withAnimation(reduceMotion ? nil : KadoMotion.base) {
            actions.setCard(nil)
        }
    }

    /// Hides the check-in card until next month; the check-in itself
    /// stays in Overview › Reflect.
    private func hideReflectionCheckIn(_ month: ReflectionMonth) {
        UserDefaults.standard.set(ReflectionReminderScheduler.key(for: month), forKey: ReflectionDefaults.dismissedCardKey)
        withAnimation(reduceMotion ? nil : KadoMotion.base) {
            actions.setCard(nil)
        }
    }

    /// Takes the card away rather than re-resolving: the tip nudge
    /// isn't due until tomorrow anyway, and resolving would only say so.
    private func hideAppearanceAnnouncement() {
        appearanceAnnouncement.retire()
        withAnimation(reduceMotion ? nil : KadoMotion.base) {
            actions.setCard(nil)
        }
    }
}

/// The day strip with the List / Calendar switch under it.
private struct TodayHeader: View {
    let days: [Date]
    @Binding var selection: Date
    let today: Date
    let progress: (Date) -> DayProgress
    @Binding var mode: TodayView.Mode

    var body: some View {
        VStack(spacing: 8) {
            DayStrip(days: days, selection: $selection, today: today, progress: progress)
                // A horizontal ScrollView is greedy vertically and
                // would take the whole inset, pushing the list away.
                .fixedSize(horizontal: false, vertical: true)
            Picker("View", selection: $mode) {
                Text("List").tag(TodayView.Mode.list)
                Text("Calendar").tag(TodayView.Mode.calendar)
            }
            .pickerStyle(.segmented)
            // Capped so it doesn't stretch across an iPad.
            .frame(maxWidth: 400)
            .padding(.horizontal)
            .padding(.bottom, 6)
            .accessibilityIdentifier(AccessibilityID.Today.modePicker)
        }
        .frame(maxWidth: .infinity)
    }
}

private extension TodayDayContent.Actions {
    /// For previews: every action does nothing.
    static let none = TodayDayContent.Actions(
        present: { _ in }, confirmArchive: { _ in }, confirmTaskDeletion: { _ in },
        openDetail: { _ in }, reportTaskError: { _ in }, select: { _ in }, setCard: { _ in }
    )
}

#Preview("Populated") {
    NavigationStack {
        TodayDayContent(selectedDay: nil, card: nil, actions: .none)
    }
    .modelContainer(PreviewContainer.shared)
}

#Preview("Dark") {
    NavigationStack {
        TodayDayContent(selectedDay: nil, card: .tipNudge, actions: .none)
    }
    .modelContainer(PreviewContainer.shared)
    .preferredColorScheme(.dark)
}
