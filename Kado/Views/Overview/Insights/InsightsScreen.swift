import SwiftData
import SwiftUI
import KadoCore

/// The Overview tab's Insights mode: picks the period, gets a report
/// and hosts the feed. It also does what the cards ask for: pushes a
/// habit or a goal onto the Overview stack, and opens the New Habit
/// form from a template.
///
/// The report is empty for now. Wiring the store and Apple Health into
/// `InsightsCalculator` is a separate step. Under the UI suite's
/// `-uiTestInsightsFixture` it shows `InsightsPreviewData.rich`, so a
/// test sees every card filled.
struct InsightsScreen: View {
    @Binding var path: NavigationPath

    @Environment(\.calendar) private var calendar
    @Environment(\.today) private var today

    @AppStorage(OverviewModeDefaults.insightsPeriodKey) private var period: InsightsPeriod = .month

    /// The New Habit form opened from a template. Holds the form's
    /// model, so a re-render never resets what the user typed.
    @State private var templateDraft: TemplateDraft?

    struct TemplateDraft: Identifiable {
        let template: InsightsHabitTemplate
        let model: NewHabitFormModel
        var id: String { template.rawValue }
    }

    var body: some View {
        InsightsFeed(report: report, period: $period, actions: actions)
            .navigationDestination(for: HabitRoute.self) { route in
                HabitDetailLoader(habitID: route.id)
            }
            .navigationDestination(for: GoalRoute.self) { route in
                GoalDetailView(goalID: route.id)
            }
            .sheet(item: $templateDraft) { draft in
                NewHabitFormView(model: draft.model)
            }
    }

    /// What the feed shows. See the type comment.
    private var report: InsightsReport {
        if UITestSupport.showsInsightsFixture {
            return InsightsPreviewData.rich(for: period)
        }
        let days = InsightsScope.days(endingAt: today, count: period.dayCount, calendar: calendar)
        return InsightsReport(period: period, days: days)
    }

    private var actions: InsightsActions {
        InsightsActions(
            openHabit: { id in path.append(HabitRoute(id: id)) },
            openGoal: { id in path.append(GoalRoute(id: id)) },
            // Wired to the Apple Health opt-in when real data arrives.
            connectHealth: {},
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
        InsightsScreen(path: .constant(NavigationPath()))
            .navigationTitle("Overview")
    }
    .modelContainer(PreviewContainer.emptyContainer())
    .kadoTheme()
}

#Preview("Dark") {
    NavigationStack {
        InsightsScreen(path: .constant(NavigationPath()))
            .navigationTitle("Overview")
    }
    .modelContainer(PreviewContainer.shared)
    .kadoTheme()
    .preferredColorScheme(.dark)
}
