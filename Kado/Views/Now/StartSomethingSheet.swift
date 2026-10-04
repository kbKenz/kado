import SwiftData
import SwiftUI
import KadoCore

/// Create a task or habit with the full form and start it, or pick a
/// recent one.
struct StartSomethingSheet: View {
    let candidates: [NowItem]
    let onPick: (NowItem) -> Void
    /// Called after the New Task form saves, with the new task's ID.
    let onCreatedTask: (UUID) -> Void
    /// Called after the New Habit form saves, with the new habit's ID.
    let onCreatedHabit: (UUID) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.calendar) private var calendar
    @Environment(\.civilToday) private var civilToday
    @State private var form: NewForm?
    /// Set synchronously before acting so a second tap cannot start twice.
    /// Never reset: every path dismisses the sheet, so each presentation starts fresh.
    @State private var starting = false

    private enum NewForm: String, Identifiable {
        case task, habit
        var id: String { rawValue }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button { form = .task } label: {
                        Label("New task", systemImage: "checklist")
                    }
                    .accessibilityIdentifier(AccessibilityID.Now.newTask)
                    Button { form = .habit } label: {
                        Label("New habit", systemImage: "repeat")
                    }
                    .accessibilityIdentifier(AccessibilityID.Now.newHabit)
                }
                .foregroundStyle(Color.kadoForeground)
                .listRowBackground(Color.kadoBackgroundSecondary)

                if !candidates.isEmpty {
                    Section("Recent") {
                        ForEach(candidates) { item in
                            Button {
                                guard !starting else { return }
                                starting = true
                                onPick(item)
                            } label: {
                                Label(item.title, systemImage: icon(for: item))
                                    .foregroundStyle(Color.kadoForeground)
                            }
                            .accessibilityIdentifier(AccessibilityID.Now.candidate(item.id))
                        }
                        .listRowBackground(Color.kadoBackgroundSecondary)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.kadoBackground.ignoresSafeArea())
            .navigationTitle("Start something")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
            }
            .sheet(item: $form) { kind in
                switch kind {
                case .task:
                    // Today, at the quarter hour nearest to now (15:33 → 15:30).
                    TaskFormView(
                        defaultDay: civilToday,
                        defaultStartTime: ScheduleDefaults.nearestQuarterHour(to: .now, calendar: calendar),
                        onSaved: { id in created { onCreatedTask(id) } }
                    )
                case .habit:
                    NewHabitFormView(model: NewHabitFormModel(), onSaved: { id in created { onCreatedHabit(id) } })
                }
            }
        }
    }

    private func created(_ action: () -> Void) {
        guard !starting else { return }
        starting = true
        action()
    }

    private func icon(for item: NowItem) -> String {
        if case .task = item { return "checklist" }
        return "repeat"
    }
}

#Preview("Candidates") {
    StartSomethingSheet(
        candidates: [.task(id: UUID(), title: "Research"), .habit(id: UUID(), name: "Read 20 pages")],
        onPick: { _ in },
        onCreatedTask: { _ in },
        onCreatedHabit: { _ in }
    )
    .modelContainer(PreviewContainer.shared)
    .kadoTheme()
}

#Preview("No candidates, Dark") {
    StartSomethingSheet(candidates: [], onPick: { _ in }, onCreatedTask: { _ in }, onCreatedHabit: { _ in })
        .modelContainer(PreviewContainer.shared)
        .kadoTheme()
        .preferredColorScheme(.dark)
}
