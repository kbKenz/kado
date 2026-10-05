import OSLog
import SwiftData
import SwiftUI
import KadoCore

/// The Overview tab's Insights mode: picks the period, gets a report
/// and hosts the feed. It also does what the cards ask for: pushes a
/// habit or a goal onto the Overview stack, and opens the New Habit
/// form from a template.
///
/// The report is built from the store (`InsightsInputBuilder`) and
/// Apple Health (`InsightsHealthLoader`), then computed off the main
/// actor. Under the UI suite's `-uiTestInsightsFixture` it shows
/// `InsightsPreviewData.rich` instead, so a test sees every card filled.
///
/// This view watches the store; `InsightsContent` holds the report and
/// everything else. A new report, a Health read or a sheet then
/// re-renders the feed alone, and never walks every record again.
struct InsightsScreen: View {
    @Binding var path: NavigationPath
    /// The reports last shown, kept across a mode or period switch.
    let cache: OverviewCache

    // Read only so a change to the store triggers a new report.
    @Query private var habitRecords: [HabitRecord]
    @Query private var completionRecords: [CompletionRecord]
    @Query private var taskRecords: [TaskRecord]
    @Query private var sessionRecords: [WorkSessionRecord]
    @Query private var goalRecords: [GoalRecord]

    var body: some View {
        InsightsContent(path: $path, cache: cache, storeKey: storeKey)
    }

    /// Changes whenever anything the report reads changes.
    private var storeKey: Int {
        var hasher = Hasher()
        for record in completionRecords {
            hasher.combine(record.id)
            hasher.combine(record.value)
            hasher.combine(record.date)
        }
        for record in taskRecords {
            hasher.combine(record.id)
            hasher.combine(record.updatedAt)
            hasher.combine(record.completedAt)
            hasher.combine(record.categoryRaw)
        }
        for record in sessionRecords {
            hasher.combine(record.id)
            hasher.combine(record.endedAt)
            hasher.combine(record.pausedSeconds)
        }
        for record in habitRecords {
            hasher.combine(record.id)
            hasher.combine(record.name)
            hasher.combine(record.archivedAt)
            hasher.combine(record.categoryRaw)
        }
        for record in goalRecords {
            hasher.combine(record.id)
            hasher.combine(record.updatedAt)
        }
        return hasher.finalize()
    }
}

/// The Insights feed and what it asks for. See `InsightsScreen`.
private struct InsightsContent: View {
    @Binding var path: NavigationPath
    let cache: OverviewCache
    /// Moves whenever a record the report reads changes.
    let storeKey: Int

    @Environment(\.modelContext) private var modelContext
    @Environment(\.calendar) private var calendar
    @Environment(\.today) private var today
    @Environment(\.civilToday) private var civilToday
    @Environment(\.dayBoundary) private var dayBoundary
    @Environment(\.frequencyEvaluator) private var frequencyEvaluator
    @Environment(\.streakCalculator) private var streakCalculator
    @Environment(\.habitScoreCalculator) private var scoreCalculator
    @Environment(\.healthTimelineProvider) private var healthProvider

    @AppStorage(OverviewModeDefaults.insightsPeriodKey) private var period: InsightsPeriod = .month
    @AppStorage(HealthCalendarDefaults.key) private var healthEnabled = false

    /// The last report. Kept while a new one computes, so the feed never
    /// flashes empty.
    @State private var report: InsightsReport?
    @State private var health: InsightsHealth = .disconnected
    /// What `health` was last read for. With Health on, a report waits
    /// for it: computing first and again once Health landed did the
    /// whole report twice, and showed the Health cards empty meanwhile.
    @State private var healthLoadedFor: HealthKey?

    /// The New Habit form opened from a template. Holds the form's
    /// model, so a re-render never resets what the user typed.
    @State private var templateDraft: TemplateDraft?
    @State private var isRequestingHealth = false

    private static let logger = Logger(subsystem: "dev.scastiel.kado", category: "insights")

    struct TemplateDraft: Identifiable {
        let template: InsightsHabitTemplate
        let model: NewHabitFormModel
        var id: String { template.rawValue }
    }

    var body: some View {
        content
            .navigationDestination(for: HabitRoute.self) { route in
                HabitDetailLoader(habitID: route.id)
            }
            .navigationDestination(for: GoalRoute.self) { route in
                GoalDetailView(goalID: route.id)
            }
            .sheet(item: $templateDraft) { draft in
                NewHabitFormView(model: draft.model)
            }
            .task(id: healthKey) { await loadHealth() }
            .task(id: refreshKey) { await recompute() }
    }

