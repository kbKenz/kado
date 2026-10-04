import SwiftUI
import KadoCore

/// A planned block not started yet: the current one or the next one.
struct NowSuggestionCard: View {
    let block: NowBlock
    let isCurrent: Bool
    let now: Date
    let onTitle: () -> Void
    let onStart: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            (isCurrent ? Text("NOW") : Text("NEXT"))
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.kadoForegroundSecondary)
                .accessibilityHidden(true)
            Button(action: onTitle) {
                Text(block.item.title)
                    .font(.largeTitle.bold())
                    .foregroundStyle(Color.kadoForeground)
                    .multilineTextAlignment(.leading)
            }
            .buttonStyle(.plain)
            .accessibilityHint(Text("Opens details"))
            .accessibilityIdentifier(AccessibilityID.Now.title)
            // One sentence: planned range, then how far it is from now.
            VStack(alignment: .leading, spacing: 12) {
                Text(block.range.nowTimeText)
                    .foregroundStyle(Color.kadoForegroundSecondary)
                Text(relative)
                    .foregroundStyle(Color.kadoForegroundSecondary)
            }
            .accessibilityElement(children: .combine)
            Button(startTitle, action: onStart)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .accessibilityIdentifier(AccessibilityID.Now.start)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color.kadoBackgroundSecondary, in: RoundedRectangle(cornerRadius: KadoRadius.card))
    }

    private var startTitle: LocalizedStringKey { isCurrent ? "Start" : "Start early" }

    private var relative: LocalizedStringKey {
        let minutes = Int(abs(block.start.timeIntervalSince(now)) / 60)
        if isCurrent { return "Planned \(minutes) min ago" }
        let hours = minutes / 60
        return hours > 0 ? "In \(hours) h \(minutes % 60) min" : "In \(minutes) min"
    }
}

struct NowEmptyState: View {
    var body: some View {
        ContentUnavailableView(
            "Nothing planned for the rest of today",
            systemImage: "sun.max",
            description: Text("Start a task or habit when you are ready.")
        )
    }
}

#Preview("Current") {
    NowSuggestionCard(
        block: NowBlock(id: UUID(), item: .task(id: UUID(), title: "Research"),
                        start: .now.addingTimeInterval(-17 * 60), end: .now.addingTimeInterval(43 * 60), createdAt: .now),
        isCurrent: true, now: .now, onTitle: {}, onStart: {}
    )
    .padding()
    .background(Color.kadoBackground)
}

#Preview("Next") {
    NowSuggestionCard(
        block: NowBlock(id: UUID(), item: .habit(id: UUID(), name: "Read 20 pages"),
                        start: .now.addingTimeInterval(95 * 60), end: nil, createdAt: .now),
        isCurrent: false, now: .now, onTitle: {}, onStart: {}
    )
    .padding()
    .background(Color.kadoBackground)
}

#Preview("Next, Dark XXXL") {
    NowSuggestionCard(
        block: NowBlock(id: UUID(), item: .task(id: UUID(), title: "Prepare the board meeting slides"),
                        start: .now.addingTimeInterval(25 * 60), end: nil, createdAt: .now),
        isCurrent: false, now: .now, onTitle: {}, onStart: {}
    )
    .padding()
    .background(Color.kadoBackground)
    .dynamicTypeSize(.accessibility3)
    .preferredColorScheme(.dark)
}

#Preview("Empty") {
    NowEmptyState()
        .background(Color.kadoBackground)
}
