import SwiftUI
import KadoCore

/// Work started today and paused, not done: one row per item with its
/// time today and a button to continue. Continuing while something else
/// runs pauses that one, so several things can be in progress at once.
struct NowPausedList: View {
    let items: [NowProgress]
    let glyphs: [UUID: ItemGlyph]
    /// True while another item runs: the button then switches to this one.
    let isSomethingRunning: Bool
    let onContinue: (NowItem) -> Void
    let onDone: (NowItem) -> Void
    let onOpen: (NowItem) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("PAUSED TODAY")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.kadoForegroundSecondary)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier(AccessibilityID.Now.paused)
            VStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    if index > 0 { Divider().padding(.leading) }
                    row(item)
                }
            }
            .background(Color.kadoBackgroundSecondary, in: RoundedRectangle(cornerRadius: KadoRadius.card))
            Text("Touch and hold a row for more.")
                .font(.footnote)
                .foregroundStyle(Color.kadoForegroundSecondary)
        }
    }

    private func row(_ progress: NowProgress) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    if let glyph = glyphs[progress.item.id] { ItemGlyphView(glyph: glyph) }
                    Text(verbatim: progress.item.title)
                        .foregroundStyle(Color.kadoForeground)
                }
                Text(summary(progress))
                    .font(.footnote)
                    .foregroundStyle(Color.kadoForegroundSecondary)
                if let target = progress.targetSeconds, target > 0 {
                    ProgressView(value: min(progress.countedSeconds, target), total: target)
                        .tint(Color.kadoAccent)
                        .padding(.top, 4)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture { onOpen(progress.item) }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
            .accessibilityHint(Text("Opens the details."))
            .accessibilityAction { onOpen(progress.item) }
            .modifier(MarkDoneAction(isAvailable: progress.canMarkDone) { onDone(progress.item) })
            .accessibilityIdentifier(AccessibilityID.Now.pausedRow(progress.item.id))

            Button { onContinue(progress.item) } label: {
                Image(systemName: "play.fill")
                    .font(.body.weight(.semibold))
                    .frame(width: 44, height: 44)
                    .background(Color.kadoAccent.opacity(0.15), in: Circle())
                    .foregroundStyle(Color.kadoAccent)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(continueLabel(progress))
            .accessibilityIdentifier(AccessibilityID.Now.continueItem(progress.item.id))
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .contextMenu { menu(progress) }
    }

    @ViewBuilder
    private func menu(_ progress: NowProgress) -> some View {
        Button { onContinue(progress.item) } label: {
            Label("Continue", systemImage: "play.fill")
        }
        if progress.canMarkDone {
            Button { onDone(progress.item) } label: {
                Label("Mark as done", systemImage: "checkmark.circle")
            }
            .accessibilityIdentifier(AccessibilityID.Now.markDone)
        }
        Button { onOpen(progress.item) } label: {
            Label("Open", systemImage: "info.circle")
        }
    }

    /// "1 hr, 20 min today · stopped 11:40" or, for a timer habit,
    /// "2 hr of 4 hr · stopped 11:40".
    private func summary(_ progress: NowProgress) -> String {
        let worked = NowDurationText.text(progress.countedSeconds)
        let amount: String
        if let target = progress.targetSeconds, target > 0 {
            amount = String(localized: "\(worked) of \(NowDurationText.text(target))")
        } else {
            amount = String(localized: "\(worked) today")
        }
        guard let stopped = progress.lastStoppedAt else { return amount }
        let time = stopped.formatted(date: .omitted, time: .shortened)
        return String(localized: "\(amount) · stopped \(time)")
    }

    private func continueLabel(_ progress: NowProgress) -> String {
        isSomethingRunning
            ? String(localized: "Switch to \(progress.item.title)")
            : String(localized: "Continue \(progress.item.title)")
    }
}

/// The context menu's Done, for VoiceOver's Actions rotor.
private struct MarkDoneAction: ViewModifier {
    let isAvailable: Bool
    let action: () -> Void

    func body(content: Content) -> some View {
        if isAvailable {
            content.accessibilityAction(named: Text("Mark as done"), action)
        } else {
            content
        }
    }
}

#Preview("Paused today") {
    let morning = Calendar.current.startOfDay(for: .now).addingTimeInterval(9 * 3600)
    NowPausedList(
        items: [
            NowProgress(item: .habit(id: UUID(), name: "IELTS prep"),
                        runs: [DateInterval(start: morning, duration: 7200)],
                        countedSeconds: 7200, targetSeconds: 14_400, canMarkDone: false),
            NowProgress(item: .task(id: UUID(), title: "Quarterly report"),
                        runs: [DateInterval(start: morning.addingTimeInterval(7800), duration: 2700)],
                        countedSeconds: 2700),
        ],
        glyphs: [:], isSomethingRunning: true,
        onContinue: { _ in }, onDone: { _ in }, onOpen: { _ in }
    )
    .padding()
    .background(Color.kadoBackground)
}

#Preview("Paused today, Dark XXXL") {
    let morning = Calendar.current.startOfDay(for: .now).addingTimeInterval(9 * 3600)
    NowPausedList(
        items: [
            NowProgress(item: .task(id: UUID(), title: "Prepare the IELTS speaking part"),
                        runs: [DateInterval(start: morning, duration: 5400)], countedSeconds: 5400),
        ],
        glyphs: [:], isSomethingRunning: false,
        onContinue: { _ in }, onDone: { _ in }, onOpen: { _ in }
    )
    .padding()
    .background(Color.kadoBackground)
    .preferredColorScheme(.dark)
    .dynamicTypeSize(.accessibility3)
}
