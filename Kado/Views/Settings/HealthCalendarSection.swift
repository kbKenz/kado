import KadoCore
import OSLog
import SwiftUI

/// Opt-in for the Calendar's Health overlay, which also feeds the
/// Insights Sleep and Movement cards. HealthKit never reports a denied
/// read, so the footer tells the user where to check instead of the app
/// guessing at an error.
struct HealthCalendarSection: View {
    @Environment(\.healthTimelineProvider) private var provider
    @Environment(\.openURL) private var openURL
    @AppStorage(HealthCalendarDefaults.key) private var showsHealth = false
    @State private var isRequesting = false

    var body: some View {
        if provider.isAvailable {
            Section {
                Toggle(isOn: toggleBinding) {
                    HStack {
                        Label("Health on Calendar", systemImage: "heart.text.square")
                        if isRequesting { ProgressView() }
                    }
                }
                .disabled(isRequesting)
                .accessibilityIdentifier(AccessibilityID.Settings.healthOnCalendarToggle)
                if showsHealth {
                    // Undocumented but long-stable scheme; a failure
                    // simply does nothing, and the footer still guides.
                    Button {
                        if let url = URL(string: "x-apple-health://") { openURL(url) }
                    } label: {
                        Label("Open Health", systemImage: "arrow.up.right.square")
                    }
                }
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    if showsHealth {
                        Text("No data showing? Check Settings → Privacy & Security → Health → Kadō.")
                    } else {
                        Text("Show your sleep and workouts on the Calendar. Read-only, and the data stays on your device.")
                    }
                    Text("Sleep and workouts also appear in Insights.")
                }
            }
            .listRowBackground(Color.kadoBackgroundSecondary)
        }
    }

    /// The disabling flag is set synchronously before the Task, so two
    /// taps in one runloop tick cannot both request.
    private var toggleBinding: Binding<Bool> {
        Binding(
            get: { showsHealth || isRequesting },
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
                        Logger.healthCalendar.error("Health authorization failed: \(String(describing: type(of: error)), privacy: .public)")
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
