import LocalAuthentication
import Observation
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

/// Whether reflections are locked right now, for every screen that
/// shows them: Reflect, a month, a question's history and the check-in,
/// however it was opened. App-wide, so leaving the app relocks all of
/// them at once (`ContentView` calls `relock()`).
@MainActor
@Observable
final class ReflectionLockState {
    static let shared = ReflectionLockState()

    /// The setting. Changed only through `enable()` and `disable()`,
    /// which both ask for Face ID first.
    private(set) var isEnabled: Bool
    private var isUnlocked = false

    private init() {
        isEnabled = UserDefaults.standard.bool(forKey: ReflectionDefaults.lockKey)
    }

    /// UI runs never lock: a test cannot pass Face ID.
    var isLocked: Bool { isEnabled && !isUnlocked && !UITestSupport.isRunningUITests }

    func relock() {
        isUnlocked = false
    }

    func unlock() async {
        if await ReflectionLock.authenticate() { isUnlocked = true }
    }

    /// Turns the lock on after a successful authentication, which also
    /// proves the user can open it again. False when the device cannot
    /// lock (no passcode).
    func enable() async -> Bool {
        guard ReflectionLock.isAvailable else { return false }
        guard await ReflectionLock.authenticate() else { return true }
        setEnabled(true)
        isUnlocked = true
        return true
    }

    /// Turns the lock off, only for someone who can open it.
    func disable() async {
        guard await ReflectionLock.authenticate() else { return }
        setEnabled(false)
    }

    private func setEnabled(_ on: Bool) {
        isEnabled = on
        UserDefaults.standard.set(on, forKey: ReflectionDefaults.lockKey)
    }
}

extension View {
    /// Covers the view with the locked screen while reflections are
    /// locked. A cover, not a swap: a check-in keeps its unsaved text
    /// underneath, and the app-switcher snapshot shows only the cover.
    func reflectionLockGate() -> some View {
        modifier(ReflectionLockGate())
    }
}

private struct ReflectionLockGate: ViewModifier {
    private var lock: ReflectionLockState { .shared }

    func body(content: Content) -> some View {
        let locked = lock.isLocked
        content
            .accessibilityHidden(locked)
            .overlay {
                if locked {
                    ReflectionLockedView { Task { await lock.unlock() } }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.kadoBackground.ignoresSafeArea())
                }
            }
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
