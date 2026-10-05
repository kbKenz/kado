import SwiftData
import SwiftUI
import KadoCore

/// The Overview tab. Owns the navigation stack and the title, and
/// switches between the Insights feed (`InsightsScreen`) and the
/// habits × days matrix (`OverviewGridView`), like Today's List /
/// Calendar switch. The choice is remembered across launches.
struct OverviewView: View {
    @AppStorage(OverviewModeDefaults.key) private var mode: OverviewMode = .insights
    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                switch mode {
                case .insights: InsightsScreen(path: $path)
                case .grid: OverviewGridView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.kadoBackground.ignoresSafeArea())
            .safeAreaInset(edge: .top, spacing: 0) {
                OverviewModePicker(mode: $mode)
            }
            .navigationTitle("Overview")
        }
    }
}

/// The Insights / Grid switch under the title.
private struct OverviewModePicker: View {
    @Binding var mode: OverviewMode

    var body: some View {
        Picker("View", selection: $mode) {
            Text("Insights").tag(OverviewMode.insights)
            Text("Grid").tag(OverviewMode.grid)
        }
        .pickerStyle(.segmented)
        // Capped so it doesn't stretch across an iPad.
        .frame(maxWidth: 400)
        .padding(.horizontal)
        .padding(.top, 4)
        .padding(.bottom, 6)
        .accessibilityIdentifier(AccessibilityID.Insights.modePicker)
        .frame(maxWidth: .infinity)
        .background(Color.kadoBackground, ignoresSafeAreaEdges: [])
    }
}

#Preview("Populated") {
    OverviewView()
        .modelContainer(PreviewContainer.shared)
}

#Preview("Dark") {
    OverviewView()
        .modelContainer(PreviewContainer.shared)
        .preferredColorScheme(.dark)
}
