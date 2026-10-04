import KadoCore
import SwiftUI

struct GoalMeasurementSection: View {
    @Binding var measurement: GoalMeasurement
    let habits: [Habit]
    @Environment(\.locale) private var locale
    @State private var baselineText = "0"
    @State private var targetText = "1"

    private var eligible: [Habit] {
        habits.filter { switch $0.type { case .counter, .timer: true; default: false } }
    }
    var body: some View {
        Section {
            Toggle("Measure progress", isOn: $measurement.enabled)
                .accessibilityIdentifier("goal.measurement.enabled")
            if measurement.enabled {
                Picker("Progress source", selection: $measurement.mode) {
                    ForEach(GoalProgressMode.allCases, id: \.self) { Text($0.plannerTitle).tag($0) }
                }
                .accessibilityIdentifier("goal.measurement.mode")
                if measurement.mode == .habit {
                    Picker("Source habit", selection: $measurement.habitID) {
                        Text("Choose a habit").tag(Optional<UUID>.none)
                        ForEach(eligible) { Text($0.name).tag(Optional($0.id)) }
                        if let selected = measurement.habitID, !eligible.contains(where: { $0.id == selected }) {
                            Text("Source unavailable").tag(Optional(selected))
                        }
                    }
                    .accessibilityIdentifier("goal.measurement.habit")
                    Text("Link a counter or timer habit to this goal to use its recorded values.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Baseline").font(.footnote).foregroundStyle(.secondary)
                    TextField("Baseline", text: $baselineText)
                        .keyboardType(.decimalPad).accessibilityIdentifier("goal.measurement.baseline")
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Numeric target").font(.footnote).foregroundStyle(.secondary)
                    TextField("Numeric target", text: $targetText)
                        .keyboardType(.decimalPad).accessibilityIdentifier("goal.measurement.target")
                }
                if measurement.mode == .tasks {
                    LabeledContent("Unit", value: String(localized: "tasks"))
                } else if isTimer {
                    LabeledContent("Unit", value: String(localized: "minutes"))
                } else {
                    TextField("Unit (for example, pages)", text: $measurement.unit)
                        .accessibilityIdentifier("goal.measurement.unit")
                }
                if !measurement.isValid {
                    Text("Use a finite, nonnegative baseline and a target above it. Choose a unit and a habit source when needed.")
                        .font(.footnote).foregroundStyle(.red)
                }
            }
        } header: { Text("Progress measurement") }
        footer: {
            Text("Progress never completes a goal automatically. Changing the source recalculates totals; manual entries are retained.")
        }
        .listRowBackground(Color.kadoBackgroundSecondary)
        .onAppear {
            baselineText = measurement.baseline.formatted(.number.grouping(.never).locale(locale))
            targetText = measurement.target.formatted(.number.grouping(.never).locale(locale))
        }
        .onChange(of: baselineText) { _, value in measurement.baseline = GoalProgressNumber.parse(value, locale: locale) ?? .nan }
        .onChange(of: targetText) { _, value in measurement.target = GoalProgressNumber.parse(value, locale: locale) ?? .nan }
        .onChange(of: measurement.mode) { _, _ in normalizeUnit() }
        .onChange(of: measurement.habitID) { _, _ in normalizeUnit() }
    }
    private var isTimer: Bool {
        guard measurement.mode == .habit, let habit = eligible.first(where: { $0.id == measurement.habitID }) else { return false }
        if case .timer = habit.type { return true }; return false
    }
    private func normalizeUnit() {
        // Fixed-unit modes must not erase a custom manual/counter unit.
        if isTimer && measurement.unit.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { measurement.unit = "minutes" }
    }
}
