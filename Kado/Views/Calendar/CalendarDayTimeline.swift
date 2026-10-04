import KadoCore
import SwiftUI

/// Planned time sits on a civil-day grid. Overlapping blocks occupy
/// separate columns; cross-midnight events are clipped to this day.
/// The visual height of a start-only block never becomes an end time
/// in persistence.
struct CalendarDayTimeline: View {
    let day: Date
    let blocks: [CalendarBlockItem]
    let onToggle: (CalendarBlockItem) -> Void
    let onEdit: (CalendarBlockItem) -> Void
    let onDelete: (CalendarBlockItem) -> Void

    @Environment(\.calendar) private var calendar
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private let pointsPerMinute: CGFloat = 1.1
    private let labelWidth: CGFloat = 64

    var body: some View {
        if dynamicTypeSize.isAccessibilitySize || maximumOverlappingColumns > 3 {
            accessibleAgenda
        } else {
            timeline
        }
    }

    private var dayInterval: DateInterval {
        calendar.dateInterval(of: .day, for: day)!
    }

    private var maximumOverlappingColumns: Int {
        placements(in: dayInterval).map(\.laneCount).max() ?? 1
    }

    private var timeline: some View {
        let interval = dayInterval
        let layout = placements(in: interval)
        let height = CGFloat(interval.duration / 60) * pointsPerMinute
        return GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                hourGrid(in: interval, width: geometry.size.width)
                ForEach(layout) { placement in
                    let lanes = max(1, placement.laneCount)
                    let available = max(80, geometry.size.width - labelWidth - 8)
                    let laneWidth = available / CGFloat(lanes)
                    timelineCard(placement.block)
                        .frame(width: max(44, laneWidth - 6), height: placement.height, alignment: .topLeading)
                        .offset(x: labelWidth + CGFloat(placement.lane) * laneWidth, y: placement.y)
                }
            }
            .frame(height: height)
        }
        .frame(height: height)
    }

    private func hourGrid(in interval: DateInterval, width: CGFloat) -> some View {
        let hours = hourMarks(in: interval)
        return VStack(alignment: .leading, spacing: 0) {
            ForEach(hours, id: \.self) { hour in
                HStack(alignment: .top, spacing: 8) {
                    Text(hour.formatted(date: .omitted, time: .shortened))
                        .font(.caption.monospacedDigit())
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .foregroundStyle(Color.kadoForegroundSecondary)
                        .frame(width: labelWidth - 8, alignment: .trailing)
                    Rectangle()
                        .fill(Color.kadoHairline)
                        .frame(height: 1)
                }
                .frame(width: width, height: CGFloat(min(60, interval.end.timeIntervalSince(hour) / 60)) * pointsPerMinute, alignment: .topLeading)
                // A Date stays unique when an hour repeats at DST's
                // autumn transition; an hour-of-day integer does not.
                .id(hour)
                .accessibilityHidden(true)
            }
        }
    }

    private func timelineCard(_ block: CalendarBlockItem) -> some View {
        Button { onEdit(block) } label: {
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .top, spacing: 4) {
                    Text(block.title)
                        .font(.caption.weight(.semibold))
                        .strikethrough(block.isComplete)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if block.isComplete {
                        Image(systemName: "checkmark.circle.fill")
                            .accessibilityHidden(true)
                    }
                }
                Text(block.schedule.timeLabel)
                    .font(.caption2)
                    .lineLimit(2)
                if continuesAcrossDays(block) {
                    Text("Continues across days")
                        .font(.caption2)
                        .lineLimit(1)
                } else if block.task?.isFromGoogle == true {
                    Text("Google Calendar")
                        .font(.caption2)
                        .lineLimit(1)
                }
            }
            .foregroundStyle(block.isComplete ? Color.kadoForegroundSecondary : Color.kadoForeground)
            .padding(8)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(block.isComplete ? Color.kadoBackgroundSecondary : Color.kadoAccentTint, in: RoundedRectangle(cornerRadius: KadoRadius.sm))
            .overlay(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(block.isComplete ? Color.kadoForegroundTertiary : Color.kadoAccent)
                    .frame(width: 3)
            }
            .clipShape(RoundedRectangle(cornerRadius: KadoRadius.sm))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(block.title)
        .accessibilityValue(Text("\(block.schedule.timeLabel), \(block.isComplete ? String(localized: "Complete") : String(localized: "Incomplete"))"))
        .accessibilityHint("Open task. Long-press for completion and other actions.")
        .accessibilityIdentifier(AccessibilityID.Calendar.block(block.id))
        .contextMenu {
            if block.task != nil {
                Button { onToggle(block) } label: {
                    Label(block.isComplete ? String(localized: "Mark incomplete") : String(localized: "Complete task"), systemImage: "checkmark.circle")
                }
                .accessibilityIdentifier(AccessibilityID.Calendar.completeMenuItem)
            }
            Button { onEdit(block) } label: {
                Label(block.task?.isFromGoogle == true ? String(localized: "View event") : String(localized: "Edit task"), systemImage: "pencil")
            }
            if block.task != nil {
                Button(role: .destructive) { onDelete(block) } label: {
                    Label(block.task?.isFromGoogle == true ? String(localized: "Remove from planner") : String(localized: "Delete task"), systemImage: "trash")
                }
            }
        }
        .accessibilityAction(named: block.isComplete ? Text("Mark incomplete") : Text("Complete task")) {
            if block.task != nil { onToggle(block) }
        }
    }

    /// No clipped text or overlapping controls when larger type is
    /// needed: the same chronological events expand as regular rows.
    private var accessibleAgenda: some View {
        LazyVStack(alignment: .leading, spacing: 12) {
            ForEach(blocks.sorted { ($0.schedule.startAt ?? $0.schedule.plannedDay) < ($1.schedule.startAt ?? $1.schedule.plannedDay) }) { block in
                if let task = block.task {
                    TaskRowView(item: task, schedule: block.schedule, showsDate: false,
                        onToggle: { onToggle(block) }, onEdit: { onEdit(block) }, onDelete: { onDelete(block) })
                        .padding(12)
                        .background(Color.kadoBackgroundSecondary, in: RoundedRectangle(cornerRadius: KadoRadius.card))
                } else {
                    Button { onEdit(block) } label: {
                        VStack(alignment: .leading) {
                            Text(block.title)
                            Text(block.schedule.timeLabel).font(.caption)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                    }
                }
            }
        }
    }

    private func continuesAcrossDays(_ block: CalendarBlockItem) -> Bool {
        guard let start = block.schedule.startAt, let end = block.schedule.endAt else { return false }
        let interval = dayInterval
        return start < interval.start || end > interval.end
    }

    private func hourMarks(in interval: DateInterval) -> [Date] {
        var marks: [Date] = []
        var cursor = interval.start
        while cursor < interval.end {
            marks.append(cursor)
            guard let next = calendar.date(byAdding: .hour, value: 1, to: cursor), next > cursor else { break }
            cursor = next
        }
        return marks
    }

    private struct Placement: Identifiable {
        let block: CalendarBlockItem
        let start: Date
        let end: Date
        var lane: Int
        var laneCount: Int
        let y: CGFloat
        let height: CGFloat
        var id: UUID { block.id }
    }

    private func placements(in interval: DateInterval) -> [Placement] {
        var placements: [Placement] = []
        let sorted = blocks.sorted { ($0.schedule.startAt ?? interval.start) < ($1.schedule.startAt ?? interval.start) }
        var laneEnds: [Date] = []
        for block in sorted {
            guard let originalStart = block.schedule.startAt else { continue }
            let start = max(originalStart, interval.start)
            guard start < interval.end else { continue }
            let defaultEnd = calendar.date(byAdding: .minute, value: 60, to: start) ?? interval.end
            let end = min(block.schedule.endAt ?? defaultEnd, interval.end)
            // Very short appointments retain a tap target and their
            // name; the label continues to show the real time bounds.
            let y = CGFloat(start.timeIntervalSince(interval.start) / 60) * pointsPerMinute
            let height = min(max(54, CGFloat(max(0, end.timeIntervalSince(start)) / 60) * pointsPerMinute), max(44, CGFloat(interval.duration / 60) * pointsPerMinute - y))
            let visualEnd = min(start.addingTimeInterval(TimeInterval(height / pointsPerMinute) * 60), interval.end)
            let lane = laneEnds.firstIndex(where: { $0 <= start }) ?? laneEnds.count
            if lane == laneEnds.count { laneEnds.append(visualEnd) } else { laneEnds[lane] = visualEnd }
            placements.append(Placement(block: block, start: start, end: visualEnd, lane: lane, laneCount: 1, y: y, height: height))
        }
        // Widths adapt independently for each group of overlapping
        // events, so a busy morning does not narrow the whole day.
        var groupStart = 0
        while groupStart < placements.count {
            var groupEnd = groupStart + 1
            var latestEnd = placements[groupStart].end
            while groupEnd < placements.count && placements[groupEnd].start < latestEnd {
                latestEnd = max(latestEnd, placements[groupEnd].end)
                groupEnd += 1
            }
            let count = (placements[groupStart..<groupEnd].map(\.lane).max() ?? 0) + 1
            for index in groupStart..<groupEnd { placements[index].laneCount = count }
            groupStart = groupEnd
        }
        return placements
    }
}

