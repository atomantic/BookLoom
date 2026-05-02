import Foundation

/// Compile-time feature flags. These gate code paths that are not yet ready
/// to ship — including any code that touches `CKContainer(identifier:)`,
/// which hard-traps in signed builds when the container isn't fully set up
/// on Apple's portal + CloudKit Console.
enum Features {
    /// Gates the iCloud-share-based book-club collaboration flow.
    /// While `false`:
    ///   - The "Invite Members" UI shows a "Coming soon" placeholder.
    ///   - `CloudKitSharingService` is never instantiated (singleton stays
    ///     un-touched), so `CKContainer(identifier:)` is never called.
    ///
    /// Prerequisites before flipping to `true`:
    ///   1. developer.apple.com → App ID `net.shadowpuppet.PlotLoom` →
    ///      enable iCloud capability → register container
    ///      `iCloud.net.shadowpuppet.PlotLoom`.
    ///   2. icloud.developer.apple.com → open container → push records from
    ///      a development build to auto-create the schema → click
    ///      "Deploy Schema Changes…" to promote it to Production.
    ///   3. Re-archive (automatic signing refreshes the provisioning profile
    ///      with the new entitlement).
    ///   4. Smoke-test in TestFlight on two different Apple IDs.
    static let cloudKitSharing: Bool = true
}
