import Observation

/// Status observer for builds without iCloud (``CloudSync/isEnabled``
/// is false). Reports `.disabledInBuild` and never touches CloudKit.
@MainActor
@Observable
final class DisabledCloudAccountStatusObserver: CloudAccountStatusObserving {
    let status: CloudAccountStatus = .disabledInBuild
    let syncHealth: CloudSyncHealth = .unknown

    func refresh() async {}
}
