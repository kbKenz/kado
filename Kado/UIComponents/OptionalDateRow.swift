import SwiftUI

/// A form row for an optional date or time, replacing a "has X" toggle
/// plus picker. Empty, it offers to add one: an "Add…" button, or quick
/// picks (Today, Tomorrow) and "+" for a day. Set, it shows the value,
/// tappable to change, with a clear button. Disabled (imported tasks,
/// archived goals), it reads "None" or the value, with no controls.
///
/// Identifiers derive from `identifier`: the picker itself carries it
/// unchanged; `AccessibilityID.OptionalDate` builds the rest.
struct OptionalDateRow: View {
    enum Kind {
        /// "Add" opens a calendar; the user picks the date.
        case date
        /// "Add" fills in `suggestion()` at once; the user adjusts it.
        case time
    }

    struct QuickPick: Identifiable {
        let id: String
        let title: LocalizedStringKey
        let date: Date
    }

    let title: LocalizedStringKey
    let addTitle: LocalizedStringKey
    let systemImage: String
    @Binding var value: Date?
    var kind: Kind = .date
    var quickPicks: [QuickPick] = []
    /// The date the calendar opens on, or the time "Add" fills in.
    let suggestion: () -> Date
    let identifier: String

    @Environment(\.isEnabled) private var isEnabled
    @State private var isPicking = false
    @State private var pickedDate = Date.now

    var body: some View {
        if let current = value {
            setRow(current)
        } else if !isEnabled {
            LabeledContent {
                Text("None")
            } label: {
                Label(title, systemImage: systemImage)
            }
            .accessibilityIdentifier(identifier)
        } else if quickPicks.isEmpty {
            addButton
        } else {
            quickPickRow
        }
    }

    // MARK: - Set

    private func setRow(_ current: Date) -> some View {
        HStack {
            DatePicker(
                selection: Binding(get: { current }, set: { value = $0 }),
                displayedComponents: kind == .time ? .hourAndMinute : .date
            ) {
                Label(title, systemImage: systemImage)
            }
            .accessibilityIdentifier(identifier)
            if isEnabled {
                Button {
                    value = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .imageScale(.large)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(Text("Remove \(Text(title))"))
                .accessibilityIdentifier(AccessibilityID.OptionalDate.clear(identifier))
            }
        }
    }

    // MARK: - Empty

    private var addButton: some View {
        Button(action: add) {
            Label(addTitle, systemImage: systemImage)
        }
        .accessibilityIdentifier(AccessibilityID.OptionalDate.add(identifier))
        .datePickerPopover(isPresented: $isPicking, date: $pickedDate, commit: commitPicked)
    }

    /// Wide enough: label and chips on one line. Large Dynamic Type:
    /// chips wrap under the label instead of squeezing it.
    private var quickPickRow: some View {
        ViewThatFits(in: .horizontal) {
            HStack {
                Label(title, systemImage: systemImage)
                Spacer(minLength: 8)
                quickPickButtons
            }
            VStack(alignment: .leading, spacing: 8) {
                Label(title, systemImage: systemImage)
                quickPickButtons
            }
        }
    }

    private var quickPickButtons: some View {
        HStack(spacing: 6) {
            ForEach(quickPicks) { pick in
                Button(pick.title) { value = pick.date }
                    .accessibilityIdentifier(AccessibilityID.OptionalDate.quick(identifier, pick.id))
            }
            Button(action: add) {
                Image(systemName: "calendar.badge.plus")
            }
            .accessibilityLabel(Text("Choose \(Text(title))"))
            .accessibilityIdentifier(AccessibilityID.OptionalDate.add(identifier))
            .datePickerPopover(isPresented: $isPicking, date: $pickedDate, commit: commitPicked)
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.capsule)
        .controlSize(.small)
    }

    private func add() {
        switch kind {
        case .time:
            value = suggestion()
        case .date:
            pickedDate = suggestion()
            isPicking = true
        }
    }

    private func commitPicked() {
        value = pickedDate
        isPicking = false
    }
}

private extension View {
    /// A calendar in a popover (a popover on iPhone too, not a sheet).
    /// Tapping a day commits it; "OK" commits the day already shown,
    /// which a tap cannot do because it changes nothing.
    func datePickerPopover(isPresented: Binding<Bool>, date: Binding<Date>, commit: @escaping () -> Void) -> some View {
        popover(isPresented: isPresented) {
            VStack(alignment: .trailing, spacing: 0) {
                Button("OK", action: commit)
                    .fontWeight(.semibold)
                    .padding([.top, .horizontal])
                DatePicker("", selection: date, displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .labelsHidden()
                    .padding([.horizontal, .bottom])
                    .onChange(of: date.wrappedValue) { _, _ in commit() }
            }
            .frame(minWidth: 320)
            .presentationCompactAdaptation(.popover)
        }
    }
}

#Preview("States") {
    @Previewable @State var empty: Date?
    @Previewable @State var day: Date? = .now
    @Previewable @State var noTime: Date?
    @Previewable @State var time: Date? = .now
    Form {
        Section("Schedule") {
            OptionalDateRow(
                title: "Date", addTitle: "Add date", systemImage: "calendar", value: $empty,
                quickPicks: [
                    .init(id: "today", title: "Today", date: .now),
                    .init(id: "tomorrow", title: "Tomorrow", date: Calendar.current.date(byAdding: .day, value: 1, to: .now)!),
                ],
                suggestion: { .now }, identifier: "preview.day"
            )
            OptionalDateRow(title: "Date", addTitle: "Add date", systemImage: "calendar", value: $day, suggestion: { .now }, identifier: "preview.day2")
            OptionalDateRow(title: "Start time", addTitle: "Add start time", systemImage: "clock", value: $noTime, kind: .time, suggestion: { .now }, identifier: "preview.start")
            OptionalDateRow(title: "End time", addTitle: "Add end time", systemImage: "clock.badge.checkmark", value: $time, kind: .time, suggestion: { .now }, identifier: "preview.end")
        }
        Section("Disabled") {
            OptionalDateRow(title: "Start date", addTitle: "Add start date", systemImage: "flag", value: .constant(nil), suggestion: { .now }, identifier: "preview.disabled")
                .disabled(true)
        }
    }
}

#Preview("Dark") {
    @Previewable @State var empty: Date?
    @Previewable @State var day: Date? = .now
    Form {
        OptionalDateRow(
            title: "Date", addTitle: "Add date", systemImage: "calendar", value: $empty,
            quickPicks: [.init(id: "today", title: "Today", date: .now), .init(id: "tomorrow", title: "Tomorrow", date: .now)],
            suggestion: { .now }, identifier: "preview.day"
        )
        OptionalDateRow(title: "Date", addTitle: "Add date", systemImage: "calendar", value: $day, suggestion: { .now }, identifier: "preview.day2")
    }
    .preferredColorScheme(.dark)
}
