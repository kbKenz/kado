import SwiftData
import SwiftUI

/// The Overview tab. Owns the navigation stack and the title; the
/// habits × days matrix is `OverviewGridView`.
struct OverviewView: View {
    var body: some View {
        NavigationStack {
            OverviewGridView()
                .navigationTitle("Overview")
        }
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
