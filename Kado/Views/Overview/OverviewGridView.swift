import SwiftData
import SwiftUI
import KadoCore

/// The Overview tab's Grid mode: habits × days matrix. `OverviewView`
/// owns the navigation stack and the title around it.
///
/// Layout (single horizontal scroll):
/// - One full-width `ScrollView(.horizontal)` holds a VStack that,
///   per habit, alternates a clear "name" spacer and a cells row.
///   Every cell row moves together because there's only one scroll
///   state.
/// - A sibling VStack overlays the scroll view with the habit
///   labels, positioned over the clear spacer rows. It has a
///   transparent background and `.allowsHitTesting(false)` so the
///   scroll + cell taps still reach the layer below.
/// - Outer `ScrollView(.vertical)` keeps the "Overview" title
///   collapsing like Today and Settings.
///
/// Tapping a cell opens `DayEditPopover` on that (habit × day). The
/// popover is fed value snapshots — the same `Completion` array the
/// matrix is computed from — and its callbacks resolve the live
/// `HabitRecord` from `records` only inside the mutation, never a
/// fetch. That is what keeps the matrix following its own edits: a
/// view mutating through its own `@Query` re-renders on a value-only
/// save (issue #80), and nothing retained across renders holds a
/// record that a container swap could invalidate (issue #63).
///
/// This view reads the store and computes the rows; `OverviewMatrixGrid`
/// draws them and owns the selection and the haptic. A tap or a
/// popover dismissal then re-renders the grid alone, and an edit
/// scores only the habit it changed (`OverviewGridRows`).
struct OverviewGridView: View {
    @Query(
        filter: #Predicate<HabitRecord> { $0.archivedAt == nil },
        sort: \HabitRecord.sortOrder
    )
    private var records: [HabitRecord]

    @Environment(\.calendar) private var calendar
    @Environment(\.today) private var now
    @Environment(\.frequencyEvaluator) private var frequencyEvaluator
    @Environment(\.streakCalculator) private var streakCalculator
    @Environment(\.habitScoreCalculator) private var scoreCalculator

    @State private var showingNewHabit = false
    /// Rows and metrics from earlier renders, reused per habit.
    @State private var gridRows = OverviewGridRows()

