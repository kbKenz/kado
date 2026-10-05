import KadoCore
import SwiftData
import SwiftUI

/// Goal status is manual. Linked item status is always read from the
/// task's completedAt or the habit's existing completion records.
struct GoalDetailView: View {
    let goalID: UUID

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.calendar) private var calendar
    @Environment(\.today) private var today
    @Environment(\.civilToday) private var civilToday
    @Environment(\.frequencyEvaluator) private var frequencyEvaluator
    @Query private var goals: [GoalRecord]
    @Query private var tasks: [TaskRecord]
    @Query private var habits: [HabitRecord]
    @Query private var progressEntries: [GoalProgressEntryRecord]
    @Query private var completionRecords: [CompletionRecord]

    @State private var sheet: DetailSheet?
    @State private var confirmingDelete = false
    @State private var errorMessage: String?

    private enum DetailSheet: Identifiable {
        case progress(UUID?)
        case editGoal
        case task(UUID)
        case linkTasks
        case linkHabits
        case newTask
        /// Holds the form's model, so the sheet keeps what was typed
        /// when this screen redraws.
        case newHabit(NewHabitFormModel)

        var id: String {
            switch self {
            case .progress(let id): "progress-\(id?.uuidString ?? "new")"
            case .editGoal: "edit-goal"
            case .task(let id): "task-\(id)"
            case .linkTasks: "link-tasks"
            case .linkHabits: "link-habits"
            case .newTask: "new-task"
            case .newHabit: "new-habit"
            }
        }
    }

    private struct LinkedTask: Identifiable {
        let item: TaskListItem
        let isArchived: Bool
        let isCancelled: Bool
        var id: UUID { item.id }
        var isHistorical: Bool { isArchived || isCancelled }
    }

    private struct LinkedHabit: Identifiable {
        let habit: Habit
        let completions: [Completion]
        var id: UUID { habit.id }
    }

    var body: some View {
        Group {
            if let goal = snapshot {
                goalContent(goal)
            } else {
                ContentUnavailableView("Goal unavailable", systemImage: "scope", description: Text("This goal is no longer in the current store."))
            }
        }
        .background(Color.kadoBackground.ignoresSafeArea())
        .navigationTitle(snapshot?.name ?? String(localized: "Goal"))
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(for: HabitRoute.self) { route in HabitDetailLoader(habitID: route.id) }
        .toolbar { goalToolbar }
        .sheet(item: $sheet) { selection in
            switch selection {
            case .progress(let id): GoalProgressEntryForm(goalID: goalID, entryID: id)
            case .editGoal: GoalFormView(goalID: goalID)
            case .task(let id): TaskFormView(taskID: id)
            case .linkTasks: GoalLinkItemsView(goalID: goalID, kind: .tasks)
            case .linkHabits: GoalLinkItemsView(goalID: goalID, kind: .habits)
            case .newTask: TaskFormView(defaultGoalID: goalID)
            case .newHabit(let model): NewHabitFormView(model: model)
            }
        }
        .confirmationDialog("Delete this goal?", isPresented: $confirmingDelete, titleVisibility: .visible, presenting: snapshot) { _ in
            Button("Delete goal", role: .destructive, action: deleteGoal)
                .accessibilityIdentifier(AccessibilityID.Goals.deleteConfirm)
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("This permanently deletes the goal. Linked tasks and habits stay in your planner with all of their history.")
        }
        .alert("Unable to update goal", isPresented: errorBinding) {
            Button("Close", role: .cancel) {}
        } message: { Text(errorMessage ?? "") }
    }

    private func goalContent(_ goal: GoalListItem) -> some View {
        List {
            summarySection(goal)
            if goal.measurement.enabled {
                GoalProgressSection(goal: goal, result: progressResult(goal), manualEntries: progressEntries.filter { $0.goal?.id == goalID }.compactMap(\.snapshot), onAdd: { sheet = .progress(nil) }, onEdit: { sheet = .progress($0) }, onTask: { sheet = .task($0) })
            }
            linkedTasksSection
            linkedHabitsSection
            Section {
                Button { sheet = .newTask } label: { Label("Add task", systemImage: "plus.circle") }
                    .accessibilityIdentifier(AccessibilityID.Goals.addTask)
                Button { sheet = .newHabit(NewHabitFormModel(goalID: goalID)) } label: {
                    Label("Add habit", systemImage: "plus.circle")
                }
                .accessibilityIdentifier(AccessibilityID.Goals.addHabit)
            }
            .disabled(goal.archivedAt != nil)
            .listRowBackground(Color.kadoBackgroundSecondary)
            Section {
                Button { sheet = .linkTasks } label: { Label("Link tasks", systemImage: "checklist") }
                    .accessibilityIdentifier(AccessibilityID.Goals.linkTasks)
                Button { sheet = .linkHabits } label: { Label("Link habits", systemImage: "repeat") }
                    .accessibilityIdentifier(AccessibilityID.Goals.linkHabits)
            } footer: {
                Text(goal.archivedAt == nil
                    ? String(localized: "Link existing items or move them from another goal. Their history stays with them.")
                    : String(localized: "Restore this goal to add or move linked items."))
            }
            .disabled(goal.archivedAt != nil)
            .listRowBackground(Color.kadoBackgroundSecondary)
        }
        .scrollContentBackground(.hidden)
    }

    private func summarySection(_ goal: GoalListItem) -> some View {
        Section {
            Label(goal.status.plannerTitle, systemImage: goal.status.plannerSymbol)
                .foregroundStyle(Color.kadoAccent)
            Label {
                Text(goal.resolvedCategory.localizedName)
                    .foregroundStyle(Color.kadoForeground)
            } icon: {
                ItemGlyphView(glyph: ItemGlyph(category: goal.resolvedCategory))
            }
            if goal.archivedAt != nil {
                Label("Archived", systemImage: "archivebox")
                    .foregroundStyle(Color.kadoForegroundSecondary)
                Button("Restore goal") { setArchived(false) }
                    .accessibilityIdentifier(AccessibilityID.Goals.restore)
            }
            if !goal.details.isEmpty {
                Text(goal.details).textSelection(.enabled)
            }
            if let start = goal.startDate {
                LabeledContent("Starts") { Text(start, format: .dateTime.year().month(.abbreviated).day()) }
            }
            if let target = goal.targetDate {
                LabeledContent("Target") { Text(target, format: .dateTime.year().month(.abbreviated).day()) }
            }
            if goal.status == .completed, let completedAt = goal.completedAt {
                LabeledContent("Completed") { Text(completedAt, format: .dateTime.year().month(.abbreviated).day()) }
            }
        } footer: {
            Text("Goal status is yours to set. Completing linked items does not automatically complete the goal.")
        }
        .listRowBackground(Color.kadoBackgroundSecondary)
    }

    private var linkedTasksSection: some View {
        Section {
            if linkedTasks.isEmpty {
                Text("No linked tasks yet").foregroundStyle(Color.kadoForegroundSecondary)
            } else {
                ForEach(linkedTasks) { taskRow($0) }
            }
        } header: { Text("Tasks") }
        .listRowBackground(Color.kadoBackgroundSecondary)
    }

    private var linkedHabitsSection: some View {
        Section {
            if linkedHabits.isEmpty {
                Text("No linked habits yet").foregroundStyle(Color.kadoForegroundSecondary)
            } else {
                ForEach(linkedHabits) { habitRow($0) }
            }
        } header: { Text("Habits") }
        footer: { Text("Open a habit for its full completion history. Swipe an item to unlink it.") }
        .listRowBackground(Color.kadoBackgroundSecondary)
    }

    private func taskRow(_ linked: LinkedTask) -> some View {
        let task = linked.item
        return HStack(alignment: .top, spacing: 10) {
            Button { toggleTask(task.id) } label: {
                Image(systemName: task.isComplete ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(task.isComplete ? Color.kadoAccent : Color.kadoForegroundSecondary)
                    .frame(minWidth: 44, minHeight: 44)
            }
            .buttonStyle(.borderless)
            .disabled(linked.isHistorical)
            .accessibilityLabel(task.isComplete ? String(localized: "Mark incomplete") : String(localized: "Complete task"))
            .accessibilityValue(task.title)
            .accessibilityIdentifier(AccessibilityID.Goals.taskCompletion(task.id))
            Button { sheet = .task(task.id) } label: {
                VStack(alignment: .leading, spacing: 5) {
                    Text(task.title)
                        .foregroundStyle(task.isComplete ? Color.kadoForegroundSecondary : Color.kadoForeground)
                        .strikethrough(task.isComplete)
                        .multilineTextAlignment(.leading)
                    Text(task.isComplete ? String(localized: "Completed") : String(localized: "Incomplete"))
                        .font(.caption).foregroundStyle(Color.kadoForegroundSecondary)
                    if linked.isArchived { Text("Archived task").font(.caption).foregroundStyle(Color.kadoForegroundSecondary) }
                    if linked.isCancelled { Text("Removed from Google Calendar").font(.caption).foregroundStyle(Color.kadoForegroundSecondary) }
                    if task.isFromGoogle { Label("Google Calendar", systemImage: "arrow.triangle.2.circlepath").font(.caption).foregroundStyle(Color.kadoForegroundSecondary) }
                }
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .accessibilityElement(children: .combine)
            .accessibilityHint("Open task")
            .accessibilityIdentifier(AccessibilityID.Goals.task(task.id))
        }
        .contextMenu {
            Button("Open task") { sheet = .task(task.id) }
            Button("Unlink task", role: .destructive) { unlinkTask(task.id) }
        }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) { unlinkTask(task.id) } label: { Label("Unlink", systemImage: "link") }
        }
        .accessibilityAction(named: Text("Unlink task")) { unlinkTask(task.id) }
    }

    private func habitRow(_ linked: LinkedHabit) -> some View {
        NavigationLink(value: HabitRoute(id: linked.id)) {
            VStack(alignment: .leading, spacing: 5) {
                Label(linked.habit.name, systemImage: linked.habit.icon)
                    .foregroundStyle(Color.kadoForeground)
                Text(habitStatus(linked))
                    .font(.caption)
                    .foregroundStyle(Color.kadoForegroundSecondary)
            }
            .padding(.vertical, 4)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(AccessibilityID.Goals.habit(linked.id))
        .contextMenu {
            Button("Unlink habit", role: .destructive) { unlinkHabit(linked.id) }
        }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) { unlinkHabit(linked.id) } label: { Label("Unlink", systemImage: "link") }
        }
        .accessibilityAction(named: Text("Unlink habit")) { unlinkHabit(linked.id) }
    }

    @ToolbarContentBuilder
    private var goalToolbar: some ToolbarContent {
        if let goal = snapshot {
            ToolbarItem(placement: .primaryAction) {
                Button("Edit") { sheet = .editGoal }
                    .accessibilityIdentifier(AccessibilityID.Goals.edit)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Picker("Status", selection: statusBinding) {
                        ForEach(GoalStatus.allCases, id: \.self) { value in
                            Text(value.plannerTitle).tag(value)
                        }
                    }
                    if goal.archivedAt == nil {
                        Button { setArchived(true) } label: { Label("Archive goal", systemImage: "archivebox") }
                            .accessibilityIdentifier(AccessibilityID.Goals.archive)
                    } else {
                        Button { setArchived(false) } label: { Label("Restore goal", systemImage: "arrow.uturn.backward") }
                    }
                    Button(role: .destructive) { confirmingDelete = true } label: { Label("Delete goal", systemImage: "trash") }
                        .accessibilityIdentifier(AccessibilityID.Goals.delete)
                } label: { Label("Goal actions", systemImage: "ellipsis.circle") }
                .accessibilityIdentifier(AccessibilityID.Goals.actions)
            }
        }
    }

    private func progressResult(_ goal: GoalListItem) -> GoalProgressResult {
        GoalProgressCalculator.calculate(goalID: goalID, measurement: goal.measurement, startDate: goal.startDate, today: civilToday, calendar: calendar,
            entries: progressEntries.compactMap(\.snapshot),
            tasks: tasks.map { TaskBackup(id: $0.id, title: $0.title, createdAt: $0.createdAt, updatedAt: $0.updatedAt, completedAt: $0.completedAt, goalID: $0.goal?.id) },
            habits: habits.map(\.snapshot), completions: completionRecords.compactMap(\.snapshot))
    }

    private var snapshot: GoalListItem? {
        goals.first(where: { $0.id == goalID }).map { GoalListItem($0) }
    }

    private var linkedTasks: [LinkedTask] {
        tasks.filter { $0.goal?.id == goalID }.map {
            LinkedTask(item: TaskListItem($0), isArchived: $0.archivedAt != nil, isCancelled: $0.externalCancelledAt != nil)
        }.sorted {
            $0.item.isComplete == $1.item.isComplete
                ? $0.item.title.localizedStandardCompare($1.item.title) == .orderedAscending
                : !$0.item.isComplete
        }
    }

    private var linkedHabits: [LinkedHabit] {
        habits.filter { $0.goal?.id == goalID }.map {
            LinkedHabit(habit: $0.snapshot, completions: ($0.completions ?? []).compactMap(\.snapshot))
        }.sorted { $0.habit.name.localizedStandardCompare($1.habit.name) == .orderedAscending }
    }

    private func habitStatus(_ linked: LinkedHabit) -> String {
        if linked.habit.archivedAt != nil { return String(localized: "Archived habit") }
        let state = HabitRowState.resolve(habit: linked.habit, completions: linked.completions, calendar: calendar, asOf: today)
        if case .negative = linked.habit.type {
            return state.status == .complete ? String(localized: "Slipped today") : String(localized: "No slip recorded today")
        }
        if !frequencyEvaluator.isDueOrLogged(habit: linked.habit, on: today, completions: linked.completions, calendar: calendar) {
            return String(localized: "Not scheduled today")
        }
        switch state.status {
        case .none: return String(localized: "No progress recorded today")
        case .partial: return String(localized: "In progress today")
        case .complete: return String(localized: "Done today")
        }
    }

    private var statusBinding: Binding<GoalStatus> {
        Binding(get: { snapshot?.status ?? .active }, set: setStatus)
    }

    private var errorBinding: Binding<Bool> {
        Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
    }

    private func setStatus(_ status: GoalStatus) {
        guard let goal = goals.first(where: { $0.id == goalID }) else { return }
        goal.status = status
        goal.completedAt = status == .completed ? (goal.completedAt ?? .now) : nil
        goal.updatedAt = .now
        persist()
    }

    private func setArchived(_ archived: Bool) {
        guard let goal = goals.first(where: { $0.id == goalID }) else { return }
        goal.archivedAt = archived ? .now : nil
        goal.updatedAt = .now
        persist()
    }

    private func toggleTask(_ id: UUID) {
        guard let task = tasks.first(where: { $0.id == id && $0.goal?.id == goalID }),
              task.archivedAt == nil, task.externalCancelledAt == nil else { return }
        task.completedAt = task.completedAt == nil ? .now : nil
        task.updatedAt = .now
        persist()
    }

    private func unlinkTask(_ id: UUID) {
        guard let task = tasks.first(where: { $0.id == id && $0.goal?.id == goalID }) else { return }
        task.goal = nil
        task.updatedAt = .now
        goals.first(where: { $0.id == goalID })?.updatedAt = .now
        persist()
    }

    private func unlinkHabit(_ id: UUID) {
        guard let habit = habits.first(where: { $0.id == id && $0.goal?.id == goalID }) else { return }
        habit.goal = nil
        goals.first(where: { $0.id == goalID })?.updatedAt = .now
        persist()
    }

    private func deleteGoal() {
        guard let goal = goals.first(where: { $0.id == goalID }) else { return }
        // Explicit unlinking and the schema's nullify rule both preserve
        // all item records, completions, and planned calendar blocks.
        for task in tasks where task.goal?.id == goalID {
            task.goal = nil
            task.updatedAt = .now
        }
        for habit in habits where habit.goal?.id == goalID { habit.goal = nil }
        modelContext.delete(goal)
        do {
            try modelContext.save()
            dismiss()
        } catch {
            modelContext.rollback()
            errorMessage = error.localizedDescription
        }
    }

    private func persist() {
        do { try modelContext.save() }
        catch {
            modelContext.rollback()
            errorMessage = error.localizedDescription
        }
    }
}

#Preview("Linked items") {
    NavigationStack { GoalDetailView(goalID: GoalPreviewContainer.healthGoalID) }
        .modelContainer(GoalPreviewContainer.shared)
        .kadoTheme()
}

#Preview("Dark") {
    NavigationStack { GoalDetailView(goalID: GoalPreviewContainer.healthGoalID) }
        .modelContainer(GoalPreviewContainer.shared)
        .kadoTheme()
        .preferredColorScheme(.dark)
}
