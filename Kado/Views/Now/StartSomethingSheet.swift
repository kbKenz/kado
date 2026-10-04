import SwiftUI
import KadoCore

/// Start a new task or habit by name, or pick an existing one.
struct StartSomethingSheet: View {
    let candidates: [NowItem]
    let onPick: (NowItem) -> Void
    let onStartNew: (String, QuickStartKind) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var kind: QuickStartKind = .task
    /// Set synchronously before acting so a second tap cannot start twice.
    /// Never reset: every path dismisses the sheet, so each presentation starts fresh.
    @State private var starting = false
    // Focus is a nicety: the screen works when the runtime ignores it.
    @FocusState private var titleFocused: Bool

    private var trimmedTitle: String { title.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField("What are you working on?", text: $title)
                        .focused($titleFocused)
                        .submitLabel(.go)
                        .onSubmit(startNew)
                        .accessibilityIdentifier(AccessibilityID.Now.quickStartTitle)
                    Picker("Task or habit", selection: $kind) {
                        Text("Task").tag(QuickStartKind.task)
                        Text("Habit").tag(QuickStartKind.habit)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .accessibilityIdentifier(AccessibilityID.Now.quickStartKind)
                }
                .listRowBackground(Color.kadoBackgroundSecondary)

                Section {
                    Button(action: startNew) {
                        Text("Start").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(trimmedTitle.isEmpty)
                    .accessibilityIdentifier(AccessibilityID.Now.quickStartStart)
                }
                .listRowBackground(Color.clear)

                if !candidates.isEmpty {
                    Section("Or pick one") {
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
            .onAppear { titleFocused = true }
        }
    }

    private func startNew() {
        guard !starting, !trimmedTitle.isEmpty else { return }
        starting = true
        onStartNew(trimmedTitle, kind)
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
        onStartNew: { _, _ in }
    )
}

#Preview("No candidates, Dark") {
    StartSomethingSheet(candidates: [], onPick: { _ in }, onStartNew: { _, _ in })
        .preferredColorScheme(.dark)
}
