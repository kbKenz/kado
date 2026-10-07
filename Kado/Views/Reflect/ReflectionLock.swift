import LocalAuthentication
import SwiftUI
import KadoCore

/// Face ID (or the device passcode) in front of the reflections.
enum ReflectionLock {
    /// False when the device has no passcode, so it cannot lock.
    static var isAvailable: Bool {
        var error: NSError?
        return LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: &error)
    }

    /// Asks the user to authenticate. True on success.
    static func authenticate() async -> Bool {
        let context = LAContext()
        let reason = String(localized: "Unlock your reflections.", comment: "Face ID prompt reason for the Reflect section.")
        return (try? await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)) ?? false
    }
}

/// Shown instead of the reflections while they are locked.
struct ReflectionLockedView: View {
    let onUnlock: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label("Reflections are locked", systemImage: "lock.fill")
        } description: {
            Text("Unlock with Face ID or your passcode to read them.")
        } actions: {
            Button("Unlock", action: onUnlock)
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier(AccessibilityID.Reflect.unlock)
        }
    }
}

#Preview("Locked") {
    ReflectionLockedView(onUnlock: {})
        .background(Color.kadoBackground)
}

#Preview("Locked, Dark") {
    ReflectionLockedView(onUnlock: {})
        .background(Color.kadoBackground)
        .preferredColorScheme(.dark)
}
