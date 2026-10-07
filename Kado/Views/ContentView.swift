import SwiftData
import SwiftUI
import KadoCore

/// Root view of the app. Hosts the primary TabView shell.
///
/// Now shows the current work; Today combines habits and tasks, with a
/// calendar view of the same day; Overview keeps the habit matrix.
struct ContentView: View {
    @State private var selection: AppTab = UITestSupport.initialTab
    private var router: AppRouter { AppRouter.shared }

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
        // The monthly reminder opens Overview's Reflect section, which
        // then takes the request and opens the check-in.
        .onChange(of: router.checkInRequest) { _, month in
            guard month != nil else { return }
            UserDefaults.standard.set(OverviewMode.reflect.rawValue, forKey: OverviewModeDefaults.key)
            selection = .overview
        }
        .kadoTheme()
        .reviewPromptOnForeground()
        .dayCompletionCelebration()
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
