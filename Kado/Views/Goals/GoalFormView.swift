import KadoCore
import SwiftData
import SwiftUI

struct GoalFormView: View {
    let goalID: UUID?
    var onSaved: ((UUID) -> Void)?

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.calendar) private var calendar
    @Environment(\.civilToday) private var civilToday
    @Query private var records: [GoalRecord]
    @Query private var habits: [HabitRecord]

    @State private var measurement = GoalMeasurement()
    @State private var confirmingMeasurementChange = false
    @State private var name = ""
    @State private var details = ""
    @State private var status: GoalStatus = .active
    /// `nil` means not set.
    @State private var startDate: Date?
    @State private var targetDate: Date?
    @State private var populated = false
    @State private var errorMessage: String?
    @FocusState private var nameFocused: Bool

    init(goalID: UUID? = nil, onSaved: ((UUID) -> Void)? = nil) {
        self.goalID = goalID
        self.onSaved = onSaved
    }

    var body: some View {
        NavigationStack {
            Group {
                if goalID != nil && snapshot == nil {
                    ContentUnavailableView("Goal unavailable", systemImage: "scope", description: Text("This goal is no longer in the current store."))
                } else {
                    form
                }
            }
            .navigationTitle(goalID == nil ? String(localized: "New Goal") : String(localized: "Edit Goal"))
            .navigationBarTitleDisplayMode(.inline)
            .background(Color.kadoBackground.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .accessibilityIdentifier(AccessibilityID.Goals.cancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: requestSave)
                        .disabled(!isValid)
                        .accessibilityIdentifier(AccessibilityID.Goals.save)
                }
            }
            .onAppear(perform: populate)
            .confirmationDialog("Recalculate progress?", isPresented: $confirmingMeasurementChange, titleVisibility: .visible) {
                Button("Save changes", action: save)
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Changing measurement source recalculates the total. Existing manual entries and linked item history remain stored.")
            }
            .alert("Unable to save goal", isPresented: errorBinding) {
                Button("Close", role: .cancel) {}
            } message: { Text(errorMessage ?? "") }
        }
    }

    private var form: some View {
        Form {
            Section {
                TextField("Goal name", text: $name)
                    .focused($nameFocused)
                    .submitLabel(.done)
                    .accessibilityIdentifier(AccessibilityID.Goals.name)
                TextField("Why this matters (optional)", text: $details, axis: .vertical)
                    .lineLimit(3...8)
                    .accessibilityIdentifier(AccessibilityID.Goals.details)
            } header: { Text("Details") }
            .listRowBackground(Color.kadoBackgroundSecondary)
            Section {
                Picker("Status", selection: $status) {
                    ForEach(GoalStatus.allCases, id: \.self) { value in
                        Label(value.plannerTitle, systemImage: value.plannerSymbol).tag(value)
                    }
                }
                .accessibilityIdentifier(AccessibilityID.Goals.status)
            } footer: {
                Text("You decide when a goal is paused or completed. Linked tasks and habits keep their own completion history.")
            }
            .listRowBackground(Color.kadoBackgroundSecondary)
            datesSection.disabled(snapshot?.archivedAt != nil)
            GoalMeasurementSection(measurement: $measurement, habits: habits.filter { $0.goal?.id == goalID && goalID != nil }.map(\.snapshot))
                .disabled(snapshot?.archivedAt != nil)
        }
        .scrollContentBackground(.hidden)
        .background(Color.kadoBackground.ignoresSafeArea())
    }

    private var datesSection: some View {
        Section {
            OptionalDateRow(
                title: "Start date",
                addTitle: "Add start date",
                systemImage: "flag",
                value: $startDate,
                suggestion: { civilToday },
                identifier: AccessibilityID.Goals.startDate
            )
            OptionalDateRow(
                title: "Target date",
                addTitle: "Add target date",
                systemImage: "flag.checkered",
                value: $targetDate,
                // A target before the start would be refused; open on
                // the start when there is one.
                suggestion: { startDate ?? civilToday },
                identifier: AccessibilityID.Goals.targetDate
            )
            if !validDates {
                Text("Target date must be on or after start date.")
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .accessibilityIdentifier(AccessibilityID.Goals.dateError)
            }
        } header: { Text("Dates (optional)") }
        .listRowBackground(Color.kadoBackgroundSecondary)
    }

    private var snapshot: GoalListItem? {
        guard let goalID, let record = records.first(where: { $0.id == goalID }) else { return nil }
        return GoalListItem(record)
    }

    private var errorBinding: Binding<Bool> {
        Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
    }

    private var validDates: Bool {
        guard let startDate, let targetDate else { return true }
        return calendar.startOfDay(for: targetDate) >= calendar.startOfDay(for: startDate)
    }

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && validDates
            && (goalID == nil || snapshot != nil) && measurement.isValid
    }

    private func populate() {
        guard !populated else { return }
        let item = snapshot
        measurement = item?.measurement ?? GoalMeasurement()
        name = item?.name ?? ""
        details = item?.details ?? ""
        status = item?.status ?? .active
        startDate = item?.startDate
        targetDate = item?.targetDate
        populated = true
        nameFocused = goalID == nil && !UITestSupport.suppressesNameAutoFocus
    }

    private func requestSave() {
        if let old = snapshot?.measurement, old.enabled && (old.mode != measurement.mode || old.habitID != measurement.habitID) {
            confirmingMeasurementChange = true
        } else { save() }
    }

    private func save() {
        guard isValid else { return }
        let record: GoalRecord
        if let goalID {
            guard let current = records.first(where: { $0.id == goalID }) else { return }
            record = current
        } else {
            record = GoalRecord()
            modelContext.insert(record)
        }
        if record.archivedAt == nil { record.measurement = measurement }
        record.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        record.details = details.trimmingCharacters(in: .whitespacesAndNewlines)
        record.status = status
        record.completedAt = status == .completed ? (record.completedAt ?? .now) : nil
        if record.archivedAt == nil {
            record.startDate = startDate.map { calendar.startOfDay(for: $0) }
            record.targetDate = targetDate.map { calendar.startOfDay(for: $0) }
        }
        record.updatedAt = .now
        do {
            try modelContext.save()
            onSaved?(record.id)
            dismiss()
        } catch {
            modelContext.rollback()
            errorMessage = error.localizedDescription
        }
    }
}

#Preview("New goal") {
    GoalFormView().modelContainer(GoalPreviewContainer.shared).kadoTheme()
}

#Preview("Dark") {
    GoalFormView(goalID: GoalPreviewContainer.healthGoalID)
        .modelContainer(GoalPreviewContainer.shared)
        .kadoTheme()
        .preferredColorScheme(.dark)
}