private enum CalendarTimelinePreview {
    static let calendar = Calendar.current
    static let day = calendar.startOfDay(for: .now)
    static let start = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: day)!
    static let end = calendar.date(bySettingHour: 10, minute: 30, second: 0, of: day)!
    static let meetingSchedule = TaskScheduleItem(plannedDay: day, startAt: start, endAt: end)
    static let meeting = TaskListItem(title: "Meeting with Thomas", dueDate: day, isFromGoogle: true, schedules: [meetingSchedule])
    static let readingSchedule = TaskScheduleItem(plannedDay: day, startAt: calendar.date(byAdding: .minute, value: 30, to: start)!, endAt: end)
    static let reading = TaskListItem(title: "Read a chapter", dueDate: day, completedAt: .now, schedules: [readingSchedule])
    static let blocks = [
        CalendarBlockItem(id: meetingSchedule.id, title: meeting.title, schedule: meetingSchedule, task: meeting),
        CalendarBlockItem(id: readingSchedule.id, title: reading.title, schedule: readingSchedule, task: reading, isComplete: true)
    ]
}

#Preview("Overlapping tasks") {
    ScrollViewReader { proxy in
        ScrollView {
            CalendarDayTimeline(day: CalendarTimelinePreview.day, blocks: CalendarTimelinePreview.blocks,
                onToggle: { _ in }, onEdit: { _ in }, onDelete: { _ in })
                .padding()
        }
        .onAppear { proxy.scrollTo(CalendarTimelinePreview.start, anchor: .top) }
    }
    .background(Color.kadoBackground)
    .kadoTheme()
}

#Preview("Dark") {
    ScrollViewReader { proxy in
        ScrollView {
            CalendarDayTimeline(day: CalendarTimelinePreview.day, blocks: CalendarTimelinePreview.blocks,
                onToggle: { _ in }, onEdit: { _ in }, onDelete: { _ in })
                .padding()
        }
        .onAppear { proxy.scrollTo(CalendarTimelinePreview.start, anchor: .top) }
    }
    .background(Color.kadoBackground)
    .kadoTheme()
    .preferredColorScheme(.dark)
}
