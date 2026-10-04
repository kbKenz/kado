import KadoCore
import OSLog
import SwiftUI

/// Opt-in for the Calendar's Health overlay. HealthKit never reports
/// a denied read, so the footer tells the user where to check instead
/// of the app guessing at an error.
struct HealthCalendarSection: View {
    @Environment(\.healthTimelineProvider) private var provider
    @Environment(\.openURL) private var openURL
    @AppStorage(HealthCalendarDefaults.key) private var showsHealth = false
    @State private var isRequesting = false

    private static let logger = Logger(subsystem: "dev.scastiel.kado", category: "health-calendar")

    var body: some View {
        if provider.isAvailable {
            Section {
                Toggle(isOn: toggleBinding) {
                    Label("Health on Calendar", systemImage: "heart.text.square")
                }
                .disabled(isRequesting)
                .accessibilityIdentifier(AccessibilityID.Settings.healthOnCalendarToggle)
                if showsHealth {
                    Button("Open Health") {
                        // Undocumented but long-stable scheme; a failure
                        // simply does nothing, and the footer still guides.
                        if let url = URL(string: "x-apple-health://") { openURL(url) }
                    }
                }
            } footer: {
                if showsHealth {
                    Text("No data showing? Check Settings → Health → Data Access & Devices → Kadō.")
                } else {
                    Text("Show your sleep and workouts on the Calendar. Read-only, and the data stays on your device.")
                }
            }
            .listRowBackground(Color.kadoBackgroundSecondary)
        }
    }

    /// The disabling flag is set synchronously before the Task, so two
    /// taps in one runloop tick cannot both request.
    private var toggleBinding: Binding<Bool> {
        Binding(
            get: { showsHealth },
            set: { isOn in
                guard isOn else { showsHealth = false; return }
                guard !isRequesting else { return }
                isRequesting = true
                Task {
                    defer { isRequesting = false }
                    do {
                        try await provider.requestAuthorization()
                        showsHealth = true
                    } catch {
                        Self.logger.error("Health authorization failed: \(String(describing: type(of: error)), privacy: .public)")
                        showsHealth = false
                    }
                }
            }
        )
    }
}

#Preview("Off") {
    Form { HealthCalendarSection() }
        .environment(\.healthTimelineProvider, PreviewHealthTimelineProvider())
        .kadoTheme()
}

#Preview("Dark") {
    Form { HealthCalendarSection() }
        .environment(\.healthTimelineProvider, PreviewHealthTimelineProvider())
        .kadoTheme()
        .preferredColorScheme(.dark)
}

#Preview("Unavailable") {
    Form { HealthCalendarSection() }
        .environment(\.healthTimelineProvider, PreviewHealthTimelineProvider(isAvailable: false))
        .kadoTheme()
}
