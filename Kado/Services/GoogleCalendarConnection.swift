import Foundation
import GoogleSignIn
import KadoCore
import Observation
import SwiftData
import SwiftUI
import UIKit

/// Optional Google account connection. The SDK owns OAuth credentials in
/// Keychain; only event content passes into the app's persistent store.
@MainActor
@Observable
final class GoogleCalendarConnection {
    private(set) var isConnected = false
    private(set) var isSyncing = false
    private(set) var email: String?
    private(set) var lastSync: Date?
    private(set) var errorMessage: String?
    private(set) var importedEventCount: Int?

    @ObservationIgnored private let client: any GoogleCalendarFetching
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let clientID: String?
    @ObservationIgnored private let allowsConnection: Bool
    @ObservationIgnored private var sessionGeneration = UUID()
    @ObservationIgnored private var lastForegroundAttempt: Date?

    private static let calendarID = "primary"
    private static let eventsScope = "https://www.googleapis.com/auth/calendar.events.readonly"

    /// Creating a connection does not restore an account or contact Google.
    /// Lifecycle integration calls `restoreAndSync` explicitly for the live store.
    init(
        client: any GoogleCalendarFetching = GoogleCalendarClient(),
        defaults: UserDefaults = .standard,
        bundle: Bundle = .main,
        allowsConnection: Bool = true
    ) {
        self.client = client
        self.defaults = defaults
        self.allowsConnection = allowsConnection
        let configuredID = bundle.object(forInfoDictionaryKey: "GIDClientID") as? String
        let urlTypes = bundle.object(forInfoDictionaryKey: "CFBundleURLTypes") as? [[String: Any]]
        let schemes = urlTypes?.flatMap { $0["CFBundleURLSchemes"] as? [String] ?? [] } ?? []
        let reversedID = configuredID?.split(separator: ".").reversed().joined(separator: ".")
        if let configuredID, let reversedID,
           configuredID.hasSuffix(".apps.googleusercontent.com"),
           !configuredID.contains("unconfigured"),
           schemes.contains(reversedID) {
            clientID = configuredID
        } else {
            clientID = nil
        }
    }

    var isConfigured: Bool { clientID != nil && allowsConnection }

    /// Call from SwiftUI `.onOpenURL` to finish the system-browser consent flow.
    @discardableResult
    func handle(_ url: URL) -> Bool {
        guard isConfigured else { return false }
        return GIDSignIn.sharedInstance.handle(url)
    }

    func connect(using context: ModelContext) async {
        guard !isSyncing, !Task.isCancelled,
              !DevModeDefaults.sharedDefaults.bool(forKey: DevModeDefaults.key) else { return }
        guard configureSDK() else {
            errorMessage = String(localized: "Google Calendar needs app configuration before connecting.")
            return
        }
        guard let presenter = Self.presentingViewController() else {
            errorMessage = String(localized: "Open Google Calendar settings again to connect.")
            return
        }
        isSyncing = true
        errorMessage = nil
        let generation = sessionGeneration
        defer { if generation == sessionGeneration { isSyncing = false } }
        do {
            let user: GIDGoogleUser
            if let currentUser = GIDSignIn.sharedInstance.currentUser {
                if currentUser.grantedScopes?.contains(Self.eventsScope) == true {
                    user = currentUser
                } else {
                    user = try await currentUser.addScopes([Self.eventsScope], presenting: presenter).user
                }
            } else {
                user = try await GIDSignIn.sharedInstance.signIn(
                    withPresenting: presenter,
                    hint: nil,
                    additionalScopes: [Self.eventsScope]
                ).user
            }
            guard generation == sessionGeneration, !Task.isCancelled else { return }
            try await importEvents(for: user, generation: generation, using: context)
        } catch {
            guard generation == sessionGeneration, !Task.isCancelled else { return }
            // Cancelling the consent sheet leaves the existing account untouched.
            let nsError = error as NSError
            if nsError.domain != kGIDSignInErrorDomain || nsError.code != -5 {
                errorMessage = error.localizedDescription
            }
        }
    }

    /// Automatic foreground refresh is throttled; manual sync always retries.
    /// An unconfigured or disconnected account causes no networking.
    func restoreAndSync(using context: ModelContext) async {
        guard !isSyncing, !Task.isCancelled,
              !DevModeDefaults.sharedDefaults.bool(forKey: DevModeDefaults.key),
              configureSDK() else { return }
        let now = Date.now
        if let lastForegroundAttempt, now.timeIntervalSince(lastForegroundAttempt) < 60 { return }
        lastForegroundAttempt = now
        let sdk = GIDSignIn.sharedInstance
        guard sdk.currentUser != nil || sdk.hasPreviousSignIn() else { return }
        isSyncing = true
        let generation = sessionGeneration
        defer { if generation == sessionGeneration { isSyncing = false } }
        do {
            let user: GIDGoogleUser
            if let currentUser = sdk.currentUser {
                user = currentUser
            } else {
                user = try await sdk.restorePreviousSignIn()
            }
            guard generation == sessionGeneration, !Task.isCancelled else { return }
            // Scope upgrades must be initiated by the user's Connect action.
            guard user.grantedScopes?.contains(Self.eventsScope) == true else {
                errorMessage = String(localized: "Connect again to allow Google Calendar access.")
                return
            }
            try await importEvents(for: user, generation: generation, using: context)
        } catch {
            guard generation == sessionGeneration, !Task.isCancelled else { return }
            errorMessage = error.localizedDescription
        }
    }

