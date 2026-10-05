import KadoCore
import SwiftData
import SwiftUI

/// One day's planned blocks on a timeline, shown by Today's Calendar
/// mode. All completion controls resolve and update the linked task;
/// ScheduleBlock stores no status. The day comes from Today's strip, and
/// the toolbar items merge into Today's navigation stack.
struct CalendarDayAgenda: View {
    let day: Date

    @Environment(\.modelContext) private var modelContext
    @Environment(\.calendar) private var calendar
    @Environment(\.googleCalendarConnection) private var googleCalendar
    @AppStorage(DevModeDefaults.key, store: DevModeDefaults.sharedDefaults) private var isDevMode = false
    @Environment(\.healthTimelineProvider) private var healthProvider
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(HealthCalendarDefaults.key) private var showsHealth = false
    @State private var loadedHealth: LoadedHealth?

    private struct LoadedHealth {
        let day: Date
        let entries: [HealthTimelineEntry]
    }

    /// Entries for the selected day only; a previous day's result is never drawn.
    private var dayHealthEntries: [HealthTimelineEntry] {
        guard showsHealth, let loadedHealth, loadedHealth.day == day else { return [] }
        return loadedHealth.entries
    }

    /// Reload when the day, the opt-in, or foreground state changes.
    private struct HealthReloadKey: Hashable {
        let day: Date
        let isEnabled: Bool
        let isActive: Bool
    }

    /// Only blocks that can touch `day` (see `init`), not every block
    /// ever planned or imported.
    @Query private var blocks: [ScheduleBlockRecord]
    @Query(filter: #Predicate<TaskRecord> { $0.archivedAt == nil && $0.externalCancelledAt == nil }, sort: \TaskRecord.createdAt)
    private var records: [TaskRecord]

    /// `calendar` must be the environment's, so the fetched range is
    /// the day the agenda draws; a mismatch only widens the fetch.
    init(day: Date, calendar: Calendar = .current) {
        self.day = day
        _blocks = Query(Self.blocksDescriptor(touching: day, calendar: calendar))
    }

    /// Every block `TaskScheduleItem.belongs(to:)` can keep for `day`,
    /// and a few more: `visibleBlocks` still decides exactly, so this
    /// only has to never drop one. A day of slack each side keeps it a
    /// superset whatever zone the two calendars disagree on.
    static func blocksDescriptor(touching day: Date, calendar: Calendar) -> FetchDescriptor<ScheduleBlockRecord> {
        let dayStart = calendar.startOfDay(for: day)
        let lower = calendar.date(byAdding: .day, value: -1, to: dayStart) ?? .distantPast
        let upper = calendar.date(byAdding: .day, value: 2, to: dayStart) ?? .distantFuture
        let distantPast = Date.distantPast
        let distantFuture = Date.distantFuture
        // `belongs` reads the planned day unless both times are set, and
        // then the overlap of the timed range with the day. A missing
        // time falls outside the range, so that arm only keeps fully
        // timed blocks.
        let predicate = #Predicate<ScheduleBlockRecord> { block in
            (block.plannedDay >= lower && block.plannedDay < upper)
                || ((block.startAt ?? distantFuture) < upper && (block.endAt ?? distantPast) > lower)
        }
        return FetchDescriptor(predicate: predicate, sortBy: [SortDescriptor(\.plannedDay)])
    }

    @State private var sheet: CalendarSheet?
    @State private var deletingTaskID: UUID?
    @State private var errorMessage: String?

    private enum CalendarSheet: Identifiable {
        case newTask(Date)
        case editTask(UUID)
        case habit(UUID)

        var id: String {
            switch self {
            case .newTask(let date): "new-\(date.timeIntervalSinceReferenceDate)"
            case .editTask(let id): "task-\(id)"
            case .habit(let id): "habit-\(id)"
            }
        }
    }

