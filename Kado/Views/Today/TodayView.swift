import SwiftData
import SwiftUI
import KadoCore

/// The Today tab — shows the day picked in the day strip (today by
/// default): lists habits due that day and handles tap-to-toggle
/// for binary and negative habits, inline counter / timer logging,
/// and a long-press context menu for the secondary actions
/// (specific-value sheets, edit, archive).
///
/// This view holds the navigation and what it presents (sheets,
/// dialogs, the bottom card); `TodayDayContent` holds the strip and
/// the list. Kept apart so presenting something doesn't re-snapshot
/// every habit.
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
    @Environment(\.tipNudge) private var tipNudge
    @Environment(\.appearanceAnnouncement) private var appearanceAnnouncement
    @Environment(\.calendar) private var calendar
    @Environment(\.today) private var today
    @Environment(\.dayBoundary) private var dayBoundary

    /// Read by the sheets and the archive dialog only; the list reads
    /// its own in `TodayDayContent`.
    @Query(
        filter: #Predicate<HabitRecord> { $0.archivedAt == nil },
        sort: \HabitRecord.sortOrder
    )
    private var activeHabits: [HabitRecord]

    @State private var path = NavigationPath()
    @State private var sheet: TodaySheet?
    @State private var confirmingArchiveOf: UUID?
    @State private var deletingTaskID: UUID?
    @State private var taskError: String?

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

    enum Mode: String { case list, calendar }

    /// List or Calendar view of the displayed day; remembered across launches.
    @AppStorage(TodayModeDefaults.key) private var mode: Mode = .list

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
        /// The monthly check-in, from its card.
        case reflectionCheckIn(ReflectionMonth)

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
            case .reflectionCheckIn(let month): "reflection-\(month.id)"
            }
        }
    }

    var body: some View {
        NavigationStack(path: $path) {
            TodayDayContent(selectedDay: selectedDay, card: card, actions: contentActions)
                .equatable()
                .onChange(of: today) { _, newToday in
                    // A day picked while it was in the future follows
                    // today again once it becomes today.
                    if let selectedDay, calendar.isDate(selectedDay, inSameDayAs: newToday) {
                        self.selectedDay = nil
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

    /// Each one only writes this view's state. `TodayDayContent` keeps
    /// the closures from an earlier pass when it skips an update, so
    /// they must not read anything that pass captured.
    private var contentActions: TodayDayContent.Actions {
        TodayDayContent.Actions(
            present: { sheet = $0 },
            confirmArchive: { confirmingArchiveOf = $0 },
            confirmTaskDeletion: { deletingTaskID = $0 },
            openDetail: { path.append(HabitRoute(id: $0)) },
            reportTaskError: { taskError = $0 },
            select: { selectedDay = $0 },
            setCard: { card = $0 }
        )
    }

    // MARK: - Selected day

    /// The day shown for a strip selection; `nil` follows today.
    static func displayedDay(selectedDay: Date?, today: Date, calendar: Calendar) -> Date {
        selectedDay.map { calendar.startOfDay(for: $0) } ?? today
    }

    private var displayedDay: Date {
        Self.displayedDay(selectedDay: selectedDay, today: today, calendar: calendar)
    }

    private var dayKind: TodayDayKind {
        TodayDayKind(day: displayedDay, today: today, calendar: calendar)
    }

    private var titleText: Text {
        dayKind == .today
            ? Text("Today")
            : Text(displayedDay, format: .dateTime.weekday(.abbreviated).month(.abbreviated).day())
    }

    @ViewBuilder
    private func sheetContent(for sheet: TodaySheet) -> some View {
        switch sheet {
        case .newHabit:
            NewHabitFormView(model: NewHabitFormModel())
        case .newTask:
            // Calendar mode plans onto the shown day, so the task
            // must land on it or it would not appear there.
            TaskFormView(defaultDay: dayKind == .future || mode == .calendar ? displayedDay : nil)
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
        case .reflectionCheckIn(let month):
            ReflectionCheckInView(month: month)
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

    // MARK: - Tasks

    /// The task the delete dialog is about, read from the store by id
    /// rather than from a query of every task this view would otherwise
    /// have to hold.
    private func activeTask(_ id: UUID) -> TaskRecord? {
        let descriptor = FetchDescriptor<TaskRecord>(predicate: #Predicate { $0.id == id })
        return (try? modelContext.fetch(descriptor))?
            .first { $0.archivedAt == nil && $0.externalCancelledAt == nil }
    }

    private var pendingTaskDeletion: TaskListItem? {
        guard let deletingTaskID, let record = activeTask(deletingTaskID) else { return nil }
        return TaskListItem(record)
    }

    private var taskDeleteBinding: Binding<Bool> {
        Binding(get: { deletingTaskID != nil }, set: { if !$0 { deletingTaskID = nil } })
    }

    private var taskErrorBinding: Binding<Bool> {
        Binding(get: { taskError != nil }, set: { if !$0 { taskError = nil } })
    }

    private func deleteTask(_ id: UUID) {
        guard let record = activeTask(id) else { return }
        if record.externalEventID != nil {
            record.archivedAt = .now
            record.updatedAt = .now
        } else {
            modelContext.delete(record)
        }
        deletingTaskID = nil
        do { try modelContext.save() }
        catch {
            modelContext.rollback()
            taskError = error.localizedDescription
        }
    }

    // MARK: - Habits

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

    private func archive(_ habitID: UUID) {
        guard let record = record(for: habitID) else { return }
        HabitLifecycle().archive(
            record,
            at: dayBoundary.loggingInstant(for: .now, on: displayedDay),
            in: modelContext
        )
        WidgetReloader.reloadAll(using: modelContext)
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
            calendar: calendar,
            reflectionCheckIn: dueCheckIn()
        )
    }

    /// The month whose check-in is open and not done, unless its card
    /// was put away.
    private func dueCheckIn() -> ReflectionMonth? {
        // The card depends on the date; UI runs keep the slot for the
        // cards their tests set up.
        guard !UITestSupport.isRunningUITests else { return nil }
        let entries = (try? ReflectionStore(context: modelContext).entries()) ?? []
        let planner = ReflectionPlanner(calendar: calendar)
        guard planner.isDue(now: .now, entries: entries) else { return nil }
        let month = planner.checkInMonth(now: .now, entries: entries)
        let hidden = UserDefaults.standard.string(forKey: ReflectionDefaults.dismissedCardKey)
        return hidden == ReflectionReminderScheduler.key(for: month) ? nil : month
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
