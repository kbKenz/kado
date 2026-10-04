import SwiftUI
import KadoCore

/// One day in Today's day strip: weekday letter, day number, and a ring
/// of that day's habit progress.
struct DayStripCell: View {
    let day: Date
    let isSelected: Bool
    let isToday: Bool
    let progress: DayProgress
    let onSelect: () -> Void

    @Environment(\.calendar) private var calendar
    @ScaledMetric(relativeTo: .caption2) private var ringSize: CGFloat = 14

    private var weekday: Weekday {
        Weekday(rawValue: calendar.component(.weekday, from: day)) ?? .monday
    }

    var body: some View {
        Button(action: onSelect) {
            VStack(spacing: 4) {
                Text(weekday.localizedShort)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(isSelected ? Color.kadoBackground : Color.kadoForegroundSecondary)
                Text(day, format: .dateTime.day())
                    .font(.callout.weight(.semibold).monospacedDigit())
                    .foregroundStyle(numberColor)
                ring
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 6)
            .frame(minWidth: 44)
            .background {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isSelected ? Color.kadoAccent : Color.clear)
            }
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(day, format: .dateTime.weekday(.wide).month(.wide).day()))
        .accessibilityValue(accessibilityValue)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier(AccessibilityID.Today.dayStripCell(day))
    }

    private var numberColor: Color {
        if isSelected { return Color.kadoBackground }
        return isToday ? Color.kadoAccent : Color.kadoForeground
    }

    @ViewBuilder
    private var ring: some View {
        let tint = isSelected ? Color.kadoBackground : Color.kadoAccent
        if progress.total == 0 {
            Circle().fill(tint.opacity(0.4)).frame(width: ringSize * 0.3, height: ringSize * 0.3).frame(width: ringSize, height: ringSize)
        } else {
            ZStack {
                Circle().stroke(tint.opacity(0.25), lineWidth: 2.5)
                Circle().trim(from: 0, to: progress.fraction)
                    .stroke(tint, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            .frame(width: ringSize, height: ringSize)
        }
    }

    private var accessibilityValue: String {
        progress.total == 0
            ? String(localized: "Nothing due")
            : String(localized: "\(progress.completed) of \(progress.total) habits done")
    }
}

#Preview {
    HStack {
        DayStripCell(day: .now, isSelected: true, isToday: true, progress: .init(completed: 2, total: 3)) {}
        DayStripCell(day: .now.addingTimeInterval(-86_400), isSelected: false, isToday: false, progress: .init(completed: 3, total: 3)) {}
        DayStripCell(day: .now.addingTimeInterval(86_400), isSelected: false, isToday: false, progress: .empty) {}
    }
    .padding()
}

#Preview("Dark") {
    HStack {
        DayStripCell(day: .now, isSelected: false, isToday: true, progress: .init(completed: 1, total: 4)) {}
        DayStripCell(day: .now, isSelected: true, isToday: false, progress: .init(completed: 4, total: 4)) {}
    }
    .padding()
    .preferredColorScheme(.dark)
}
