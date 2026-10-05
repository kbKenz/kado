import SwiftUI
import KadoCore

/// The History list: the filter chips, then one section per day with a
/// pinned header, a page at a time.
///
/// Days are already computed; paging only limits how many sections are
/// in the stack, so a long history stays cheap to diff. The next page
/// loads when the spinner under the last day appears. A gap of days with
/// nothing shown reads as one quiet line, so the scroll never pads empty
/// days, and the list ends on a marker that says where the record
/// starts (or that it is up to date, oldest first).
struct HistoryFeed: View {
    let days: [HistoryDay]
    let query: HistoryQuery
    let availableCategories: [ItemCategory]
    /// The oldest day with anything done, whatever the filters.
    let firstDay: Date?
    @Binding var kind: HistoryKind
    @Binding var categories: Set<ItemCategory>
    @Binding var jumpTarget: Date?
    var actions: HistoryActions

    @Environment(\.calendar) private var calendar

    /// Sections in the stack. Reset to one page when the query changes.
    @State private var shownCount = Self.pageSize
    @State private var position = ScrollPosition(edge: .top)
    @State private var scrollsToTopOnNextDays = false

    static let pageSize = 14

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                    // Nothing done at all: no chip would change that.
                    if !days.isEmpty || query.isFiltered {
                        HistoryFilterBar(kind: $kind, categories: $categories, available: availableCategories)
                            .padding(.bottom, 8)
                    }
                    if days.isEmpty {
                        emptyState
                    } else {
                        ForEach(days.prefix(shownCount)) { day in
                            section(day)
                        }
                        footer
                    }
                }
                .padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.immediately)
            .background(Color.kadoBackground.ignoresSafeArea())
            // A new order or filter starts a new page at the top, or the
            // user lands mid-list among days they never scrolled to. The
            // days for the new query arrive a moment later, from off the
            // main actor, so the jump waits for them.
            .scrollPosition($position)
            .onChange(of: query) {
                shownCount = Self.pageSize
                scrollsToTopOnNextDays = true
            }
            .onChange(of: days) {
                guard scrollsToTopOnNextDays else { return }
                scrollsToTopOnNextDays = false
                position.scrollTo(edge: .top)
            }
            .onChange(of: jumpTarget) { _, target in
                guard let target else { return }
                jump(to: target, proxy: proxy)
            }
        }
    }

    private func section(_ day: HistoryDay) -> some View {
        Section {
            VStack(spacing: 0) {
                ForEach(day.entries) { entry in
                    HistoryEntryRow(entry: entry, actions: actions)
                    if entry.id != day.entries.last?.id {
                        Divider().padding(.leading, 60)
                    }
                }
            }
            .background(
                Color.kadoBackgroundSecondary,
                in: RoundedRectangle(cornerRadius: KadoRadius.card, style: .continuous)
            )
            .padding(.horizontal)
            .padding(.bottom, 12)
        } header: {
            VStack(spacing: 0) {
                if day.quietDaysBefore > 0 {
                    QuietDaysLine(count: day.quietDaysBefore)
                }
                HistoryDayHeader(day: day)
            }
        }
        .id(day.day)
    }

    @ViewBuilder
    private var footer: some View {
        if shownCount < days.count {
            ProgressView()
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .onAppear { shownCount += Self.pageSize }
        } else {
            HistoryEndMarker(
                order: query.dayOrder,
                firstDay: firstDay,
                isFiltered: query.isFiltered
            )
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        if query.isFiltered {
            ContentUnavailableView {
                Label("No matches", systemImage: "magnifyingglass")
            } description: {
                Text("Nothing you've done matches these filters.")
            } actions: {
                if kind != .all || !categories.isEmpty {
                    Button("Clear filters") {
                        kind = .all
                        categories = []
                    }
                }
            }
            .padding(.top, 40)
            .accessibilityIdentifier(AccessibilityID.History.noMatch)
        } else {
            ContentUnavailableView {
                Label("Nothing done yet", systemImage: "clock.arrow.circlepath")
            } description: {
                Text("Complete a task or log a habit, and it shows up here, day by day.")
            }
            .padding(.top, 40)
            .accessibilityIdentifier(AccessibilityID.History.empty)
        }
    }

    /// Loads the pages up to the day shown on or before `target` (on or
    /// after it, oldest first), then scrolls its header to the top.
    private func jump(to target: Date, proxy: ScrollViewProxy) {
        let day = calendar.startOfDay(for: target)
        let index: Int?
        switch query.dayOrder {
        case .newestFirst:
            index = days.firstIndex { $0.day <= day } ?? (days.isEmpty ? nil : days.count - 1)
        case .oldestFirst:
            index = days.firstIndex { $0.day >= day } ?? (days.isEmpty ? nil : days.count - 1)
        }
        jumpTarget = nil
        guard let index else { return }
        shownCount = max(shownCount, index + Self.pageSize)
        let id = days[index].day
        Task { @MainActor in
            // One pass for the new sections to join the stack.
            await Task.yield()
            withAnimation { proxy.scrollTo(id, anchor: .top) }
        }
    }
}

