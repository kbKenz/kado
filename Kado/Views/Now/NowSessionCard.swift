import SwiftUI
import KadoCore

/// The running session: the item's time today, its runs so far, and
/// the buttons to pause it or mark it done.
struct NowSessionCard: View {
    let open: OpenSession
    let plannedRange: ClosedRange<Date>?
    /// The item's time today before this run, and its earlier runs.
    let progress: NowProgress
    let now: Date
    /// The task's category icon or the habit's own icon, before the title.
    var glyph: ItemGlyph? = nil
    let onTitle: () -> Void
    let onPause: () -> Void
    /// Nil hides Done: a timer habit is done when its time is reached.
    let onDone: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("NOW")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.kadoForegroundSecondary)
                .accessibilityHidden(true)
            NowCardTitle(title: open.item.title, glyph: glyph, action: onTitle)
            details
            buttons
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color.kadoBackgroundSecondary, in: RoundedRectangle(cornerRadius: KadoRadius.card))
    }

    /// Worked time today at `now`: earlier runs plus this one.
    private var workedToday: TimeInterval {
        progress.countedSeconds + open.session.elapsed(at: now)
    }

    /// Everything but the buttons reads as one VoiceOver element.
    private var details: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let plannedRange {
                Text(plannedRange.nowTimeText)
                    .foregroundStyle(Color.kadoForegroundSecondary)
            }
            Text("Started \(open.session.startedAt, format: .dateTime.hour().minute())")
                .foregroundStyle(Color.kadoForegroundSecondary)
            elapsedText
                .font(.title2.monospacedDigit())
                .foregroundStyle(Color.kadoForeground)
            if !progress.runs.isEmpty {
                Text("Earlier today: \(NowRunsText.text(progress.runs))")
                    .font(.footnote)
                    .foregroundStyle(Color.kadoForegroundSecondary)
            }
            if let budget { self.progress(budget) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(AccessibilityID.Now.elapsed)
    }

    /// Counts every second without our own timer. Shifting the start
    /// back by the time already counted today (and forward by a legacy
    /// session's finished pauses) leaves exactly the worked time.
    private var elapsedText: some View {
        let origin = open.session.startedAt
            .addingTimeInterval(open.session.pausedSeconds - progress.countedSeconds)
        return HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(timerInterval: origin...Date.distantFuture, countsDown: false)
            Group {
                if progress.countedSeconds > 0 { Text("today") } else { Text("elapsed") }
            }
            .font(.body)
            .foregroundStyle(Color.kadoForegroundSecondary)
        }
    }

    /// What the worked time is measured against: a timer habit's daily
    /// target, else the planned block's length.
    private var budget: TimeInterval? {
        if let target = progress.targetSeconds, target > 0 { return target }
        guard let plannedRange else { return nil }
        let planned = plannedRange.upperBound.timeIntervalSince(plannedRange.lowerBound)
        return planned > 0 ? planned : nil
    }

    private func progress(_ budget: TimeInterval) -> some View {
        let worked = workedToday
        let remaining = budget - worked
        return VStack(alignment: .leading, spacing: 4) {
            ProgressView(value: min(worked, budget), total: budget)
                .tint(Color.kadoAccent)
            Group {
                if remaining > 0 {
                    Text("\(NowDurationText.text(ceil(remaining / 60) * 60)) left")
                } else {
                    Text("\(NowDurationText.text(floor(-remaining / 60) * 60)) over")
                }
            }
            .font(.footnote)
            .foregroundStyle(Color.kadoForegroundSecondary)
        }
    }

    private var buttons: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) { pauseButton; doneButton }
            VStack(alignment: .leading, spacing: 12) { pauseButton; doneButton }
        }
    }

    private var pauseButton: some View {
        Button(action: onPause) {
            Label("Pause", systemImage: "pause.fill")
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .accessibilityIdentifier(AccessibilityID.Now.pause)
    }

    @ViewBuilder
    private var doneButton: some View {
        if let onDone {
            Button(action: onDone) {
                Label("Done", systemImage: "checkmark")
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .accessibilityIdentifier(AccessibilityID.Now.done)
        }
    }
}

/// "1 hr, 20 min" in the user's locale, to the minute ("0 min" under one).
enum NowDurationText {
    static func text(_ seconds: TimeInterval) -> String {
        let minutes = max(0, Int(seconds / 60))
        return Duration.seconds(minutes * 60).formatted(.units(allowed: [.hours, .minutes], width: .abbreviated))
    }
}

/// "10:02 – 12:01 PM, 2:05 – 2:30 PM": the runs of a day, the last
/// three when there are more.
enum NowRunsText {
    static let shown = 3

    static func text(_ runs: [DateInterval]) -> String {
        let parts = runs.suffix(shown).map { ($0.start...$0.end).nowTimeText }
        let list = parts.formatted(.list(type: .and, width: .narrow))
        guard runs.count > shown else { return list }
        return String(localized: "\(list) and \(runs.count - shown) more")
    }
}

extension ClosedRange where Bound == Date {
    /// "9:00 – 10:00 AM" in the user's locale; just the start when the range is empty.
    var nowTimeText: String {
        guard lowerBound < upperBound else {
            return lowerBound.formatted(date: .omitted, time: .shortened)
        }
        return (lowerBound..<upperBound).formatted(.interval.hour().minute())
    }
}

#Preview("Running") {
    let start = Date.now.addingTimeInterval(-48 * 60)
    NowSessionCard(
        open: OpenSession(id: UUID(), item: .task(id: UUID(), title: "Research"), session: WorkSession(startedAt: start), blockID: nil),
        plannedRange: start.addingTimeInterval(-17 * 60)...start.addingTimeInterval(103 * 60),
        progress: NowProgress(item: .task(id: UUID(), title: "Research"), runs: [], countedSeconds: 0),
        now: .now, glyph: ItemGlyph(category: .study), onTitle: {}, onPause: {}, onDone: {}
    )
    .padding()
    .background(Color.kadoBackground)
}

