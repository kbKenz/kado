import SwiftData
import SwiftUI
import KadoCore

/// Root view of the app. Hosts the primary TabView shell.
///
/// Now shows the current work; Today combines habits and tasks, with a
/// calendar view of the same day; Overview keeps the habit matrix.
struct ContentView: View {
    @State private var selection: AppTab = UITestSupport.initialTab
    /// The check-in a reminder tap asked for, presented over any tab.
    @State private var routedCheckIn: RoutedCheckIn?
    @Environment(\.scenePhase) private var scenePhase
    private var router: AppRouter { AppRouter.shared }

    private struct RoutedCheckIn: Identifiable {
        let month: ReflectionMonth
        var id: Int { month.id }
    }

    var body: some View {
        // Deliberately no `.accessibilityIdentifier` on these tabs: one
        // on a tab's content would stamp every element in the screen
        // beneath it, and one on its label never reaches the tab bar
        // button. The UI suite addresses tabs by position instead — see
        // `AccessibilityID.Tab`, and keep the order here in step with it.
        TabView(selection: $selection) {
            Tab("Now", systemImage: "clock", value: AppTab.now) {
                NowView()
            }
            Tab("Today", systemImage: "list.bullet.clipboard", value: AppTab.today) {
                TodayView()
            }
            Tab("Goals", systemImage: "scope", value: AppTab.goals) {
                GoalsView()
            }
            Tab("Overview", systemImage: "square.grid.2x2", value: AppTab.overview) {
                OverviewView()
            }
            Tab("Settings", systemImage: "gearshape", value: AppTab.settings) {
                SettingsView()
            }
        }
        // The monthly reminder opens its check-in where the user is. A
        // tap that launched the app set the request before this view
        // watched it, so it is also taken on appear.
        .onChange(of: router.checkInRequest) { _, _ in takeCheckInRequest() }
        .onAppear(perform: takeCheckInRequest)
        .fullScreenCover(item: $routedCheckIn) { routed in
            ReflectionCheckInView(month: routed.month)
        }
        // Leaving the app, even for the app switcher, locks reflections
        // again on every screen that shows them.
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { ReflectionLockState.shared.relock() }
        }
        .kadoTheme()
        .reviewPromptOnForeground()
        .dayCompletionCelebration()
    }
}

extension ContentView {
    private func takeCheckInRequest() {
        guard let month = router.checkInRequest, routedCheckIn == nil else { return }
        router.checkInRequest = nil
        routedCheckIn = RoutedCheckIn(month: month)
    }
}

#Preview {
    ContentView()
        .modelContainer(PreviewContainer.shared)
}

#Preview("Dark") {
    ContentView()
        .modelContainer(PreviewContainer.shared)
        .preferredColorScheme(.dark)
}
