import KadoCore
import SwiftData
import SwiftUI

/// Only draft values and the task UUID live in retained state. The
/// record to mutate is resolved against the currently mounted store.
struct TaskFormView: View {
    let taskID: UUID?
    let defaultDay: Date?

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.calendar) private var calendar
    @Environment(\.civilToday) private var civilToday
    @Query private var records: [TaskRecord]
    @Query private var goals: [GoalRecord]

    @State private var title = ""
    @State private var notes = ""
    /// `nil` means not set. Times exist only with a day.
    @State private var day: Date?
    @State private var startTime: Date?
    @State private var endTime: Date?
    @State private var populated = false
    @State private var errorMessage: String?
    @State private var selectedGoalID: UUID?
    @FocusState private var titleFocused: Bool

    init(taskID: UUID? = nil, defaultDay: Date? = nil) {
        self.taskID = taskID
        self.defaultDay = defaultDay
    }

    var body: some View {
        NavigationStack {
            Group {
                if taskID != nil && item == nil {
                    ContentUnavailableView("Task unavailable", systemImage: "checklist", description: Text("This task is no longer in the current store."))
                } else {
                    form
                }
            }
            .background(Color.kadoBackground.ignoresSafeArea())
            .navigationTitle(taskID == nil ? String(localized: "New Task") : String(localized: "Task"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(isImported && selectedGoalID == item?.goalID ? String(localized: "Close") : String(localized: "Cancel")) { dismiss() }
                        .accessibilityIdentifier(AccessibilityID.Tasks.cancel)
                }
                if !isImported || selectedGoalID != item?.goalID {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save", action: save)
                            .disabled(!isValid)
                            .accessibilityIdentifier(AccessibilityID.Tasks.save)
                    }
                }
            }
            .onAppear(perform: populate)
            .alert("Unable to save task", isPresented: errorBinding) {
                Button("Close", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private var form: some View {
        Form {
            detailsSection
            schedulingSection
            GoalPickerSection(selectedGoalID: $selectedGoalID)
            if isImported {
                Section {
                    Label("Google Calendar", systemImage: "arrow.triangle.2.circlepath")
                    Text("Event details and times are managed in Google Calendar. Completion and goal assignment stay in this app.")
                        .font(.footnote)
                        .foregroundStyle(Color.kadoForegroundSecondary)
                    if let sourceURL {
                        Link("Open in Google Calendar", destination: sourceURL)
                    }
                }
                .listRowBackground(Color.kadoBackgroundSecondary)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.kadoBackground.ignoresSafeArea())
    }

    private var detailsSection: some View {
        Section {
            TextField("Task title", text: $title)
                .focused($titleFocused)
                .submitLabel(.done)
                .accessibilityIdentifier(AccessibilityID.Tasks.title)
            TextField("Notes (optional)", text: $notes, axis: .vertical)
                .lineLimit(3...6)
                .accessibilityIdentifier(AccessibilityID.Tasks.notes)
        } header: {
            Text("Details")
        }
        .disabled(isImported)
        .listRowBackground(Color.kadoBackgroundSecondary)
    }

    private var schedulingSection: some View {
        Section {
            OptionalDateRow(
                title: "Date",
                addTitle: "Add date",
                systemImage: "calendar",
                value: dayBinding,
                quickPicks: dayQuickPicks,
                suggestion: { civilToday },
                identifier: AccessibilityID.Tasks.day
            )
            if let day {
                OptionalDateRow(
                    title: "Start time",
                    addTitle: "Add start time",
                    systemImage: "clock",
                    value: $startTime,
                    kind: .time,
                    suggestion: { ScheduleDefaults.startTime(on: day, now: .now, calendar: calendar) },
                    identifier: AccessibilityID.Tasks.start
                )
                OptionalDateRow(
                    title: "End time",
                    addTitle: "Add end time",
                    systemImage: "clock.badge.checkmark",
                    value: $endTime,
                    kind: .time,
                    suggestion: {
                        ScheduleDefaults.endTime(on: day, start: startTime, now: .now, calendar: calendar)
                    },
                    identifier: AccessibilityID.Tasks.end
                )
                if let scheduleError {
                    Text(scheduleError)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .accessibilityIdentifier(AccessibilityID.Tasks.timeError)
                }
            }
        } header: {
            Text("Schedule (optional)")
        } footer: {
            Text(day != nil
                ? String(localized: "Start and end are optional. A task with no times appears under Any time in Calendar. Planned time does not mark a task complete.")
                : String(localized: "Without a day, this task stays in your Today inbox. You can schedule it later."))
        }
        .disabled(isImported)
        .listRowBackground(Color.kadoBackgroundSecondary)
    }

    private var item: TaskListItem? {
        guard let taskID, let record = records.first(where: { $0.id == taskID }) else { return nil }
        return TaskListItem(record)
    }

    private var isImported: Bool { item?.isFromGoogle == true }

    private var sourceURL: URL? {
        guard let taskID,
              let value = records.first(where: { $0.id == taskID })?.externalURL
        else { return nil }
        guard let url = URL(string: value), url.scheme?.lowercased() == "https" else { return nil }
        return url
    }

    /// Clearing the day clears its times too: a time needs a day.
    private var dayBinding: Binding<Date?> {
        Binding(
            get: { day },
            set: { newDay in
                day = newDay.map { calendar.startOfDay(for: $0) }
                if newDay == nil {
                    startTime = nil
                    endTime = nil
                }
            }
        )
    }

    private var dayQuickPicks: [OptionalDateRow.QuickPick] {
        let days = ScheduleDefaults.quickDays(today: civilToday, calendar: calendar)
        return [
            .init(id: "today", title: "Today", date: days.today),
            .init(id: "tomorrow", title: "Tomorrow", date: days.tomorrow),
        ]
    }

    private var errorBinding: Binding<Bool> {
        Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
    }

    private var draft: TaskScheduleDraft {
        TaskScheduleDraft(
            title: title,
            day: day,
            startTime: day == nil ? nil : startTime,
            endTime: day == nil ? nil : endTime
        )
    }

    private var scheduleError: String? {
        guard !isImported else { return nil }
        do {
            _ = try draft.normalized(using: calendar)
            return nil
        } catch TaskScheduleDraft.ValidationError.endMustFollowStart {
            return String(localized: "End time must be after start time.")
        } catch TaskScheduleDraft.ValidationError.timeUnavailableOnDay {
            return String(localized: "This clock time is unavailable on the selected day. Choose another time.")
        } catch {
            return nil
        }
    }

    private var isValid: Bool {
        if isImported { return item != nil }
        return (try? draft.normalized(using: calendar)) != nil && (taskID == nil || item != nil)
    }

    private func populate() {
        guard !populated else { return }
        let snapshot = item
        title = snapshot?.title ?? ""
        notes = snapshot?.notes ?? ""
        selectedGoalID = snapshot?.goalID
        let firstBlock = snapshot?.schedules.first
        let scheduledDay = firstBlock?.plannedDay ?? snapshot?.dueDate ?? defaultDay
        day = scheduledDay.map { calendar.startOfDay(for: $0) }
        startTime = firstBlock?.startAt
        endTime = firstBlock?.endAt
        populated = true
        titleFocused = taskID == nil && !UITestSupport.suppressesNameAutoFocus
    }

    private func save() {
        guard isValid else { return }
        let selectedGoal: GoalRecord?
        if let selectedGoalID {
            guard let currentGoal = goals.first(where: { $0.id == selectedGoalID }) else {
                errorMessage = String(localized: "This goal is no longer available. Choose another goal or remove the assignment.")
                return
            }
            selectedGoal = currentGoal
        } else {
            selectedGoal = nil
        }
        // Google owns event details. A goal is local organization and
        // can be changed without rewriting its title, plan or completion.
        if isImported {
            guard let taskID, let record = records.first(where: { $0.id == taskID }) else { return }
            if record.goal?.id != selectedGoalID {
                record.goal = selectedGoal
                record.updatedAt = .now
            }
            persistAndDismiss()
            return
        }
        guard let schedule = try? draft.normalized(using: calendar) else { return }
        let record: TaskRecord
        if let taskID {
            guard let existing = records.first(where: { $0.id == taskID }) else { return }
            record = existing
        } else {
            record = TaskRecord(title: schedule.title)
            modelContext.insert(record)
        }
        record.title = schedule.title
        record.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        record.updatedAt = .now
        record.dueDate = schedule.plannedDay
        record.goal = selectedGoal

        if let plannedDay = record.dueDate {
            let block: ScheduleBlockRecord
            if let existing = (record.scheduleBlocks ?? []).sorted(by: { $0.createdAt < $1.createdAt }).first {
                block = existing
            } else {
                block = ScheduleBlockRecord(plannedDay: plannedDay, task: record)
                modelContext.insert(block)
            }
            block.plannedDay = plannedDay
            block.startAt = schedule.startAt
            block.endAt = schedule.endAt
            block.updatedAt = .now
        } else {
            for block in record.scheduleBlocks ?? [] { modelContext.delete(block) }
        }
        persistAndDismiss()
    }

    private func persistAndDismiss() {
        do {
            try modelContext.save()
            dismiss()
        } catch {
            modelContext.rollback()
            errorMessage = error.localizedDescription
        }
    }
}

#Preview("Calendar task") {
    TaskFormView(defaultDay: .now)
        .modelContainer(PreviewContainer.shared)
        .kadoTheme()
}

#Preview("Dark") {
    TaskFormView()
        .modelContainer(PreviewContainer.shared)
        .kadoTheme()
        .preferredColorScheme(.dark)
}
