import SwiftUI
import KadoCore

/// A month calendar to jump the History to a day. Picking a day closes
/// the sheet at once: one tap, no Done button to find.
struct HistoryJumpSheet: View {
    /// From the oldest day shown to today.
    let range: ClosedRange<Date>
    let onPick: (Date) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var picked: Date?

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                DatePicker(
                    "Day",
                    selection: Binding(
                        get: { picked ?? range.upperBound },
                        set: { day in
                            picked = day
                            onPick(day)
                            dismiss()
                        }
                    ),
                    in: range,
                    displayedComponents: .date
                )
                .datePickerStyle(.graphical)
                .labelsHidden()
                .padding(.horizontal)
                Spacer(minLength: 0)
            }
            .navigationTitle("Go to date")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Today") {
                        onPick(range.upperBound)
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

#Preview("Jump") {
    let today = Calendar.current.startOfDay(for: .now)
    let start = Calendar.current.date(byAdding: .month, value: -3, to: today)!
    return Color.kadoBackground.sheet(isPresented: .constant(true)) {
        HistoryJumpSheet(range: start...today) { _ in }
    }
}

#Preview("Dark") {
    let today = Calendar.current.startOfDay(for: .now)
    let start = Calendar.current.date(byAdding: .day, value: -20, to: today)!
    return Color.kadoBackground.sheet(isPresented: .constant(true)) {
        HistoryJumpSheet(range: start...today) { _ in }
    }
    .preferredColorScheme(.dark)
}