    var body: some View {
        agenda
            .toolbar {
                // "New task" lives in Today's add menu, which is already
                // in the toolbar in this mode.
                ToolbarItem(placement: .topBarLeading) {
                    NavigationLink { GoogleCalendarSettingsView() } label: {
                        Label("Google Calendar", systemImage: "arrow.triangle.2.circlepath")
                    }
                    .accessibilityIdentifier(AccessibilityID.Calendar.googleSettings)
                }
            }
            .task(id: HealthReloadKey(day: day, isEnabled: showsHealth, isActive: scenePhase == .active)) {
                guard scenePhase == .active else { return }
                let loaded = await HealthTimelineLoader(provider: healthProvider, calendar: calendar)
                    .entries(on: day, isEnabled: showsHealth)
                // A superseded load (the user moved to another day) must not
                // overwrite the newer day's entries.
                guard !Task.isCancelled else { return }
                loadedHealth = LoadedHealth(day: day, entries: loaded)
            }
            .sheet(item: $sheet) { selection in
                switch selection {
                case .newTask(let day): TaskFormView(defaultDay: day)
                case .editTask(let id): TaskFormView(taskID: id)
                case .habit(let id):
                    NavigationStack {
                        HabitDetailLoader(habitID: id)
                            .toolbar {
                                ToolbarItem(placement: .cancellationAction) {
                                    Button("Close") { sheet = nil }
                                }
                            }
                    }
                }
            }
            .confirmationDialog("Remove this task?", isPresented: deleteBinding, titleVisibility: .visible, presenting: pendingDeletion) { item in
                Button(item.isFromGoogle ? String(localized: "Remove from planner") : String(localized: "Delete task"), role: .destructive) { deleteTask(item.id) }
                    .accessibilityIdentifier(AccessibilityID.Tasks.deleteConfirm)
                Button("Cancel", role: .cancel) {}
            } message: { item in
                Text(item.isFromGoogle
                    ? String(localized: "The imported task and its completion history will be archived. The event stays in Google Calendar.")
                    : String(localized: "This removes the task and its planned calendar blocks."))
            }
            .alert("Unable to update task", isPresented: errorBinding) {
                Button("Close", role: .cancel) {}
            } message: { Text(errorMessage ?? "") }
    }

