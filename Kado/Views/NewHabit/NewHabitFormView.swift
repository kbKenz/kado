import SwiftData
import SwiftUI
import KadoCore

/// Create or edit a habit and its optional goal assignment using
/// draft values; the current store resolves identities when saving.
struct NewHabitFormView: View {
    @Bindable var model: NewHabitFormModel
    /// Called with the habit's ID after a successful save, before the form closes.
    var onSaved: ((UUID) -> Void)?

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.notificationScheduler) private var notificationScheduler
    @Environment(\.dayBoundary) private var dayBoundary
    @Environment(\.calendar) private var calendar
    /// For title suggestions only: the goals the name can point to.
    @Query private var goals: [GoalRecord]

    @FocusState private var nameFocused: Bool
    @State private var saveTick: Int = 0
    @State private var showingPermissionDeniedAlert = false
    @State private var isSaving = false
    @State private var saveError: String?

    var body: some View {
        NavigationStack {
            Form {
                nameSection
                appearanceSection
                frequencySection
                typeSection
                reminderSection
                CategoryPickerSection(
                    selection: $model.category,
                    isSuggested: model.suggestions.categoryOrigin == .suggested,
                    identifier: AccessibilityID.Suggestion.habitCategory
                )
                GoalPickerSection(
                    selectedGoalID: $model.selectedGoalID,
                    isSuggested: model.suggestions.goalOrigin == .suggested
                )
            }
            .scrollContentBackground(.hidden)
            .background(Color.kadoBackground.ignoresSafeArea())
            .titleSuggestions(model.suggestions, title: model.name, goals: goals.map { SuggestionGoal($0) })
            .navigationTitle(model.isEditing
                ? String(localized: "Edit Habit")
                : String(localized: "New Habit"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .accessibilityIdentifier(AccessibilityID.NewHabit.cancelButton)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(!model.isValid || isSaving)
                        .accessibilityIdentifier(AccessibilityID.NewHabit.saveButton)
                }
            }
            .sensoryFeedback(.success, trigger: saveTick)
            // Focused on appear so a real user starts typing straight
            // away — except under the screenshot run, where the
            // keyboard would cover the half of the form the shot is
            // about. See `UITestSupport.suppressesNameAutoFocus`.
            .onAppear { nameFocused = !UITestSupport.suppressesNameAutoFocus }
            .alert(
                String(localized: "Notifications are disabled"),
                isPresented: $showingPermissionDeniedAlert
            ) {
                Button(String(localized: "Open Settings")) {
                    openNotificationSettings()
                }
                Button(String(localized: "Not now"), role: .cancel) {}
            } message: {
                Text(String(localized: "Enable notifications in Settings to receive this reminder."))
            }
            .alert("Unable to save habit", isPresented: saveErrorBinding) {
                Button("Close", role: .cancel) {}
            } message: {
                Text(saveError ?? "")
            }
        }
    }

    private var nameSection: some View {
        Section {
            TextField(String(localized: "Habit name"), text: $model.name)
                .focused($nameFocused)
                .submitLabel(.done)
                .accessibilityIdentifier(AccessibilityID.NewHabit.nameField)
                .assistedInput($model.name, identifier: AccessibilityID.NewHabit.nameField)
            if !model.suggestions.chips.isEmpty {
                SuggestionStrip(draft: model.suggestions)
            }
        }
        .listRowBackground(Color.kadoBackgroundSecondary)
    }

    private var appearanceSection: some View {
        Section {
            HabitColorPicker(selection: $model.color)
            HabitIconPicker(selection: $model.icon, tint: model.color)
        } header: {
            Text("Appearance")
                .foregroundStyle(Color.kadoForegroundSecondary)
        } footer: {
            if model.suggestions.iconOrigin == .suggested || model.suggestions.colorOrigin == .suggested {
                SuggestedCaption(identifier: AccessibilityID.Suggestion.iconBadge)
            }
        }
        .listRowBackground(Color.kadoBackgroundSecondary)
    }

    private var frequencySection: some View {
        Section {
            Picker(String(localized: "Repeats"), selection: $model.frequencyKind) {
                Text("Every day").tag(NewHabitFormModel.FrequencyKind.daily)
                Text("A few times a week").tag(NewHabitFormModel.FrequencyKind.daysPerWeek)
                Text("Specific days").tag(NewHabitFormModel.FrequencyKind.specificDays)
                Text("Every N days").tag(NewHabitFormModel.FrequencyKind.everyNDays)
            }

            switch model.frequencyKind {
            case .daily:
                EmptyView()
            case .daysPerWeek:
                Stepper(
                    String(localized: "\(model.daysPerWeek) days per week"),
                    value: $model.daysPerWeek,
                    in: 1...7
                )
            case .specificDays:
                WeekdayPicker(selection: $model.specificDays)
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
            case .everyNDays:
                Stepper(
                    String(localized: "Every \(model.everyNDays) days"),
                    value: $model.everyNDays,
                    in: 1...60
                )
            }
        } header: {
            Text("Frequency")
                .foregroundStyle(Color.kadoForegroundSecondary)
        }
        .listRowBackground(Color.kadoBackgroundSecondary)
    }

    private var typeSection: some View {
        Section {
            Picker(String(localized: "How is it measured?"), selection: $model.typeKind) {
                Text("Yes / no").tag(NewHabitFormModel.HabitTypeKind.binary)
                Text("Counter").tag(NewHabitFormModel.HabitTypeKind.counter)
                Text("Timer").tag(NewHabitFormModel.HabitTypeKind.timer)
                Text("Avoid").tag(NewHabitFormModel.HabitTypeKind.negative)
            }

            switch model.typeKind {
            case .binary, .negative:
                EmptyView()
            case .counter:
                Stepper(
                    String(localized: "Target: \(Int(model.counterTarget))"),
                    value: $model.counterTarget,
                    in: 1...999,
                    step: 1
                )
            case .timer:
                Stepper(
                    String(localized: "Target: \(model.timerTargetMinutes) min"),
                    value: $model.timerTargetMinutes,
                    in: 1...240
                )
            }
        } header: {
            Text("Type")
                .foregroundStyle(Color.kadoForegroundSecondary)
        }
        .listRowBackground(Color.kadoBackgroundSecondary)
    }

    private var reminderSection: some View {
        Section {
            Toggle(String(localized: "Remind me"), isOn: $model.remindersEnabled)
            if model.remindersEnabled {
                DatePicker(
                    String(localized: "Time"),
                    selection: $model.reminderTime,
                    displayedComponents: .hourAndMinute
                )
            }
        } header: {
            Text("Reminder")
                .foregroundStyle(Color.kadoForegroundSecondary)
        } footer: {
            if model.remindersEnabled {
                Text(String(localized: "Fires on \(frequencyFooter)"))
                    .foregroundStyle(Color.kadoForegroundSecondary)
            }
        }
        .listRowBackground(Color.kadoBackgroundSecondary)
    }

    private var frequencyFooter: String {
        switch model.frequency {
        case .daily:
            return String(localized: "every day")
        case .daysPerWeek(let n):
            return String(localized: "\(n) days each week")
        case .specificDays(let days):
            let ordered = Weekday.week(startingOn: calendar.firstWeekday)
            return ordered.filter(days.contains).map(\.localizedMedium).joined(separator: " · ")
        case .everyNDays(let n):
            return String(localized: "every \(n) days")
        }
    }

    private func save() {
        guard model.isValid, !isSaving else { return }
        isSaving = true
        // No suggestion may change a field while the save waits for the
        // notification prompt.
        model.suggestions.freeze()
        Task {
            defer { isSaving = false }
            if model.remindersEnabled {
                let status = await notificationScheduler.requestAuthorizationIfNeeded()
                if status == .denied {
                    showingPermissionDeniedAlert = true
                    model.suggestions.thaw()
                    return
                }
            }
            do {
                let record = try model.save(in: modelContext, createdAt: dayBoundary.loggingInstant(for: .now))
                saveTick += 1
                onSaved?(record.id)
                dismiss()
            } catch {
                saveError = error.localizedDescription
                model.suggestions.thaw()
            }
        }
    }

    private var saveErrorBinding: Binding<Bool> {
        Binding(get: { saveError != nil }, set: { if !$0 { saveError = nil } })
    }

    private func openNotificationSettings() {
        guard let url = URL(string: UIApplication.openNotificationSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}

#Preview("Default") {
    NewHabitFormView(model: NewHabitFormModel())
        .modelContainer(PreviewContainer.emptyContainer())
}

