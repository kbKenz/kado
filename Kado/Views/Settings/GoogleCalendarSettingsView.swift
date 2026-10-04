import GoogleSignInSwift
import KadoCore
import SwiftData
import SwiftUI

/// Optional account connection and truthful foreground sync status.
struct GoogleCalendarSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.googleCalendarConnection) private var connection
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage(DevModeDefaults.key, store: DevModeDefaults.sharedDefaults) private var isDevMode = false
    @State private var isWorking = false

    var body: some View {
        Form {
            connectionSection
            behaviorSection
            if let error = connection.errorMessage {
                Section("Sync problem") {
                    Text(verbatim: error)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("googleCalendar.error")
                }
            }
        }
        .navigationTitle("Google Calendar")
        .task {
            guard !isDevMode else { return }
            await connection.restoreAndSync(using: modelContext)
        }
    }

    private var connectionSection: some View {
        Section {
            if isDevMode {
                Label("Google Calendar is paused in Dev mode.", systemImage: "pause.circle")
            } else if !connection.isConfigured {
                Label("Google Calendar setup required", systemImage: "gearshape")
                Text("Add the app's Google OAuth configuration to enable account connection.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else if connection.isConnected {
                Label("Connected", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.tint)
                if let email = connection.email {
                    LabeledContent("Google account") { Text(verbatim: email) }
                }
                if let lastSync = connection.lastSync {
                    LabeledContent("Last sync") {
                        Text(lastSync, format: .dateTime.month(.abbreviated).day().hour().minute())
                    }
                }
                Button {
                    run { await connection.sync(using: modelContext) }
                } label: {
                    Label("Sync now", systemImage: "arrow.triangle.2.circlepath")
                }
                .disabled(isWorking || connection.isSyncing)
                .accessibilityIdentifier("googleCalendar.sync")

                Button("Disconnect", role: .destructive) { connection.disconnect() }
                    .disabled(isWorking || connection.isSyncing)
                    .accessibilityIdentifier("googleCalendar.disconnect")
            } else {
                GoogleSignInButton(scheme: colorScheme == .dark ? .dark : .light) {
                    run { await connection.connect(using: modelContext) }
                }
                .disabled(isWorking || connection.isSyncing)
                .accessibilityIdentifier("googleCalendar.connect")
            }
            if isWorking || connection.isSyncing {
                ProgressView("Syncing Google Calendar…")
            }
        } header: {
            Text("Connection")
        } footer: {
            Text("Disconnecting keeps imported tasks and their completion history. You can revoke app access in your Google Account.")
        }
    }

    private var behaviorSection: some View {
        Section("How sync works") {
            Label("Primary Google calendar", systemImage: "calendar")
            Text("Events from the past 30 days and next 180 days become tasks with planned time in Calendar.")
            Text("Sync runs when you open the app, every minute while it is active, or when you tap Sync now. New meetings appear after the next successful sync.")
            Text("Completing a task stays in this app. It does not change the Google event.")
            Text("Google event titles and times update imported tasks. Edit connected events in Google Calendar.")
            Text("Google manages sign-in and may collect authentication and service usage data.")
            Link("Google sign-in privacy", destination: URL(string: "https://developers.google.com/identity/sign-in/ios/app-privacy")!)
                .accessibilityIdentifier("googleCalendar.privacy")
        }
        .font(.subheadline)
    }

    private func run(_ action: @escaping @MainActor () async -> Void) {
        guard !isWorking, !connection.isSyncing else { return }
        isWorking = true
        Task { @MainActor in
            await action()
            isWorking = false
        }
    }
}

#Preview("Setup required") {
    NavigationStack { GoogleCalendarSettingsView() }
        .modelContainer(PreviewContainer.shared)
}

#Preview("Dark") {
    NavigationStack { GoogleCalendarSettingsView() }
        .modelContainer(PreviewContainer.shared)
        .preferredColorScheme(.dark)
}
