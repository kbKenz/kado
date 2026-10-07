import Foundation
import Observation
import KadoCore

/// Requests to show a place in the app from outside the view tree: a
/// notification tap. `ContentView` switches tabs; the screen that owns
/// the destination takes the request and clears it.
@MainActor
@Observable
final class AppRouter {
    static let shared = AppRouter()

    /// The check-in to open, from the monthly reminder.
    var checkInRequest: ReflectionMonth?

    func openCheckIn(for month: ReflectionMonth) {
        checkInRequest = month
    }
}
