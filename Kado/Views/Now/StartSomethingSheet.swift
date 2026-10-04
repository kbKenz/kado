import SwiftUI
import KadoCore

/// Pick any open task or today's habit and start it now.
struct StartSomethingSheet: View {
    let candidates: [NowItem]
    let onPick: (NowItem) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(candidates) { item in
                Button { onPick(item) } label: {
                    Label(item.title, systemImage: icon(for: item))
                        .foregroundStyle(Color.kadoForeground)
                }
                .listRowBackground(Color.kadoBackgroundSecondary)
                .accessibilityIdentifier(AccessibilityID.Now.candidate(item.id))
            }
            .scrollContentBackground(.hidden)
            .background(Color.kadoBackground.ignoresSafeArea())
            .overlay {
                if candidates.isEmpty {
                    ContentUnavailableView("Nothing to start", systemImage: "checkmark.circle", description: Text("No open tasks or habits left today."))
                }
            }
            .navigationTitle("Start something")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
            }
        }
    }

    private func icon(for item: NowItem) -> String {
        if case .task = item { return "checklist" }
        return "repeat"
    }
}

#Preview("Candidates") {
    StartSomethingSheet(
        candidates: [.task(id: UUID(), title: "Research"), .habit(id: UUID(), name: "Read 20 pages")],
        onPick: { _ in }
    )
}

#Preview("Empty, Dark") {
    StartSomethingSheet(candidates: [], onPick: { _ in })
        .preferredColorScheme(.dark)
}