#Preview("Pre-filled counter") {
    let model = NewHabitFormModel()
    model.name = "Drink water"
    model.typeKind = .counter
    model.counterTarget = 8
    return NewHabitFormView(model: model)
        .modelContainer(PreviewContainer.emptyContainer())
}

#Preview("Pre-filled specific days") {
    let model = NewHabitFormModel()
    model.name = "Gym"
    model.frequencyKind = .specificDays
    model.specificDays = [.monday, .wednesday, .friday]
    return NewHabitFormView(model: model)
        .modelContainer(PreviewContainer.emptyContainer())
}

#Preview("Reminder on") {
    let model = NewHabitFormModel()
    model.name = "Meditate"
    model.remindersEnabled = true
    model.reminderTime = Calendar.current.date(bySettingHour: 7, minute: 15, second: 0, of: .now)!
    return NewHabitFormView(model: model)
        .modelContainer(PreviewContainer.emptyContainer())
}

#Preview("Suggested") {
    let model = NewHabitFormModel()
    model.name = "Read 20 pages"
    model.suggestions.applyWords(title: model.name, goals: [])
    return NewHabitFormView(model: model)
        .modelContainer(PreviewContainer.emptyContainer())
}

#Preview("From a goal") {
    NewHabitFormView(model: NewHabitFormModel(goalID: GoalPreviewContainer.healthGoalID))
        .modelContainer(GoalPreviewContainer.shared)
}

#Preview("Dark") {
    let model = NewHabitFormModel()
    model.name = "Gym"
    model.frequencyKind = .specificDays
    model.specificDays = [.monday, .wednesday, .friday]
    return NewHabitFormView(model: model)
        .modelContainer(PreviewContainer.emptyContainer())
        .preferredColorScheme(.dark)
}