    private static let dayWindow = 30

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.kadoBackground.ignoresSafeArea())
            .sheet(isPresented: $showingNewHabit) {
                NewHabitFormView(model: NewHabitFormModel())
            }
    }

    @ViewBuilder
    private var content: some View {
        if records.isEmpty {
            emptyState
        } else {
            matrix
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No habits yet", systemImage: "square.grid.2x2")
        } description: {
            Text("Habits you create will appear here.")
        } actions: {
            Button {
                showingNewHabit = true
            } label: {
                Label("Create your first habit", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private var matrix: some View {
        let today = calendar.startOfDay(for: now)
        let days = dayRange(endingAt: today)
        let snapshots = records.map { record -> (habit: Habit, completions: [Completion]) in
            (record.snapshot, (record.completions ?? []).compactMap(\.snapshot))
        }
        let output = gridRows.compute(
            snapshots,
            days: days,
            today: today,
            now: now,
            calendar: calendar,
            frequencyEvaluator: frequencyEvaluator,
            streakCalculator: streakCalculator,
            scoreCalculator: scoreCalculator
        )
        // What the popover reads its value from — the same snapshots the
        // cells were drawn from, so the two can't disagree.
        let completionsByHabit = Dictionary(uniqueKeysWithValues: snapshots.map { ($0.habit.id, $0.completions) })

        return OverviewMatrixGrid(
            rows: output.rows,
            days: days,
            metrics: output.metrics,
            completionsByHabit: completionsByHabit,
            record: record(for:)
        )
    }

    /// The live record behind a cell, resolved against the query that
    /// is mounted now. Called from the mutations only, never from a
    /// render — see the type comment.
    private func record(for habitID: UUID) -> HabitRecord? {
        records.first { $0.id == habitID }
    }

    private func dayRange(endingAt today: Date) -> [Date] {
        (0..<Self.dayWindow).reversed().compactMap { offset in
            calendar.date(byAdding: .day, value: -offset, to: today)
        }
    }
}

/// The Grid itself: cells, labels and the cell popover. Owns the
/// selection and the haptic, so changing either re-renders this view
/// and not the one that reads the store.
private struct OverviewMatrixGrid: View {
    let rows: [MatrixRow]
    let days: [Date]
    let metrics: [UUID: OverviewGridRows.Metrics]
    let completionsByHabit: [UUID: [Completion]]
    /// Resolves a habit's live record. Called from the mutations only.
    let record: (UUID) -> HabitRecord?

    @Environment(\.habitTheme) private var habitTheme
    @Environment(\.calendar) private var calendar
    @Environment(\.modelContext) private var modelContext

    @State private var selection: CellSelection?
    /// The latest popover step, for the haptic — recorded at the
    /// mutation site, as on the detail screen.
    @State private var quickLog: QuickLogEvent?

    private static let cellSize: CGFloat = 36
    private static let cellSpacing: CGFloat = 6
    private static let labelHeight: CGFloat = 28
    private static let labelBottomPadding: CGFloat = 8
    private static let rowGap: CGFloat = 12
    private static let headerHeight: CGFloat = 40

    /// The cell whose popover is up. Addressed by id and day only: the
    /// popover reads its value from the current render, so nothing
    /// captured at tap time can go stale under it.
    struct CellSelection: Equatable {
        let habitID: UUID
        let date: Date
    }

    var body: some View {
        // One date string per column, shared by every row's cells.
        let dateLabels = days.map { Self.fullDate($0, calendar: calendar) }
        return ScrollView(.vertical) {
            ZStack(alignment: .topLeading) {
                scrollingCells(dateLabels: dateLabels)
                labelsOverlay
            }
            .padding(.vertical, 8)
        }
        .scrollContentBackground(.hidden)
        .background(Color.kadoBackground.ignoresSafeArea())
        .quickLogFeedback(quickLog)
    }

    /// Binding that reflects whether a specific (habit, date) cell is
    /// the currently selected one. Used to attach `.popover` per-cell
    /// so the popover anchors to the tapped button rather than the
    /// whole matrix. Days compare by calendar day, as the detail
    /// calendar's binding does, not by instant.
    private func isSelected(habitID: UUID, date: Date) -> Bool {
        guard let sel = selection else { return false }
        return sel.habitID == habitID && calendar.isDate(sel.date, inSameDayAs: date)
    }

    private func selectionBinding(habitID: UUID, date: Date) -> Binding<Bool> {
        Binding(
            get: { isSelected(habitID: habitID, date: date) },
            set: { newValue in
                if !newValue,
                   let sel = selection,
                   sel.habitID == habitID,
                   calendar.isDate(sel.date, inSameDayAs: date) {
                    selection = nil
                }
            }
        )
    }

    private func scrollingCells(dateLabels: [String]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                // Date column headers — scroll horizontally with the cells.
                HStack(spacing: Self.cellSpacing) {
                    ForEach(days, id: \.self) { day in
                        DayColumnHeader(date: day, width: Self.cellSize)
                    }
                }
                .frame(height: Self.headerHeight)

                Color.clear.frame(height: Self.rowGap)

                ForEach(rows, id: \.habit.id) { row in
                    // Transparent spacer where the label + padding overlay.
                    Color.clear.frame(height: Self.labelHeight + Self.labelBottomPadding)
                    cellRow(row, dateLabels: dateLabels, completions: completionsByHabit[row.habit.id] ?? [])
                    if row.habit.id != rows.last?.habit.id {
                        Color.clear.frame(height: Self.rowGap)
                    }
                }
            }
            .padding(.horizontal, 16)
        }
        .defaultScrollAnchor(.trailing)
    }

    private var labelsOverlay: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Match the date-header row + its trailing gap so the first
            // label lands in the first habit's spacer slot.
            Color.clear.frame(height: Self.headerHeight + Self.rowGap)

            ForEach(rows, id: \.habit.id) { row in
                HStack(spacing: 8) {
                    Image(systemName: row.habit.icon)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(row.habit.color.color(in: habitTheme))
                    Text(row.habit.name)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Color.kadoForeground)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        // On the `Text` rather than the enclosing
                        // `HStack`: an identifier on the row would be
                        // stamped over the `MetricsChip` beside it.
                        .accessibilityIdentifier(
                            AccessibilityID.Overview.habitLabel(row.habit.id)
                        )
                    Spacer(minLength: 8)
                    if let m = metrics[row.habit.id] {
                        MetricsChip(streak: m.streak, scorePercent: m.scorePercent)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: Self.labelHeight)

                // Spacer for the breathing room below the name + the
                // cell row itself, so the next label lines up with the
                // next habit's spacer slot.
                Color.clear.frame(height: Self.labelBottomPadding + Self.cellSize)
                if row.habit.id != rows.last?.habit.id {
                    Color.clear.frame(height: Self.rowGap)
                }
            }
        }
        .padding(.horizontal, 16)
        .allowsHitTesting(false)
    }

    private func cellRow(_ row: MatrixRow, dateLabels: [String], completions: [Completion]) -> some View {
        HStack(spacing: Self.cellSpacing) {
            ForEach(Array(zip(days, row.days).enumerated()), id: \.offset) { offset, pair in
                let (day, cell) = pair
                matrixCell(
                    row: row,
                    day: day,
                    dateLabel: dateLabels[offset],
                    cell: cell,
                    daysAgo: days.count - 1 - offset,
                    completions: completions
                )
            }
        }
        .frame(height: Self.cellSize)
    }

    /// Grey cells inside the tracked range open the editor — a day the
    /// schedule didn't ask for can still be logged, as on the detail
    /// calendar. A day before the habit's start does not: logging it
    /// would quietly move the start back and turn the month in between
    /// into misses (issue #104). Back-dating stays on the detail
    /// calendar, which says so before it happens. The window ends
    /// today, so `.future` never reaches this row.
    ///
    /// The cell whose popover is up stays a button whatever its state.
    /// Stepping a habit's earliest day down to zero moves the start
    /// past it and turns it `.beforeStart` under the open popover;
    /// swapping the branch then would tear the popover down mid-edit,
    /// with no way back from the Overview.
    @ViewBuilder
    private func matrixCell(
        row: MatrixRow,
        day: Date,
        dateLabel: String,
        cell: DayCell,
        daysAgo: Int,
        completions: [Completion]
    ) -> some View {
        let label = Self.accessibilityLabel(habit: row.habit, dateString: dateLabel, cell: cell)
        let identifier = AccessibilityID.Overview.cell(row.habit.id, daysAgo: daysAgo)
        let visual = MatrixCell(state: cell, color: row.habit.color, size: Self.cellSize)
        if cell.isEditable || isSelected(habitID: row.habit.id, date: day) {
            Button {
                selection = CellSelection(habitID: row.habit.id, date: day)
            } label: {
                visual
            }
            .buttonStyle(.plain)
            .accessibilityLabel(label)
            .accessibilityHint(Text("Double-tap to edit this day."))
            .accessibilityIdentifier(identifier)
            .popover(isPresented: selectionBinding(habitID: row.habit.id, date: day)) {
                dayEditPopover(for: row.habit, on: day, cell: cell, completions: completions)
            }
        } else {
            visual
                .accessibilityElement()
                .accessibilityLabel(label)
                .accessibilityIdentifier(identifier)
        }
    }

    /// The editor for one cell, fed from the render's value snapshots.
    /// Kept out of `cellRow` so the type-checker has one closure fewer
    /// to fit inside the `ForEach`.
    private func dayEditPopover(
        for habit: Habit,
        on day: Date,
        cell: DayCell,
        completions: [Completion]
    ) -> some View {
        let completion = completions.first { calendar.isDate($0.date, inSameDayAs: day) }
        // A pre-start day can still get here — it holds a record, or
        // was stepped to zero under this popover — so it carries the
        // detail calendar's warning, which replaces "Not scheduled".
        let backdatesStart = habit.loggingBackdatesStart(
            on: day, completions: completions, calendar: calendar
        )
        let notScheduled: Bool
        switch cell {
        case .notDue, .offSchedule:
            notScheduled = !backdatesStart
        case .future, .beforeStart, .scored:
            notScheduled = false
        }
        return DayEditPopover(
            habit: habit,
            date: day,
            currentValue: completion?.value ?? 0,
            currentNote: completion?.note,
            onToggle: { toggle(habit, on: day) },
            onSetCounter: { value in setCounter(value, for: habit, on: day) },
            onSetTimerSeconds: { seconds in setTimerSeconds(seconds, for: habit, on: day) },
            onClear: { clear(habit, on: day) },
            onNoteChanged: { note in setNote(note, for: habit, on: day) },
            notScheduled: notScheduled,
            backdatesStart: backdatesStart
        )
        .presentationCompactAdaptation(.popover)
    }

    // MARK: - Cell popover mutations

    private var dayEditor: DayCompletionEditor { DayCompletionEditor(calendar: calendar) }

    private func recordQuickLog(_ change: DayCompletionEditor.Change, type: HabitType) {
        guard let event = QuickLogEvent.next(
            after: quickLog, type: type, oldValue: change.before, newValue: change.after
        ) else { return }
        quickLog = event
    }

    private func toggle(_ habit: Habit, on day: Date) {
        guard let record = record(habit.id) else { return }
        let change = dayEditor.toggle(for: record, on: day, in: modelContext)
        recordQuickLog(change, type: habit.type)
    }

    private func setCounter(_ value: Double, for habit: Habit, on day: Date) {
        guard let record = record(habit.id) else { return }
        let change = dayEditor.setCounter(value, for: record, on: day, in: modelContext)
        recordQuickLog(change, type: habit.type)
    }

    private func setTimerSeconds(_ seconds: TimeInterval, for habit: Habit, on day: Date) {
        guard let record = record(habit.id) else { return }
        let change = dayEditor.setTimerSeconds(seconds, for: record, on: day, in: modelContext)
        recordQuickLog(change, type: habit.type)
    }

    private func clear(_ habit: Habit, on day: Date) {
        guard let record = record(habit.id) else { return }
        let change = dayEditor.clear(for: record, on: day, in: modelContext)
        recordQuickLog(change, type: habit.type)
    }

    private func setNote(_ note: String?, for habit: Habit, on day: Date) {
        guard let record = record(habit.id) else { return }
        dayEditor.setNote(note, for: record, on: day, in: modelContext)
    }

    // MARK: - VoiceOver labels

    /// What a `.full` date formatter is built from. The formatter's own
    /// time zone defaults to the system's, so that is part of it too.
    private struct FormatterKey: Hashable {
        let calendar: Calendar
        let locale: Locale
        let timeZone: TimeZone
    }

    /// `DateFormatter` is costly to make, and every render labels each
    /// column, so one is kept per calendar, locale and zone. Main actor
    /// only, like the renders that read it.
    private static var fullDateFormatters: [FormatterKey: DateFormatter] = [:]

    /// The column's date, spelled out for VoiceOver.
    private static func fullDate(_ date: Date, calendar: Calendar) -> String {
        let key = FormatterKey(calendar: calendar, locale: calendar.locale ?? .current, timeZone: .current)
        if let formatter = fullDateFormatters[key] {
            return formatter.string(from: date)
        }
        let formatter = DateFormatter()
        formatter.calendar = key.calendar
        formatter.locale = key.locale
        formatter.dateStyle = .full
        fullDateFormatters[key] = formatter
        return formatter.string(from: date)
    }

    /// Composes a per-cell VoiceOver label:
    /// `"{habit}, {localized date}, {state}"`.
    private static func accessibilityLabel(
        habit: Habit,
        dateString: String,
        cell: DayCell
    ) -> String {
        let state: String
        switch cell {
        case .future:
            state = String(localized: "upcoming")
        case .notDue:
            state = String(localized: "not scheduled")
        case .beforeStart:
            state = String(localized: "before tracking started")
        case .scored(let s):
            state = completionPhrase(for: s)
        case .offSchedule(let s):
            // The hollow cell is a purely visual distinction, so
            // VoiceOver has to say it out loud.
            state = String(
                localized: "\(completionPhrase(for: s)), off schedule",
                comment: "Overview cell state for a day logged outside the habit's schedule. Argument: the completion phrase, e.g. 'completed'."
            )
        }
        return "\(habit.name), \(dateString), \(state)"
    }

    /// Shared wording for a day's value, used on its own for
    /// scheduled days and embedded in the off-schedule phrasing.
    private static func completionPhrase(for value: Double) -> String {
        if value >= 1.0 {
            return String(localized: "completed")
        } else if value <= 0.0 {
            return String(localized: "missed")
        } else {
            let percent = Int((value * 100).rounded())
            return String(localized: "\(percent)% complete")
        }
    }
}

#Preview("Populated") {
    NavigationStack {
        OverviewGridView()
            .navigationTitle("Overview")
    }
    .modelContainer(PreviewContainer.shared)
}

#Preview("Empty") {
    NavigationStack {
        OverviewGridView()
            .navigationTitle("Overview")
    }
    .modelContainer(PreviewContainer.emptyContainer())
}

#Preview("Dark") {
    NavigationStack {
        OverviewGridView()
            .navigationTitle("Overview")
    }
    .modelContainer(PreviewContainer.shared)
    .preferredColorScheme(.dark)
}

#Preview("Dynamic Type XXXL") {
    NavigationStack {
        OverviewGridView()
            .navigationTitle("Overview")
    }
    .modelContainer(PreviewContainer.shared)
    .environment(\.dynamicTypeSize, .accessibility3)
}
