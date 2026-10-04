import Foundation

/// Whether this build syncs through iCloud (CloudKit).
///
/// Off for builds signed with a free Personal Team, which cannot carry
/// the iCloud or Push Notifications entitlements. Without those
/// entitlements, opening the store with a CloudKit configuration or
/// creating a `CKContainer` traps at launch, so both paths check this
/// flag. To turn sync back on with a paid team: set this to `true` and
/// restore the iCloud (CloudKit, `CloudContainerID.kado`) and
/// `aps-environment` entitlements in both `.entitlements` files.
nonisolated public enum CloudSync {
    public static let isEnabled = false
}