    private var agenda: some View {
        let dayBlocks = visibleBlocks
        let timed = dayBlocks.filter { $0.schedule.startAt != nil }
        let untimed = dayBlocks.filter { $0.schedule.startAt == nil }
        let unscheduled = tasksWithoutBlocks
        return ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if googleCalendar.isSyncing {
                        HStack(spacing: 8) {
                            ProgressView()
                            Text("Syncing Google Calendar…").font(.caption)
                        }
                    } else if let syncError = googleCalendar.errorMessage {
                        Text(syncError)
                            .font(.caption)
                            .foregroundStyle(Color.kadoForegroundSecondary)
                    }
                    if !untimed.isEmpty || !unscheduled.isEmpty {
                        anyTimeSection(blocks: untimed, tasks: unscheduled)
                    }
                    if dayBlocks.isEmpty && unscheduled.isEmpty {
                        ContentUnavailableView {
                            Label("Your day is open", systemImage: "calendar")
                        } description: {
                            Text("Add a task to plan this day. Start and end times are optional.")
                        } actions: {
                            Button("Add task") { sheet = .newTask(day) }
                                .buttonStyle(.borderedProminent)
                        }
                        .padding(.vertical, 16)
                    }
                    HStack {
                        Text("Timeline").font(.headline)
                        Spacer()
                        Text("Planned time").font(.caption).foregroundStyle(Color.kadoForegroundSecondary)
                    }
                    CalendarDayTimeline(
                        day: day, blocks: timed, healthEntries: dayHealthEntries,
                        onToggle: { if let taskID = $0.task?.id { toggleTask(taskID) } },
                        onEdit: openBlock,
                        onDelete: { deletingTaskID = $0.task?.id }
                    )
                    Text("Tap a block to open it. Long-press for completion and other actions.")
                        .font(.footnote)
                        .foregroundStyle(Color.kadoForegroundSecondary)
                }
                .padding(16)
            }
            .refreshable {
                guard googleCalendar.isConnected, !isDevMode else { return }
                await googleCalendar.sync(using: modelContext)
            }
            .onAppear {
                if !timed.isEmpty {
                    let intervalStart = calendar.startOfDay(for: day)
                    let firstHour = timed.compactMap(\.schedule.startAt)
                        .map { max(0, calendar.component(.hour, from: max($0, intervalStart)) - 1) }.min() ?? 8
                    if let anchor = calendar.date(bySettingHour: firstHour, minute: 0, second: 0, of: day) {
                        proxy.scrollTo(anchor, anchor: .top)
                    }
                }
            }
        }
    }

    private func anyTimeSection(blocks: [CalendarBlockItem], tasks: [TaskListItem]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Any time").font(.headline)
            ForEach(blocks) { block in
                if let task = block.task {
                    TaskRowView(item: task, schedule: block.schedule, showsDate: false,
                        onToggle: { toggleTask(task.id) }, onEdit: { sheet = .editTask(task.id) }, onDelete: { deletingTaskID = task.id })
                } else {
                    Button { openBlock(block) } label: {
                        HStack {
                            Image(systemName: "repeat")
                            Text(block.title)
                            Spacer()
                        }
                        .frame(minHeight: 44)
                    }
                }
                Divider()
            }
            ForEach(tasks) { task in
                TaskRowView(item: task, showsDate: false,
                    onToggle: { toggleTask(task.id) }, onEdit: { sheet = .editTask(task.id) }, onDelete: { deletingTaskID = task.id })
                Divider()
            }
        }
        .padding(12)
        .background(Color.kadoBackgroundSecondary, in: RoundedRectangle(cornerRadius: KadoRadius.card))
    }

    private var visibleBlocks: [CalendarBlockItem] {
        blocks.filter { block in
            if let task = block.task, task.archivedAt != nil || task.externalCancelledAt != nil { return false }
            if let habit = block.habit, habit.archivedAt != nil { return false }
            guard block.task != nil || block.habit != nil else { return false }
            return TaskScheduleItem(block).belongs(to: day, calendar: calendar)
        }
        .map { CalendarBlockItem($0, on: day, calendar: calendar) }
    }

    private var tasksWithoutBlocks: [TaskListItem] {
        // The due day first, from the record: most tasks are due on
        // another day, and building an item reads the goal and every block.
        records
            .filter { record in
                guard let dueDate = record.dueDate else { return false }
                return calendar.isDate(dueDate, inSameDayAs: day)
            }
            .map { TaskListItem($0) }
            .filter { item in !item.schedules.contains { $0.belongs(to: day, calendar: calendar) } }
    }

    private func openBlock(_ block: CalendarBlockItem) {
        if let task = block.task { sheet = .editTask(task.id) }
        else if let habitID = block.habitID { sheet = .habit(habitID) }
    }

    private var pendingDeletion: TaskListItem? {
        guard let deletingTaskID, let record = records.first(where: { $0.id == deletingTaskID }) else { return nil }
        return TaskListItem(record)
    }

    private var deleteBinding: Binding<Bool> {
        Binding(get: { deletingTaskID != nil }, set: { if !$0 { deletingTaskID = nil } })
    }

    private var errorBinding: Binding<Bool> {
        Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
    }

    private func toggleTask(_ id: UUID) {
        guard let record = records.first(where: { $0.id == id }) else { return }
        record.completedAt = record.completedAt == nil ? .now : nil
        record.updatedAt = .now
        persist()
    }

    private func deleteTask(_ id: UUID) {
        guard let record = records.first(where: { $0.id == id }) else { return }
        if record.externalEventID != nil {
            record.archivedAt = .now
            record.updatedAt = .now
        } else {
            modelContext.delete(record)
        }
        deletingTaskID = nil
        persist()
    }

    private func persist() {
        do { try modelContext.save() }
        catch {
            modelContext.rollback()
            errorMessage = error.localizedDescription
        }
    }
}

#Preview("Calendar") {
    NavigationStack {
        CalendarDayAgenda(day: Calendar.current.startOfDay(for: .now))
    }
    .modelContainer(PreviewContainer.shared)
    .kadoTheme()
}

#Preview("Dark") {
    NavigationStack {
        CalendarDayAgenda(day: Calendar.current.startOfDay(for: .now))
    }
    .modelContainer(PreviewContainer.shared)
    .kadoTheme()
    .preferredColorScheme(.dark)
}
