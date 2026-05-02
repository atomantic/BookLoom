import Foundation
import CloudKit
import os

/// Owns the CKShare invite handshake. SwiftData (`cloudKitDatabase: .automatic`)
/// already replicates `BookClub` and its descendants across the user's own
/// devices; this service overlays a `CKShare` so users on **different Apple
/// IDs** can join the same club.
///
/// This service creates the inviteable share root. SwiftData's `.automatic`
/// CloudKit mode still primarily handles private-database sync, so a signed
/// two-account TestFlight smoke test must verify whether club mutations
/// actually propagate across participants before calling collaboration done.
///
/// ⚠️ This file references `CKContainer(identifier:)`, which traps at runtime
/// in signed builds if the container isn't registered on the developer portal
/// AND deployed to Production in CloudKit Console. All callers must check
/// `Features.cloudKitSharing` first. The singleton is fine to import — it only
/// touches the container lazily.
@MainActor
final class CloudKitSharingService {
    static let shared = CloudKitSharingService()

    private static let containerID = "iCloud.net.shadowpuppet.PlotLoom"
    private static let logger = Logger(subsystem: "net.shadowpuppet.PlotLoom", category: "CloudKitSharing")
    /// Custom record type for the share root. NEVER prefix with `_` — that's
    /// a CloudKit-reserved namespace and `modifyRecords` will reject it.
    private static let rootRecordType = "BookClubShareRoot"

    /// Lazy so we never construct a CKContainer until a code path that has
    /// already passed the `Features.cloudKitSharing` gate calls a method.
    private lazy var container: CKContainer = CKContainer(identifier: Self.containerID)
    private var privateDB: CKDatabase { container.privateCloudDatabase }
    private var sharedDB: CKDatabase { container.sharedCloudDatabase }

    private init() {}

    // MARK: - Owner-side: create or fetch share

    /// Creates (or returns the existing) CKShare for `club`. The share URL
    /// can then be surfaced via `UICloudSharingController` (iOS) or copied to
    /// the pasteboard (macOS). Re-runs are idempotent — calling twice returns
    /// the same share.
    func createOrFetchShare(for club: BookClub) async throws -> CKShare {
        guard Features.cloudKitSharing else {
            throw SharingError.featureDisabled
        }

        // Backfill a zone name if this BookClub was created before the field
        // existed (or somehow ended up empty).
        if club.cloudZoneName.isEmpty {
            club.cloudZoneName = "BookClub-\(UUID().uuidString)"
        }

        let zone = CKRecordZone(zoneName: club.cloudZoneName)
        try await ensureZoneExists(zone)

        let rootID = CKRecord.ID(recordName: "ShareRoot", zoneID: zone.zoneID)

        // Reuse existing share by following root.share, not by guessing the
        // share record ID.
        if let existingRoot = try? await privateDB.record(for: rootID),
           let shareReference = existingRoot.share,
           let existingShareRecord = try? await privateDB.record(for: shareReference.recordID),
           let existingShare = existingShareRecord as? CKShare {
            club.shareIsActive = true
            club.shareParticipantCount = existingShare.participants.count
            return existingShare
        }

        // First-time: save root + share atomically. CloudKit rejects saving a
        // share without its root in the same modifyRecords call.
        let rootRecord = CKRecord(recordType: Self.rootRecordType, recordID: rootID)
        rootRecord["clubName"] = club.name as CKRecordValue

        let share = CKShare(rootRecord: rootRecord)
        share[CKShare.SystemFieldKey.title] = "Book Club: \(club.name)" as CKRecordValue
        share.publicPermission = .none

        let result = try await privateDB.modifyRecords(
            saving: [rootRecord, share],
            deleting: []
        )
        // Some OS releases return only the root record in saveResults even
        // though the CKShare save succeeded. When the resolver falls back to
        // our locally-built share, hydrate it from the database; when CloudKit
        // gave us the saved share directly, skip the extra round-trip.
        let resolution = try ShareSaveResultResolver.resolve(
            saveResults: result.saveResults,
            fallback: share
        )
        let finalShare: CKShare
        if resolution.needsHydration {
            finalShare = (try? await privateDB.record(for: resolution.share.recordID) as? CKShare) ?? resolution.share
        } else {
            finalShare = resolution.share
        }

        club.shareIsActive = true
        club.shareParticipantCount = finalShare.participants.count
        Self.logger.info("✅ Created share for club '\(club.name, privacy: .public)' (zone \(club.cloudZoneName, privacy: .public))")
        return finalShare
    }

    // MARK: - Member-side: accept share

    /// Accepts an incoming CKShare. Caller is responsible for resolving the
    /// metadata into a SwiftData `BookClub` row (typically: insert one with
    /// the share's title and `ownerUserRecordName` set).
    func acceptShare(metadata: CKShare.Metadata) async throws -> AcceptedShareInfo {
        guard Features.cloudKitSharing else {
            throw SharingError.featureDisabled
        }
        // Discard the return — the compiler warns if it's ignored implicitly.
        _ = try await container.accept([metadata])
        let title = metadata.share[CKShare.SystemFieldKey.title] as? String ?? "Shared Book Club"
        return AcceptedShareInfo(
            zoneName: metadata.share.recordID.zoneID.zoneName,
            ownerUserRecordName: metadata.share.recordID.zoneID.ownerName,
            title: title
        )
    }

    func cloudKitContainer() -> CKContainer {
        container
    }

    // MARK: - Private helpers

    private func ensureZoneExists(_ zone: CKRecordZone) async throws {
        let existing = try await privateDB.allRecordZones()
        if existing.contains(where: { $0.zoneID.zoneName == zone.zoneID.zoneName }) {
            return
        }
        _ = try await privateDB.modifyRecordZones(saving: [zone], deleting: [])
    }
}

struct AcceptedShareInfo: Sendable {
    let zoneName: String
    let ownerUserRecordName: String
    let title: String
}

enum SharingError: LocalizedError {
    case featureDisabled
    case shareCreationFailed

    var errorDescription: String? {
        switch self {
        case .featureDisabled:
            return "iCloud sharing isn't available in this build yet."
        case .shareCreationFailed:
            return "Couldn't create the share. Please try again."
        }
    }
}

enum ShareSaveResultResolver {
    struct Resolution {
        let share: CKShare
        /// True when the share was reconstructed from the local fallback (not
        /// returned in saveResults) and should be re-fetched from the database.
        let needsHydration: Bool
    }

    static func resolve(
        saveResults: [CKRecord.ID: Result<CKRecord, Error>],
        fallback: CKShare
    ) throws -> Resolution {
        for result in saveResults.values {
            if case .success(let record) = result, let share = record as? CKShare {
                return Resolution(share: share, needsHydration: false)
            }
        }

        for result in saveResults.values {
            if case .failure(let error) = result {
                throw error
            }
        }

        return Resolution(share: fallback, needsHydration: true)
    }
}
