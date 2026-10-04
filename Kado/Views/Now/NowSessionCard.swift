import SwiftUI
import KadoCore

/// The running or paused session.
struct NowSessionCard: View {
    let open: OpenSession
    let plannedRange: ClosedRange<Date>?
    let now: Date
    let onTitle: () -> Void
    let onPause: () -> Void
    let onResume: () -> Void
    let onFinish: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("NOW")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.kadoForegroundSecondary)
                .accessibilityHidden(true)
            Button(action: onTitle) {
                Text(open.item.title)
                    .font(.largeTitle.bold())
                    .foregroundStyle(Color.kadoForeground)
                    .multilineTextAlignment(.leading)
            }
            .buttonStyle(.plain)
            .accessibilityHint(Text("Opens details"))
            .accessibilityIdentifier(AccessibilityID.Now.title)
            details
            buttons
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color.kadoBackgroundSecondary, in: RoundedRectangle(cornerRadius: KadoRadius.card))
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
            if let plannedRange { progress(plannedRange) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(AccessibilityID.Now.elapsed)
    }

    @ViewBuilder
    private var elapsedText: some View {
        if open.session.isPaused {
            let minutes = Int(open.session.elapsed(at: now) / 60)
            Text("Paused · \(minutes) min so far")
        } else {
            // Counts every second without our own timer. Shifting the start
            // by the finished pauses leaves exactly the worked time; no
            // pause is open while running.
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(timerInterval: open.session.startedAt.addingTimeInterval(open.session.pausedSeconds)...Date.distantFuture,
                     countsDown: false)
                Text("elapsed")
                    .font(.body)
                    .foregroundStyle(Color.kadoForegroundSecondary)
            }
        }
    }

    private func progress(_ range: ClosedRange<Date>) -> some View {
        let planned = range.upperBound.timeIntervalSince(range.lowerBound)
        let worked = open.session.elapsed(at: now)
        // Progress is worked time against the planned duration (a budget), not the clock.
        let remaining = planned - worked
        return VStack(alignment: .leading, spacing: 4) {
            ProgressView(value: min(worked, planned), total: max(planned, 1))
                .tint(Color.kadoAccent)
            Group {
                if remaining > 0 {
                    Text("\(Int(ceil(remaining / 60))) min left")
                } else {
                    Text("\(Int(floor(-remaining / 60))) min over")
                }
            }
            .font(.footnote)
            .foregroundStyle(Color.kadoForegroundSecondary)
        }
    }

    private var buttons: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) { finishButton; pauseOrResume }
            VStack(alignment: .leading, spacing: 12) { finishButton; pauseOrResume }
        }
    }

    private var finishButton: some View {
        Button("Finish", action: onFinish)
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .accessibilityIdentifier(AccessibilityID.Now.finish)
    }

    @ViewBuilder
    private var pauseOrResume: some View {
        if open.session.isPaused {
            Button("Resume", action: onResume)
                .buttonStyle(.bordered).controlSize(.large)
                .accessibilityIdentifier(AccessibilityID.Now.resume)
        } else {
            Button("Pause", action: onPause)
                .buttonStyle(.bordered).controlSize(.large)
                .accessibilityIdentifier(AccessibilityID.Now.pause)
        }
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
        now: .now, onTitle: {}, onPause: {}, onResume: {}, onFinish: {}
    )
    .padding()
    .background(Color.kadoBackground)
}

#Preview("Running, over time") {
    let start = Date.now.addingTimeInterval(-90 * 60)
    NowSessionCard(
        open: OpenSession(id: UUID(), item: .task(id: UUID(), title: "Write the quarterly report"), session: WorkSession(startedAt: start), blockID: nil),
        plannedRange: start...start.addingTimeInterval(60 * 60),
        now: .now, onTitle: {}, onPause: {}, onResume: {}, onFinish: {}
    )
    .padding()
    .background(Color.kadoBackground)
}

#Preview("Paused, Dark") {
    let start = Date.now.addingTimeInterval(-60 * 60)
    NowSessionCard(
        open: OpenSession(id: UUID(), item: .habit(id: UUID(), name: "Read 20 pages"),
                          session: WorkSession(startedAt: start, pausedAt: .now.addingTimeInterval(-12 * 60)), blockID: nil),
        plannedRange: nil, now: .now, onTitle: {}, onPause: {}, onResume: {}, onFinish: {}
    )
    .padding()
    .background(Color.kadoBackground)
    .preferredColorScheme(.dark)
}

#Preview("Running, XXXL") {
    let start = Date.now.addingTimeInterval(-48 * 60)
    NowSessionCard(
        open: OpenSession(id: UUID(), item: .task(id: UUID(), title: "Research"), session: WorkSession(startedAt: start), blockID: nil),
        plannedRange: start.addingTimeInterval(-17 * 60)...start.addingTimeInterval(103 * 60),
        now: .now, onTitle: {}, onPause: {}, onResume: {}, onFinish: {}
    )
    .padding()
    .background(Color.kadoBackground)
    .dynamicTypeSize(.accessibility3)
}
