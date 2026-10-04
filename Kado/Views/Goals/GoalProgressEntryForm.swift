import KadoCore
import SwiftData
import SwiftUI

struct GoalProgressEntryForm: View {
    let goalID: UUID
    var entryID: UUID?
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.calendar) private var calendar
    @Environment(\.locale) private var locale
    @Environment(\.civilToday) private var today
    @Query private var goals: [GoalRecord]
    @Query private var entries: [GoalProgressEntryRecord]
    @State private var date = Date.now
    @State private var amountText = "1"
    private var amount: Double { GoalProgressNumber.parse(amountText, locale: locale) ?? .nan }
    @State private var note = ""
    @State private var populated = false
    @State private var error: String?
    @State private var confirmingDelete = false

    private var goal: GoalRecord? { goals.first { $0.id == goalID } }
    private var entry: GoalProgressEntryRecord? { entries.first { $0.id == entryID && $0.goal?.id == goalID } }
    private var canEdit: Bool { goal?.archivedAt == nil && goal?.measurementEnabled == true && goal?.measurement.mode == .manual && goal != nil && (entryID == nil || entry != nil) }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("Progress date", selection: $date, in: ...today, displayedComponents: .date)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Amount").font(.footnote).foregroundStyle(.secondary)
                        TextField("Amount", text: $amountText)
                            .keyboardType(.decimalPad).accessibilityIdentifier("goal.progress.amount")
                    }
                    if let goal { LabeledContent("Unit", value: goal.progressUnit) }
                    TextField("Note (optional)", text: $note, axis: .vertical)
                        .accessibilityIdentifier("goal.progress.note")
                    if !amount.isFinite || amount <= 0 { Text("Enter a finite amount greater than zero.").foregroundStyle(.red) }
                }
                .disabled(!canEdit)
                if !canEdit { Text("Restore the goal and choose manual progress to edit entries.") }
                if entryID != nil {
                    Button("Delete progress entry", role: .destructive) { confirmingDelete = true }
                        .disabled(!canEdit).accessibilityIdentifier("goal.progress.delete")
                }
            }
            .navigationTitle(entryID == nil ? String(localized: "Add progress") : String(localized: "Edit progress"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save).disabled(!canEdit || !amount.isFinite || amount <= 0)
                        .accessibilityIdentifier("goal.progress.save")
                }
            }
            .onAppear {
                guard !populated else { return }; populated = true
                date = entry?.date ?? today; amountText = (entry?.amount ?? 1).formatted(.number.grouping(.never).locale(locale)); note = entry?.note ?? ""
            }
            .confirmationDialog("Delete this progress entry?", isPresented: $confirmingDelete, titleVisibility: .visible) {
                Button("Delete progress entry", role: .destructive, action: delete)
                Button("Cancel", role: .cancel) {}
            }
            .alert("Unable to save progress", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("Close", role: .cancel) {}
            } message: { Text(error ?? "") }
        }
    }
    private func save() {
        guard canEdit, let goal, amount.isFinite, amount > 0 else { return }
        let record: GoalProgressEntryRecord
        if entryID != nil { guard let entry else { return }; record = entry }
        else { record = GoalProgressEntryRecord(amount: amount, goal: goal); context.insert(record) }
        record.date = calendar.startOfDay(for: date); record.amount = amount
        record.note = note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : note
        record.updatedAt = .now; goal.updatedAt = .now
        persist()
    }
    private func delete() {
        guard canEdit, let entry else { return }
        context.delete(entry); goal?.updatedAt = .now; persist()
    }
    private func persist() {
        do { try context.save(); dismiss() }
        catch { context.rollback(); self.error = error.localizedDescription }
    }
}