    @ViewBuilder
    private var content: some View {
        if let shown = shownReport {
            InsightsFeed(report: shown, period: $period, actions: actions)
        } else {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.kadoBackground.ignoresSafeArea())
        }
    }

    /// What the feed shows. See the type comment.
    private var shownReport: InsightsReport? {
        if UITestSupport.showsInsightsFixture {
            return InsightsPreviewData.rich(for: period)
        }
        // A report for another period would show the wrong window.
        if let report, report.period == period { return report }
        // Until this period's report lands, the last one Overview kept.
        return cache.report(for: period, today: today, civilToday: civilToday)
    }

    /// Changes whenever anything the report reads changes.
    private var refreshKey: RefreshKey {
        RefreshKey(
            period: period,
            today: today,
            civilToday: civilToday,
            data: storeKey,
            health: health,
            isHealthReady: isHealthReady
        )
    }

    private struct RefreshKey: Equatable {
        var period: InsightsPeriod
        var today: Date
        var civilToday: Date
        var data: Int
        var health: InsightsHealth
        var isHealthReady: Bool
    }

    /// Off, Health has nothing to wait for. On, it is ready once read
    /// for this period and day.
    private var isHealthReady: Bool {
        !healthEnabled || healthLoadedFor == healthKey
    }

    private struct HealthKey: Equatable {
        var period: InsightsPeriod
        var civilToday: Date
        var isEnabled: Bool
    }

    private var healthKey: HealthKey {
        HealthKey(period: period, civilToday: civilToday, isEnabled: healthEnabled)
    }

    /// Builds the input on the main actor (SwiftData), then computes the
    /// report off it.
    private func recompute() async {
        guard !UITestSupport.showsInsightsFixture else { return }
        // Health landing changes the key and runs this again.
        guard isHealthReady else { return }
        var input: InsightsInput
        do {
            input = try InsightsInputBuilder(civilToday: civilToday, calendar: calendar).build(in: modelContext)
        } catch {
            let nsError = error as NSError
            Self.logger.error("Insights input failed: \(nsError.domain, privacy: .public) \(nsError.code, privacy: .public)")
            return
        }
        input.health = health
        let context = InsightsContext(
            period: period,
            now: .now,
            today: today,
            calendar: calendar,
            dayBoundary: dayBoundary,
            frequencyEvaluator: frequencyEvaluator,
            streakCalculator: streakCalculator,
            scoreCalculator: scoreCalculator
        )
        let finished = input
        let day = (today: today, civilToday: civilToday)
        let work = Task.detached(priority: .userInitiated) {
            InsightsCalculator().report(input: finished, context: context)
        }
        let result = await withTaskCancellationHandler {
            await work.value
        } onCancel: {
            work.cancel()
        }
        // A newer key has started its own report: that one wins.
        guard !Task.isCancelled else { return }
        report = result
        cache.store(result, today: day.today, civilToday: day.civilToday)
    }

    private func loadHealth() async {
        let key = healthKey
        let interval = InsightsHealthLoader.queryInterval(for: period, today: civilToday, now: .now, calendar: calendar)
        do {
            let read = try await InsightsHealthLoader(provider: healthProvider, calendar: calendar)
                .health(in: interval, isEnabled: healthEnabled)
            // The loader can still return after a cancel (its sleep
            // grouping runs detached). A newer key started its own read,
            // and that one wins: an older one landing last would mark
            // Health as read for the old key, and no report would run
            // again until the key moved.
            guard !Task.isCancelled else { return }
            health = read
            healthLoadedFor = key
        } catch {
            // Cancelled: keep what was read before.
        }
    }

    /// The same request as Settings' Health switch, which shares the key.
    private func connectHealth() {
        guard !isRequestingHealth else { return }
        isRequestingHealth = true
        Task {
            defer { isRequestingHealth = false }
            do {
                try await healthProvider.requestAuthorization()
                healthEnabled = true
            } catch {
                Self.logger.error("Health authorization failed: \(String(describing: type(of: error)), privacy: .public)")
            }
        }
    }

    private var actions: InsightsActions {
        InsightsActions(
            openHabit: { id in path.append(HabitRoute(id: id)) },
            openGoal: { id in path.append(GoalRoute(id: id)) },
            connectHealth: connectHealth,
            addHabitTemplate: { template in
                templateDraft = TemplateDraft(template: template, model: Self.formModel(for: template))
            }
        )
    }

    /// A New Habit form model prefilled from a template.
    private static func formModel(for template: InsightsHabitTemplate) -> NewHabitFormModel {
        let model = NewHabitFormModel()
        model.name = template.name
        model.icon = template.icon
        model.color = template.color
        return model
    }
}

#Preview("Empty") {
    NavigationStack {
        InsightsScreen(path: .constant(NavigationPath()), cache: OverviewCache())
            .navigationTitle("Overview")
    }
    .modelContainer(PreviewContainer.emptyContainer())
    .kadoTheme()
}

#Preview("Dark") {
    NavigationStack {
        InsightsScreen(path: .constant(NavigationPath()), cache: OverviewCache())
            .navigationTitle("Overview")
    }
    .modelContainer(PreviewContainer.shared)
    .kadoTheme()
    .preferredColorScheme(.dark)
}
