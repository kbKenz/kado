import SwiftUI
import KadoCore

/// A day's pinned header: "Today", "Yesterday", the weekday for the rest
/// of the last week, else the date; then what the day held, as small
/// counts on the right.
///
/// "Today" is the civil today, as tasks are civil days. A habit record
/// logged at 01:00 under a 04:00 day start is already stamped on the
/// day before, so it sits under that day's header either way.
struct HistoryDayHeader: View {
    let day: HistoryDay

    @Environment(\.calendar) private var calendar
    @Environment(\.civilToday) private var today

    var body: some View {
        // Large text: the counts move under the date.
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                titles
                Spacer(minLength: 8)
                counts
            }
            VStack(alignment: .leading, spacing: 4) {
                titles
                counts
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 6)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.kadoBackground)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(spokenSummary))
        .accessibilityAddTraits(.isHeader)
        .accessibilityIdentifier(AccessibilityID.History.day(Self.key(for: day.day, calendar: calendar)))
    }

    private var titles: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
                .font(.headline)
                .foregroundStyle(Color.kadoForeground)
            if let subtitle {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(Color.kadoForegroundSecondary)
            }
        }
    }

    private var counts: some View {
        HStack(spacing: 10) {
            if day.tasksDone > 0 {
                count(day.tasksDone, symbol: "checkmark.circle")
            }
            if day.habitsDone > 0 {
                count(day.habitsDone, symbol: "repeat")
            }
            if day.trackedSeconds >= 60 {
                Label(InsightsFormat.duration(day.trackedSeconds), systemImage: "timer")
            }
        }
        .labelStyle(CompactLabelStyle())
        .font(.caption.weight(.medium).monospacedDigit())
        .fixedSize()
        .foregroundStyle(Color.kadoForegroundSecondary)
    }

    private func count(_ value: Int, symbol: String) -> some View {
        Label(InsightsFormat.count(value), systemImage: symbol)
    }

    private var daysAgo: Int {
        calendar.dateComponents([.day], from: day.day, to: calendar.startOfDay(for: today)).day ?? 0
    }

    private var title: String {
        switch daysAgo {
        case 0: return String(localized: "Today")
        case 1: return String(localized: "Yesterday")
        case 2..<7: return day.day.formatted(.dateTime.weekday(.wide))
        default:
            let sameYear = calendar.isDate(day.day, equalTo: today, toGranularity: .year)
            return sameYear
                ? day.day.formatted(.dateTime.weekday(.abbreviated).day().month(.wide))
                : day.day.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).year())
        }
    }

    /// The date under a relative title.
    private var subtitle: String? {
        guard daysAgo >= 0, daysAgo < 7 else { return nil }
        return day.day.formatted(.dateTime.day().month(.wide))
    }

    private var spokenSummary: String {
        var parts = [title]
        if let subtitle { parts.append(subtitle) }
        if day.tasksDone > 0 {
            parts.append(String(localized: "\(day.tasksDone) tasks done", comment: "History day header, VoiceOver: tasks completed that day."))
        }
        if day.habitsDone > 0 {
            parts.append(String(localized: "\(day.habitsDone) habits logged", comment: "History day header, VoiceOver: habit records that day."))
        }
        if day.trackedSeconds >= 60 {
            parts.append(String(localized: "Focus time \(InsightsFormat.duration(day.trackedSeconds))", comment: "Insights Focus, VoiceOver: total session time in the period. The value is a duration."))
        }
        return parts.joined(separator: ", ")
    }

    /// `yyyy-MM-dd` in `calendar`, for the header's identifier.
    static func key(for day: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: day)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }
}

/// Icon and text close together, as in a stat line.
private struct CompactLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 3) {
            configuration.icon
            configuration.title
        }
    }
}

#Preview("Headers") {
    VStack(spacing: 0) {
        ForEach(HistoryPreviewData.days.prefix(4)) { day in
            HistoryDayHeader(day: day)
        }
    }
    .background(Color.kadoBackground)
}

#Preview("Dark, XXXL") {
    VStack(spacing: 0) {
        ForEach(HistoryPreviewData.days.prefix(3)) { day in
            HistoryDayHeader(day: day)
        }
    }
    .background(Color.kadoBackground)
    .preferredColorScheme(.dark)
    .dynamicTypeSize(.accessibility3)
}
