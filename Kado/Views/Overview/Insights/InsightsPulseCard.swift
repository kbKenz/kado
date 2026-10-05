import SwiftUI
import KadoCore

/// Three rings at the top of the feed: habit consistency, task
/// follow-through and active days, each with its change against the
/// previous period.
struct InsightsPulseCard: View {
    let pulse: InsightsPulse

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        InsightsCard(kind: .pulse) {
            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 16) { rings }
                } else {
                    HStack(alignment: .top, spacing: 8) { rings }
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(summary))
        }
    }

    @ViewBuilder
    private var rings: some View {
        ForEach(Dial.allCases) { dial in
            InsightsPulseRing(
                label: dial.label,
                rate: dial.rate(in: pulse),
                change: InsightsFormat.pointChange(dial.rate(in: pulse), from: dial.previousRate(in: pulse)),
                isCompact: !dynamicTypeSize.isAccessibilitySize
            )
        }
    }

    /// "Habit consistency 82%. Up 6 points. Task follow-through …"
    private var summary: String {
        Dial.allCases.map { dial in
            let rate = dial.rate(in: pulse)
            guard let percent = InsightsFormat.percent(rate) else {
                return dial.spokenNoData
            }
            let change = InsightsFormat.pointChange(rate, from: dial.previousRate(in: pulse))
            return "\(dial.spoken(percent)). \(change.spokenText)."
        }
        .joined(separator: " ")
    }

    /// One of the three rings.
    enum Dial: CaseIterable, Identifiable {
        case habits, tasks, activeDays

        var id: Self { self }

        var label: LocalizedStringKey {
            switch self {
            case .habits: "Habits"
            case .tasks: "Tasks"
            case .activeDays: "Active days"
            }
        }

        func rate(in pulse: InsightsPulse) -> InsightsRate {
            switch self {
            case .habits: pulse.consistency
            case .tasks: pulse.followThrough
            case .activeDays: pulse.activeDays
            }
        }

        func previousRate(in pulse: InsightsPulse) -> InsightsRate {
            switch self {
            case .habits: pulse.previousConsistency
            case .tasks: pulse.previousFollowThrough
            case .activeDays: pulse.previousActiveDays
            }
        }

        func spoken(_ percent: String) -> String {
            switch self {
            case .habits:
                String(localized: "Habit consistency \(percent)", comment: "Insights Pulse, VoiceOver: share of due habit-days done. The value is a percent.")
            case .tasks:
                String(localized: "Task follow-through \(percent)", comment: "Insights Pulse, VoiceOver: share of planned tasks done. The value is a percent.")
            case .activeDays:
                String(localized: "Active days \(percent)", comment: "Insights Pulse, VoiceOver: share of days with any activity. The value is a percent.")
            }
        }

        var spokenNoData: String {
            switch self {
            case .habits:
                String(localized: "Habit consistency: no data yet.", comment: "Insights Pulse, VoiceOver: no habit was due in this period yet.")
            case .tasks:
                String(localized: "Task follow-through: no data yet.", comment: "Insights Pulse, VoiceOver: no task was done or left undone in this period yet.")
            case .activeDays:
                String(localized: "Active days: no data yet.", comment: "Insights Pulse, VoiceOver: no day counts in this period yet.")
            }
        }
    }
}

/// One ring: the rate as a filled arc with the percent inside, its
/// name, and how it moved.
private struct InsightsPulseRing: View {
    let label: LocalizedStringKey
    let rate: InsightsRate
    let change: InsightsFormat.PointChange
    /// Column layout (ring above the text). Off at accessibility sizes,
    /// where each ring takes a row with its text beside it.
    let isCompact: Bool

    @ScaledMetric(relativeTo: .title3) private var ringSize: CGFloat = 72
    @ScaledMetric(relativeTo: .title3) private var lineWidth: CGFloat = 7

    var body: some View {
        if isCompact {
            VStack(spacing: 8) {
                ring
                texts(alignment: .center)
            }
            .frame(maxWidth: .infinity)
        } else {
            HStack(spacing: 16) {
                ring
                texts(alignment: .leading)
                Spacer(minLength: 0)
            }
        }
    }

    private var ring: some View {
        ZStack {
            Circle()
                .stroke(Color.kadoHairline, lineWidth: lineWidth)
            if let fraction = rate.fraction {
                Circle()
                    .trim(from: 0, to: max(0.001, min(1, fraction)))
                    .stroke(Color.kadoAccent, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            Text(InsightsFormat.percent(rate) ?? "—")
                .font(.headline)
                .monospacedDigit()
                .foregroundStyle(Color.kadoForeground)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .padding(lineWidth + 4)
        }
        .frame(width: min(ringSize, 120), height: min(ringSize, 120))
    }

    private func texts(alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 4) {
            Text(label)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Color.kadoForeground)
            InsightsChangeLabel(change)
                .multilineTextAlignment(alignment == .center ? .center : .leading)
        }
    }
}

#Preview("Pulse") {
    InsightsPulseCard(pulse: InsightsPreviewData.rich.pulse)
        .padding()
        .background(Color.kadoBackground)
}

#Preview("Dark") {
    VStack(spacing: 16) {
        InsightsPulseCard(pulse: InsightsPreviewData.rich.pulse)
        InsightsPulseCard(pulse: InsightsPreviewData.sparse.pulse)
    }
    .padding()
    .background(Color.kadoBackground)
    .preferredColorScheme(.dark)
}

#Preview("XXXL") {
    InsightsPulseCard(pulse: InsightsPreviewData.rich.pulse)
        .padding()
        .background(Color.kadoBackground)
        .dynamicTypeSize(.accessibility3)
}
