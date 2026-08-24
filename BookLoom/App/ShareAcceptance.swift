import Foundation
import CloudKit
import SwiftData
import SwiftUI
import os

/// Magic strings used when iOS/macOS deliver a CKShare invite via NSUserActivity.
/// These constants are NOT exposed by Apple's SDK — older sample code references
/// `CKShare.Metadata.activityType` which doesn't exist. Hardcode them.
enum ShareAcceptance {
    static let activityType = "com.apple.CloudKit.ShareMetadata"
    static let metadataKey = "CKShareMetadata"

    private static let logger = Logger(subsystem: "net.shadowpuppet.BookLoom", category: "ShareAccept")

    /// Extract metadata from a `NSUserActivity` payload (used by SwiftUI's
    /// `onContinueUserActivity` modifier).
    static func metadata(from activity: NSUserActivity) -> CKShare.Metadata? {
        activity.userInfo?[metadataKey] as? CKShare.Metadata
    }

    /// Accept an incoming CKShare and insert a local `BookClub` row that
    /// represents the joined club. Idempotent — re-accepting the same share
    /// for an already-joined club won't duplicate the row.
    @MainActor
    static func handleAccept(
        metadata: CKShare.Metadata,
        context: ModelContext,
        localMemberID: String,
        localMemberName: String
    ) async {
        guard Features.cloudKitSharing else {
            logger.info("⏭ Share accept ignored — Features.cloudKitSharing is off")
            return
        }
        do {
            let info = try await CloudKitSharingService.shared.acceptShare(metadata: metadata)

            let zoneName = info.zoneName
            let descriptor = FetchDescriptor<BookClub>(
                predicate: #Predicate { $0.cloudZoneName == zoneName }
            )
            let existing = (try? context.fetch(descriptor)) ?? []
            let joined: BookClub
            if let existingClub = existing.first {
                joined = existingClub
                logger.info("↺ Share accept matched existing zone \(info.zoneName, privacy: .public)")
            } else {
                joined = BookClub(name: info.title)
                joined.cloudZoneName = info.zoneName
                context.insert(joined)
            }

            joined.ownerUserRecordName = info.ownerUserRecordName
            joined.shareIsActive = true
            joined.shareParticipantCount = max(1, info.participantCount)

            let authorization = MemberSnapshotAuthorization.authorize(
                info.memberSnapshotBatch,
                existingBindings: joined.memberIdentityBindings,
                isShareOwner: false
            )
            joined.memberIdentityBindings = bindingsAfterAuthorization(
                existing: joined.memberIdentityBindings,
                authorization: authorization
            )

            if authorization.isTrustEstablished,
               authorization.rejectedRecordNames.isEmpty,
               !authorization.snapshots.isEmpty {
                try MemberShareSnapshotStore.merge(
                    snapshots: authorization.snapshots,
                    into: joined,
                    context: context,
                    localMemberID: localMemberID
                )
                try context.save()
                logger.info("✅ Accepted share — imported '\(joined.name, privacy: .public)' from \(authorization.snapshots.count) authenticated member snapshot(s)")
            } else {
                try context.save()
                logger.info("✅ Accepted share — joined '\(info.title, privacy: .public)' (zone \(info.zoneName, privacy: .public))")
                // Owner published the share root *after* `acceptShare` returned —
                // give CloudKit a beat to materialize the shared zone before
                // `fetchMemberSnapshotBatch` makes its query. Without this, the
                // first refresh returns no results and the joined club stays
                // empty until the user pulls to refresh.
                try? await Task.sleep(for: .seconds(1))
                await SharedClubSync.refreshIfNeeded(
                    joined,
                    context: context,
                    localMemberID: localMemberID,
                    localMemberName: localMemberName
                )
            }

            // Publish the joining member's empty snapshot so the owner gets
            // a push notification announcing the new participant and a
            // record they can fetch.
            SharedClubSync.publishIfNeeded(
                joined,
                context: context,
                localMemberID: localMemberID,
                localMemberName: localMemberName
            )
        } catch {
            logger.error("⚠️ Share accept failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// A just-accepted share may not have materialized its owner record yet.
    /// Preserve a previously authenticated map on re-accept instead of replacing
    /// it with the fail-closed empty result from an inconclusive fetch.
    static func bindingsAfterAuthorization(
        existing: [String: String],
        authorization: MemberSnapshotAuthorizationResult
    ) -> [String: String] {
        authorization.isTrustEstablished ? authorization.bindings : existing
    }
}
