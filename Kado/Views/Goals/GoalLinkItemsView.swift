import KadoCore
import SwiftData
import SwiftUI

enum GoalLinkKind: Equatable {
    case tasks
    case habits

    var title: String {
        switch self {
        case .tasks: String(localized: "Link tasks")
        case .habits: String(localized: "Link habits")
        }
    }
}

/// Link operations resolve UUIDs in current queries, including on the
/// confirmation path. Reassignment changes only local goal metadata.
struct GoalLinkItemsView: View {
    let goalID: UUID
    let kind: GoalLinkKind

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var goals: [GoalRecord]
    @Query private var tasks: [TaskRecord]
    @Query private var habits: [HabitRecord]

    @State private var search = ""
    @State private var pendingMove: LinkItem?
    @State private var errorMessage: String?

    private struct LinkItem: Identifiable {
        let id: UUID
        let title: String
        let sourceGoalID: UUID?
        let sourceGoalName: String?
        let isArchived: Bool
        let isCancelled: Bool
        let isFromGoogle: Bool
    }

    var body: some View {
        NavigationStack {
            Group {
                if let goal = goalSnapshot, goal.archivedAt == nil {
                    itemList
                } else {
                    ContentUnavailableView("Goal unavailable", systemImage: "scope", description: Text("Restore this goal before linking items."))
                }
            }
            .navigationTitle(kind.title)
            .navigationBarTitleDisplayMode(.inline)
            .background(Color.kadoBackground.ignoresSafeArea())
            .searchable(text: $search, prompt: "Search items")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                        .accessibilityIdentifier(AccessibilityID.Goals.linkClose)
                }
            }
            .confirmationDialog("Move this item?", isPresented: moveBinding, titleVisibility: .visible, presenting: pendingMove) { item in
                Button("Move to this goal") { apply(item, confirmedSourceID: item.sourceGoalID) }
                    .accessibilityIdentifier(AccessibilityID.Goals.moveConfirm)
                Button("Cancel", role: .cancel) {}
            } message: { item in
                Text("\(item.title) is linked to \(item.sourceGoalName ?? String(localized: "another goal")). Moving it preserves its history.")
            }
            .alert("Unable to update goal links", isPresented: errorBinding) {
                Button("Close", role: .cancel) {}
            } message: { Text(errorMessage ?? "") }
        }
    }

    private var itemList: some View {
        List {
            if filteredItems.isEmpty {
                ContentUnavailableView("No matching items", systemImage: kind == .tasks ? "checklist" : "repeat", description: Text("Create a task or habit first, or change your search."))
                    .listRowBackground(Color.clear)
            } else {
                Section {
                    ForEach(filteredItems) { item in
                        itemRow(item)
                    }
                } footer: {
                    Text("An item belongs to one goal. Moving it changes its goal link and keeps its history.")
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.kadoBackground.ignoresSafeArea())
    }

    private func itemRow(_ item: LinkItem) -> some View {
        let linked = item.sourceGoalID == goalID
        return Button { apply(item) } label: {
            HStack(spacing: 12) {
                Image(systemName: linked ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(linked ? Color.kadoAccent : Color.kadoForegroundSecondary)
                    .font(.title3)
                VStack(alignment: .leading, spacing: 5) {
                    Text(item.title)
                        .foregroundStyle(Color.kadoForeground)
                    Text(linked ? String(localized: "Linked to this goal") : item.sourceGoalName.map { String(localized: "Currently linked to \($0)") } ?? String(localized: "No goal"))
                        .font(.caption)
                        .foregroundStyle(Color.kadoForegroundSecondary)
                    if item.isArchived { Text("Archived").font(.caption).foregroundStyle(Color.kadoForegroundSecondary) }
                    if item.isCancelled { Text("Removed from Google Calendar").font(.caption).foregroundStyle(Color.kadoForegroundSecondary) }
                    if item.isFromGoogle { Label("Google Calendar", systemImage: "arrow.triangle.2.circlepath").font(.caption).foregroundStyle(Color.kadoForegroundSecondary) }
                }
                Spacer(minLength: 0)
            }
            .frame(minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint(linked ? Text("Unlink from this goal") : Text("Link to this goal"))
        .accessibilityIdentifier(AccessibilityID.Goals.linkItem(item.id))
        .listRowBackground(Color.kadoBackgroundSecondary)
    }

    private var goalSnapshot: GoalListItem? {
        goals.first(where: { $0.id == goalID }).map { GoalListItem($0) }
    }

    private var items: [LinkItem] {
        switch kind {
        case .tasks:
            return tasks.map {
                LinkItem(id: $0.id, title: $0.title, sourceGoalID: $0.goal?.id,
                         sourceGoalName: $0.goal?.name, isArchived: $0.archivedAt != nil,
                         isCancelled: $0.externalCancelledAt != nil, isFromGoogle: $0.externalEventID != nil)
            }
        case .habits:
            return habits.map {
                LinkItem(id: $0.id, title: $0.name, sourceGoalID: $0.goal?.id,
                         sourceGoalName: $0.goal?.name, isArchived: $0.archivedAt != nil,
                         isCancelled: false, isFromGoogle: false)
            }
        }
    }

    private var filteredItems: [LinkItem] {
        items.filter { search.isEmpty || $0.title.localizedStandardContains(search) }
            .sorted { lhs, rhs in
                let leftLinked = lhs.sourceGoalID == goalID
                let rightLinked = rhs.sourceGoalID == goalID
                return leftLinked == rightLinked ? lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending : leftLinked
            }
    }

    private var moveBinding: Binding<Bool> {
        Binding(get: { pendingMove != nil }, set: { if !$0 { pendingMove = nil } })
    }

    private var errorBinding: Binding<Bool> {
        Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
    }

    private func apply(_ item: LinkItem, confirmedSourceID: UUID? = nil) {
        guard let goal = goals.first(where: { $0.id == goalID }), goal.archivedAt == nil,
              let current = items.first(where: { $0.id == item.id }) else { return }
        guard current.sourceGoalID == item.sourceGoalID else {
            errorMessage = String(localized: "This item's goal changed. Select it again to move it.")
            return
        }
        let confirmedMove = confirmedSourceID != nil
        if confirmedMove, current.sourceGoalID != confirmedSourceID {
            errorMessage = String(localized: "This item's goal changed. Select it again to move it.")
            return
        }
        // Confirmation assigns the destination explicitly. It never
        // inherits the tap-to-unlink behavior of an already-linked row.
        let unlinking = !confirmedMove && current.sourceGoalID == goalID
        if !unlinking, let sourceID = current.sourceGoalID, sourceID != confirmedSourceID {
            pendingMove = current
            return
        }
        let previousGoalID = current.sourceGoalID
        switch kind {
        case .tasks:
            guard let task = tasks.first(where: { $0.id == current.id }) else { return }
            task.goal = unlinking ? nil : goal
            task.updatedAt = .now
        case .habits:
            guard let habit = habits.first(where: { $0.id == current.id }) else { return }
            habit.goal = unlinking ? nil : goal
        }
        goal.updatedAt = .now
        if let previousGoalID, let previous = goals.first(where: { $0.id == previousGoalID }) {
            previous.updatedAt = .now
        }
        do { try modelContext.save() }
        catch {
            modelContext.rollback()
            errorMessage = error.localizedDescription
        }
    }
}

#Preview("Link tasks") {
    GoalLinkItemsView(goalID: GoalPreviewContainer.healthGoalID, kind: .tasks)
        .modelContainer(GoalPreviewContainer.shared)
        .kadoTheme()
}

#Preview("Dark") {
    GoalLinkItemsView(goalID: GoalPreviewContainer.healthGoalID, kind: .habits)
        .modelContainer(GoalPreviewContainer.shared)
        .kadoTheme()
        .preferredColorScheme(.dark)
}