    func sync(using context: ModelContext) async {
        guard !isSyncing, !Task.isCancelled,
              !DevModeDefaults.sharedDefaults.bool(forKey: DevModeDefaults.key) else { return }
        guard configureSDK(), let user = GIDSignIn.sharedInstance.currentUser else {
            errorMessage = String(localized: "Connect Google Calendar to sync events.")
            return
        }
        isSyncing = true
        errorMessage = nil
        let generation = sessionGeneration
        defer { if generation == sessionGeneration { isSyncing = false } }
        do {
            try await importEvents(for: user, generation: generation, using: context)
        } catch {
            guard generation == sessionGeneration, !Task.isCancelled else { return }
            errorMessage = error.localizedDescription
        }
    }

    /// Removes local SDK credentials immediately. Existing imported tasks keep
    /// their history; Google authorization can be revoked in Google Account.
    func disconnect() {
        cancelPendingSync()
        GIDSignIn.sharedInstance.signOut()
        isConnected = false
        isSyncing = false
        email = nil
        lastSync = nil
        importedEventCount = nil
        errorMessage = nil
    }

    /// Invalidate an in-flight response before switching SwiftData containers.
    /// Credentials remain connected so leaving the demo store can sync again.
    func cancelPendingSync() {
        sessionGeneration = UUID()
        isSyncing = false
        lastForegroundAttempt = nil
    }

    private func configureSDK() -> Bool {
        guard isConfigured, let clientID else { return false }
        GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)
        return true
    }

    private func importEvents(
        for user: GIDGoogleUser,
        generation: UUID,
        using context: ModelContext
    ) async throws {
        guard generation == sessionGeneration, !Task.isCancelled,
              !DevModeDefaults.sharedDefaults.bool(forKey: DevModeDefaults.key) else { return }
        guard user.grantedScopes?.contains(Self.eventsScope) == true else {
            throw ConnectionError.missingScope
        }
        guard let accountID = user.userID, !accountID.isEmpty else {
            throw ConnectionError.missingAccount
        }
        isConnected = true
        email = user.profile?.email
        lastSync = defaults.object(forKey: lastSyncKey(accountID)) as? Date
        let refreshedUser = try await user.refreshTokensIfNeeded()
        guard generation == sessionGeneration,
              GIDSignIn.sharedInstance.currentUser?.userID == accountID,
              !DevModeDefaults.sharedDefaults.bool(forKey: DevModeDefaults.key),
              !Task.isCancelled else { return }
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        guard let pastDay = calendar.date(byAdding: .day, value: -30, to: today),
              let futureDay = calendar.date(byAdding: .day, value: 181, to: today) else {
            throw ConnectionError.invalidWindow
        }
        // Normalize again after day arithmetic: a DST day that begins
        // at 01:00 must not shift the other window edges to 01:00.
        let from = calendar.startOfDay(for: pastDay)
        let to = calendar.startOfDay(for: futureDay)
        let events = try await client.events(
            accessToken: refreshedUser.accessToken.tokenString,
            calendarID: Self.calendarID,
            from: from,
            to: to
        )
        // Disconnect or account replacement while a request is in flight must
        // never write its stale response into the current store.
        guard generation == sessionGeneration,
              GIDSignIn.sharedInstance.currentUser?.userID == accountID,
              !DevModeDefaults.sharedDefaults.bool(forKey: DevModeDefaults.key),
              !Task.isCancelled else { return }
        // Off the main actor: a 211-day window expands recurring events into
        // hundreds of rows, and this runs every minute while the app is open.
        // The importer saves through its own context; the UI context merges it.
        let container = context.container
        let calendarID = Self.calendarID
        let window = DateInterval(start: from, end: to)
        let count = try await Task.detached(priority: .utility) {
            try GoogleCalendarImporter().apply(
                events: events,
                accountID: accountID,
                calendarID: calendarID,
                window: window,
                in: container
            )
        }.value
        // The import itself can't be recalled, but a disconnect or store swap
        // made while it ran must not see its status come back.
        guard generation == sessionGeneration else { return }
        importedEventCount = count
        lastSync = .now
        defaults.set(lastSync, forKey: lastSyncKey(accountID))
        errorMessage = nil
    }

    private func lastSyncKey(_ accountID: String) -> String {
        "kado.googleCalendar.lastSync.\(accountID)"
    }

    private static func presentingViewController() -> UIViewController? {
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
        guard var controller = scene?.windows.first(where: \.isKeyWindow)?.rootViewController else {
            return nil
        }
        while let presented = controller.presentedViewController { controller = presented }
        return controller
    }

    private enum ConnectionError: LocalizedError {
        case missingScope, missingAccount, invalidWindow

        var errorDescription: String? {
            switch self {
            case .missingScope:
                return String(localized: "Connect again to allow Google Calendar access.")
            case .missingAccount:
                return String(localized: "Google did not return an account. Connect again.")
            case .invalidWindow:
                return String(localized: "Could not determine the calendar sync dates.")
            }
        }
    }
}

extension EnvironmentValues {
    /// The app injects one connection for its scene. The default never restores
    /// credentials, so previews that omit injection make no network calls.
    @Entry var googleCalendarConnection = GoogleCalendarConnection(allowsConnection: false)
}
