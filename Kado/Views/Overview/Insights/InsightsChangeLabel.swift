import SwiftUI
import KadoCore

/// How a figure moved against the previous period: an arrow and a
/// short text. Up uses the accent; down and no change stay neutral, so
/// a lower number never reads as a warning.
struct InsightsChangeLabel: View {
    private let direction: Direction
    private let text: String

    private enum Direction {
        case up, down, none
    }

    init(_ change: InsightsFormat.PointChange) {
        switch change {
        case .up(let points):
            direction = .up
            text = String(localized: "\(points) pts", comment: "Insights: a rate went up or down by this many percentage points, after an arrow. pts is short for points.")
        case .down(let points):
            direction = .down
            text = String(localized: "\(points) pts", comment: "Insights: a rate went up or down by this many percentage points, after an arrow. pts is short for points.")
        case .same, .noEarlierData, .noData:
            direction = .none
            text = change.spokenText
        }
    }

    init(_ change: InsightsFormat.DurationChange) {
        switch change {
        case .more:
            direction = .up
        case .less:
            direction = .down
        case .same:
            direction = .none
        }
        text = change.spokenText
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            if let arrow {
                Image(systemName: arrow)
                    .imageScale(.small)
                    .accessibilityHidden(true)
            }
            Text(text)
                .monospacedDigit()
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.caption.weight(.medium))
        .foregroundStyle(direction == .up ? Color.kadoAccent : Color.kadoForegroundSecondary)
    }

    private var arrow: String? {
        switch direction {
        case .up: "arrowtriangle.up.fill"
        case .down: "arrowtriangle.down.fill"
        case .none: nil
        }
    }
}

extension InsightsFormat.PointChange {
    /// The change as VoiceOver says it: "Up 6 points".
    var spokenText: String {
        switch self {
        case .up(let points):
            String(localized: "Up \(points) points", comment: "Insights, VoiceOver: a rate rose by this many percentage points against the previous period.")
        case .down(let points):
            String(localized: "Down \(points) points", comment: "Insights, VoiceOver: a rate fell by this many percentage points against the previous period.")
        case .same:
            String(localized: "Same as before", comment: "Insights: a figure did not change against the previous period.")
        case .noEarlierData:
            String(localized: "No earlier data", comment: "Insights: the previous period has nothing to compare with.")
        case .noData:
            String(localized: "No data yet", comment: "Insights: a figure has nothing to count in this period yet.")
        }
    }
}

extension InsightsFormat.DurationChange {
    /// "2h 10m more than before".
    var spokenText: String {
        switch self {
        case .more(let seconds):
            String(localized: "\(InsightsFormat.duration(seconds)) more than before", comment: "Insights: a total time rose against the previous period. The value is a duration such as 2h 10m.")
        case .less(let seconds):
            String(localized: "\(InsightsFormat.duration(seconds)) less than before", comment: "Insights: a total time fell against the previous period. The value is a duration such as 2h 10m.")
        case .same:
            String(localized: "Same as before", comment: "Insights: a figure did not change against the previous period.")
        }
    }
}

#Preview("Changes") {
    VStack(alignment: .leading, spacing: 8) {
        InsightsChangeLabel(InsightsFormat.PointChange.up(6))
        InsightsChangeLabel(InsightsFormat.PointChange.down(3))
        InsightsChangeLabel(InsightsFormat.PointChange.same)
        InsightsChangeLabel(InsightsFormat.PointChange.noEarlierData)
        InsightsChangeLabel(InsightsFormat.DurationChange.more(7_800))
    }
    .padding()
    .background(Color.kadoBackgroundSecondary)
}

#Preview("Dark") {
    VStack(alignment: .leading, spacing: 8) {
        InsightsChangeLabel(InsightsFormat.PointChange.up(12))
        InsightsChangeLabel(InsightsFormat.PointChange.noData)
        InsightsChangeLabel(InsightsFormat.DurationChange.less(1_800))
    }
    .padding()
    .background(Color.kadoBackgroundSecondary)
    .preferredColorScheme(.dark)
}