#Preview("Continued, timer habit, Dark") {
    let start = Date.now.addingTimeInterval(-25 * 60)
    let morning = Calendar.current.startOfDay(for: .now).addingTimeInterval(9 * 3600)
    NowSessionCard(
        open: OpenSession(id: UUID(), item: .habit(id: UUID(), name: "IELTS prep"), session: WorkSession(startedAt: start), blockID: nil),
        plannedRange: nil,
        progress: NowProgress(
            item: .habit(id: UUID(), name: "IELTS prep"),
            runs: [DateInterval(start: morning, duration: 7200), DateInterval(start: morning.addingTimeInterval(10_800), duration: 1800)],
            countedSeconds: 9000, targetSeconds: 14_400, canMarkDone: false
        ),
        now: .now, glyph: ItemGlyph(habitIcon: "book.fill", color: .purple),
        onTitle: {}, onPause: {}, onDone: nil
    )
    .padding()
    .background(Color.kadoBackground)
    .preferredColorScheme(.dark)
}

#Preview("Running, over time") {
    let start = Date.now.addingTimeInterval(-90 * 60)
    NowSessionCard(
        open: OpenSession(id: UUID(), item: .task(id: UUID(), title: "Write the quarterly report"), session: WorkSession(startedAt: start), blockID: nil),
        plannedRange: start...start.addingTimeInterval(60 * 60),
        progress: NowProgress(item: .task(id: UUID(), title: "Write the quarterly report"), runs: [], countedSeconds: 0),
        now: .now, onTitle: {}, onPause: {}, onDone: {}
    )
    .padding()
    .background(Color.kadoBackground)
}

#Preview("Running, XXXL") {
    let start = Date.now.addingTimeInterval(-48 * 60)
    NowSessionCard(
        open: OpenSession(id: UUID(), item: .task(id: UUID(), title: "Research"), session: WorkSession(startedAt: start), blockID: nil),
        plannedRange: start.addingTimeInterval(-17 * 60)...start.addingTimeInterval(103 * 60),
        progress: NowProgress(item: .task(id: UUID(), title: "Research"), runs: [], countedSeconds: 0),
        now: .now, glyph: ItemGlyph(category: .study), onTitle: {}, onPause: {}, onDone: {}
    )
    .padding()
    .background(Color.kadoBackground)
    .dynamicTypeSize(.accessibility3)
}
