import SwiftData
import SwiftUI
import KadoCore

/// Root view of the app. Hosts the primary TabView shell.
///
/// Today combines habits and tasks; Calendar plans tasks on a day
/// timeline while Overview retains the habit history matrix.
struct ContentView: View {
    var body: some View {
        // Deliberately no `.accessibilityIdentifier` on these tabs: one
        // on a tab's content would stamp every element in the screen
        // beneath it, and one on its label never reaches the tab bar
        // button. The UI suite addresses tabs by position instead — see
        // `AccessibilityID.Tab`, and keep the order here in step with it.
        TabView {
            Tab("Today", systemImage: "list.bullet.clipboard") {
                TodayView()
            }
            Tab("Calendar", systemImage: "calendar") {
                PlannerCalendarView()
            }
            Tab("Goals", systemImage: "scope") {
                GoalsView()
            }
            Tab("Overview", systemImage: "square.grid.2x2") {
                OverviewView()
            }
            Tab("Settings", systemImage: "gearshape") {
                SettingsView()
            }
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
