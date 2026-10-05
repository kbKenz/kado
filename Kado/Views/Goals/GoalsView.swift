import KadoCore
import SwiftData
import SwiftUI

struct GoalsView: View {
    @Query(sort: \GoalRecord.createdAt, order: .reverse) private var records: [GoalRecord]
    @Environment(\.civilToday) private var today
    @Environment(\.calendar) private var calendar
    @Query private var entries: [GoalProgressEntryRecord]
    @Query private var tasks: [TaskRecord]
    @Query private var habits: [HabitRecord]
    @Query private var completions: [CompletionRecord]
    @State private var path = NavigationPath()
    @State private var showingNewGoal = false

    var body: some View {
        NavigationStack(path: $path) {
            content
                .navigationTitle("Goals")
                .background(Color.kadoBackground.ignoresSafeArea())
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button { showingNewGoal = true } label: {
                            Label("New goal", systemImage: "plus")
                        }
                        .accessibilityIdentifier(AccessibilityID.Goals.newGoal)
                    }
                }
                .navigationDestination(for: GoalRoute.self) { route in
                    GoalDetailView(goalID: route.id)
                }
                .sheet(isPresented: $showingNewGoal) {
                    GoalFormView(onSaved: { path.append(GoalRoute(id: $0)) })
                }
        }
    }

    @ViewBuilder
    private var content: some View {
        let snapshots = records.map { GoalListItem($0) }
        // One pass over each table for every row, not one per row.
        let inputs = GoalProgressInputs(
            measurements: snapshots.map(\.measurement),
            entries: entries, tasks: tasks, habits: habits, completions: completions
        )
        if snapshots.isEmpty {
            ContentUnavailableView {
                Label("No goals yet", systemImage: "scope")
            } description: {
                Text("Connect habits and tasks to something you want to achieve.")
            } actions: {
                Button("Create a goal") { showingNewGoal = true }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier(AccessibilityID.Goals.emptyCreate)
            }
        } else {
            List {
                ForEach(GoalStatus.allCases, id: \.self) { status in
                    let matching = snapshots.filter { $0.archivedAt == nil && $0.status == status }
                    if !matching.isEmpty {
                        Section(status.plannerTitle) {
                            ForEach(matching) { goalRow($0, inputs: inputs) }
                        }
                    }
                }
                let archived = snapshots.filter { $0.archivedAt != nil }
                if !archived.isEmpty {
                    Section {
                        ForEach(archived) { goalRow($0, inputs: inputs) }
                    } header: { Text("Archived") }
                    footer: { Text("Open an archived goal to restore it. Linked items keep their history.") }
                }
            }
            .scrollContentBackground(.hidden)
        }
    }

    private func goalRow(_ item: GoalListItem, inputs: GoalProgressInputs) -> some View {
        NavigationLink(value: GoalRoute(id: item.id)) {
            GoalRowView(item: item, progress: item.measurement.enabled ? inputs.progress(goalID: item.id, measurement: item.measurement, startDate: item.startDate, today: today, calendar: calendar) : nil)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel { label in
            label
            Text(item.resolvedCategory.localizedName)
        }
        .accessibilityIdentifier(AccessibilityID.Goals.row(item.id))
        .listRowBackground(Color.kadoBackgroundSecondary)
    }
}

#Preview("Goals") {
    GoalsView().modelContainer(GoalPreviewContainer.shared).kadoTheme()
}

#Preview("Dark") {
    GoalsView()
        .modelContainer(GoalPreviewContainer.shared)
        .kadoTheme()
        .preferredColorScheme(.dark)
}
