import SwiftUI
import KadoCore

/// The cards of the Insights feed, in feed order. The raw value is the
/// card's name in `AccessibilityID.Insights.card(_:)`.
enum InsightsCardKind: String, CaseIterable, Identifiable {
    case pulse
    case highlights
    case activity
    case focus
    case categories
    case sleep
    case movement
    case habits
    case tasks
    case goals
    case rhythm
    case allTime

    var id: String { rawValue }

    /// The cards a report has something for, in feed order. None for an
    /// empty report: the feed shows its first-run state instead.
    static func visible(in report: InsightsReport) -> [InsightsCardKind] {
        guard !report.isEmpty else { return [] }
        return allCases.filter { $0.hasContent(in: report) }
    }

    /// Whether the card has anything to say. Focus, Sleep and Movement
    /// always do: with no data they explain how to get some.
    func hasContent(in report: InsightsReport) -> Bool {
        switch self {
        case .pulse:
            let pulse = report.pulse
            return [pulse.consistency, pulse.followThrough, pulse.activeDays].contains { $0.total > 0 }
        case .highlights:
            return !report.highlights.isEmpty
        case .activity:
            return report.activity.days.contains { $0.isInPeriod && $0.habitFraction != nil }
        case .focus, .sleep, .movement:
            return true
        case .categories:
            return !report.categories.isEmpty
        case .habits:
            return !report.habits.isEmpty
        case .tasks:
            let tasks = report.tasks
            return tasks.done + tasks.undone + tasks.overdueOpen > 0
        case .goals:
            return !report.goals.isEmpty
        case .rhythm:
            let rhythm = report.rhythm
            return rhythm.weekdays.contains { $0.rate.total > 0 }
                || rhythm.focusByPartOfDay.contains { $0.seconds > 0 }
        case .allTime:
            return report.allTime.firstDay != nil
        }
    }

    /// The card's title.
    var title: LocalizedStringKey {
        switch self {
        case .pulse: "Pulse"
        case .highlights: "Highlights"
        case .activity: "Activity"
        case .focus: "Focus"
        case .categories: "Categories"
        case .sleep: "Sleep"
        case .movement: "Movement"
        case .habits: "Habits"
        case .tasks: "Tasks"
        case .goals: "Goals"
        case .rhythm: "Rhythm"
        case .allTime: "All time"
        }
    }

    /// The SF Symbol beside the title.
    var symbolName: String {
        switch self {
        case .pulse: "waveform.path.ecg"
        case .highlights: "sparkles"
        case .activity: "square.grid.3x3.fill"
        case .focus: "timer"
        case .categories: "tag.fill"
        case .sleep: "bed.double.fill"
        case .movement: "figure.walk"
        case .habits: "checkmark.circle.fill"
        case .tasks: "checklist"
        case .goals: "scope"
        case .rhythm: "metronome.fill"
        case .allTime: "infinity"
        }
    }
}