/// "3 quiet days": the gap between two days on the page.
private struct QuietDaysLine: View {
    let count: Int

    var body: some View {
        HStack(spacing: 8) {
            line
            Text("\(count) quiet days", comment: "History: the number of days with nothing done between two days in the list.")
                .font(.caption)
                .foregroundStyle(Color.kadoForegroundSecondary)
                .fixedSize()
            line
        }
        .padding(.horizontal, 32)
        .padding(.top, 4)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity)
        .background(Color.kadoBackground)
    }

    private var line: some View {
        Rectangle()
            .fill(Color.kadoHairline)
            .frame(height: 1)
            .accessibilityHidden(true)
    }
}

/// The marker under the last day.
private struct HistoryEndMarker: View {
    let order: HistoryDayOrder
    let firstDay: Date?
    let isFiltered: Bool

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: order == .newestFirst ? "leaf" : "checkmark.circle")
                .font(.title3)
                .foregroundStyle(Color.kadoForegroundSecondary)
                .accessibilityHidden(true)
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.kadoForeground)
            if let detail {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(Color.kadoForegroundSecondary)
            }
            Text("Long-press an item to edit or undo it.")
                .font(.caption2)
                .foregroundStyle(Color.kadoForegroundSecondary)
                .padding(.top, 6)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 32)
        .padding(.vertical, 20)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(AccessibilityID.History.end)
    }

    private var title: String {
        switch order {
        case .newestFirst:
            return String(localized: "That's the beginning", comment: "History: marker under the oldest day in the list.")
        case .oldestFirst:
            return String(localized: "You're up to date", comment: "History: marker under the newest day when the list runs oldest first.")
        }
    }

    private var detail: String? {
        guard order == .newestFirst, !isFiltered, let firstDay else { return nil }
        let date = firstDay.formatted(date: .long, time: .omitted)
        return String(localized: "Your first entry was on \(date).", comment: "History: under the end marker. The value is a date.")
    }
}

#Preview("Feed") {
    NavigationStack {
        HistoryFeed(
            days: HistoryPreviewData.days,
            query: HistoryQuery(),
            availableCategories: [.work, .study, .fitness, .health],
            firstDay: HistoryPreviewData.days.last?.day,
            kind: .constant(.all),
            categories: .constant([]),
            jumpTarget: .constant(nil),
            actions: HistoryActions()
        )
        .navigationTitle("Overview")
    }
}

#Preview("Dark, filtered empty") {
    NavigationStack {
        HistoryFeed(
            days: [],
            query: HistoryQuery(kind: .tasks),
            availableCategories: [.work],
            firstDay: nil,
            kind: .constant(.tasks),
            categories: .constant([]),
            jumpTarget: .constant(nil),
            actions: HistoryActions()
        )
        .navigationTitle("Overview")
    }
    .preferredColorScheme(.dark)
}

#Preview("Empty") {
    HistoryFeed(
        days: [],
        query: HistoryQuery(),
        availableCategories: [],
        firstDay: nil,
        kind: .constant(.all),
        categories: .constant([]),
        jumpTarget: .constant(nil),
        actions: HistoryActions()
    )
}
