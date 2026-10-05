import Foundation
import KadoCore

/// The words and the symbol for each highlight. The calculator picks
/// the facts; this only phrases them.
extension InsightsHighlight {
    /// One plain sentence, such as "Meditate: 23 days, your best
    /// streak ever".
    var sentence: String {
        switch self {
        case let .streakRecord(habitName, days):
            return String(localized: "\(habitName): \(days) days, your best streak ever", comment: "Insights highlight: a habit's current streak equals its best ever. The values are the habit name and the streak in days.")
        case let .consistencyChange(points):
            if points >= 0 {
                return String(localized: "Habits are up \(points) points", comment: "Insights highlight: habit consistency rose by this many percentage points against the previous period.")
            }
            return String(localized: "Habits are down \(-points) points", comment: "Insights highlight: habit consistency fell by this many percentage points against the previous period.")
        case let .mostUndoneCategory(category, undone, total):
            return String(localized: "\(category.localizedName) tasks are most often left undone (\(undone) of \(total))", comment: "Insights highlight: the category whose tasks were most often not done by their day. The values are the category name, then tasks left undone out of all its tasks.")
        case let .topFocusCategory(category, seconds):
            return String(localized: "Most focus went to \(category.localizedName): \(InsightsFormat.duration(seconds))", comment: "Insights highlight: the category with the most tracked session time. The values are the category name and a duration such as 6h 20m.")
        case let .perfectDays(count):
            return String(localized: "\(count) perfect days", comment: "Insights: days on which every due habit was done.")
        case let .peakFocusTime(part, share):
            let percent = InsightsFormat.percent(share)
            switch part {
            case .morning:
                return String(localized: "You focus most in the morning (\(percent))", comment: "Insights highlight: most session time starts in the morning. The value is that share, as a percent.")
            case .afternoon:
                return String(localized: "You focus most in the afternoon (\(percent))", comment: "Insights highlight: most session time starts in the afternoon. The value is that share, as a percent.")
            case .evening:
                return String(localized: "You focus most in the evening (\(percent))", comment: "Insights highlight: most session time starts in the evening. The value is that share, as a percent.")
            case .night:
                return String(localized: "You focus most at night (\(percent))", comment: "Insights highlight: most session time starts at night. The value is that share, as a percent.")
            }
        case let .bestWeekday(weekday, _):
            return String(localized: "\(weekday.localizedFull) is your most consistent day", comment: "Insights highlight: the weekday with the best habit consistency. The value is a weekday name.")
        case let .milestone(habitName, count):
            return String(localized: "\(habitName) reached \(count) times", comment: "Insights highlight: a habit passed a round number of days done in this period. The values are the habit name and that number.")
        case let .longestStreak(habitName, days):
            return String(localized: "\(habitName) is on a \(days)-day streak", comment: "Insights highlight: the longest current streak across habits. The values are the habit name and the streak in days.")
        case let .focusTotal(seconds):
            return String(localized: "\(InsightsFormat.duration(seconds)) of focus", comment: "Insights: total session time. The value is a duration such as 12h 40m.")
        }
    }

    /// The SF Symbol beside the sentence.
    var symbolName: String {
        switch self {
        case .streakRecord: "flame.fill"
        case let .consistencyChange(points):
            points >= 0 ? "chart.line.uptrend.xyaxis" : "chart.line.downtrend.xyaxis"
        case .mostUndoneCategory: "circle.dashed"
        case .topFocusCategory: "timer"
        case .perfectDays: "checkmark.seal.fill"
        case let .peakFocusTime(part, _): part.symbolName
        case .bestWeekday: "calendar"
        case .milestone: "flag.fill"
        case .longestStreak: "flame"
        case .focusTotal: "hourglass"
        }
    }
}

extension InsightsPartOfDay {
    /// Sunrise for the morning through the moon for the night.
    var symbolName: String {
        switch self {
        case .morning: "sunrise.fill"
        case .afternoon: "sun.max.fill"
        case .evening: "sunset.fill"
        case .night: "moon.stars.fill"
        }
    }

    /// "Morning", "Afternoon", "Evening", "Night".
    var localizedName: String {
        switch self {
        case .morning:
            String(localized: "Morning", comment: "Insights Rhythm: focus that started between 5:00 and 11:59.")
        case .afternoon:
            String(localized: "Afternoon", comment: "Insights Rhythm: focus that started between 12:00 and 16:59.")
        case .evening:
            String(localized: "Evening", comment: "Insights Rhythm: focus that started between 17:00 and 21:59.")
        case .night:
            String(localized: "Night", comment: "Insights Rhythm: focus that started between 22:00 and 4:59.")
        }
    }
}
