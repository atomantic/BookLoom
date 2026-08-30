import Foundation
import CloudKit
import os
import SwiftData

struct MemberSnapshotQueryPage {
    let records: [Result<CKRecord, Error>]
    let hasMore: Bool
}

/// Narrow CloudKit query seam. Keeping pagination and per-record failures in
/// the result lets tests prove that an incomplete snapshot set is discarded.
@MainActor
protocol MemberSnapshotQuerying {
    func firstPage(recordType: String, zoneID: CKRecordZone.ID) async throws -> MemberSnapshotQueryPage
    func nextPage() async throws -> MemberSnapshotQueryPage
}

@MainActor
private final class CloudKitMemberSnapshotQuery: MemberSnapshotQuerying {
    let database: CKDatabase
    private var cursor: CKQueryOperation.Cursor?

    init(database: CKDatabase) {
        self.database = database
    }

    func firstPage(recordType: String, zoneID: CKRecordZone.ID) async throws -> MemberSnapshotQueryPage {
        let query = CKQuery(recordType: recordType, predicate: NSPredicate(value: true))
        let result = try await database.records(matching: query, inZoneWith: zoneID)
        cursor = result.queryCursor
        return MemberSnapshotQueryPage(
            records: result.matchResults.map(\.1),
            hasMore: cursor != nil
        )
    }

    func nextPage() async throws -> MemberSnapshotQueryPage {
        guard let cursor else {
            return MemberSnapshotQueryPage(records: [], hasMore: false)
        }
        let result = try await database.records(continuingMatchFrom: cursor)
        self.cursor = result.queryCursor
        return MemberSnapshotQueryPage(
            records: result.matchResults.map(\.1),
            hasMore: self.cursor != nil
        )
    }
}

@MainActor
protocol MemberSnapshotSyncing: AnyObject {
    func publishMemberSnapshot(_ snapshot: MemberShareSnapshot, target: MemberSnapshotSyncTarget, localMemberID: String) async throws
    func fetchMemberSnapshotBatch(target: MemberSnapshotSyncTarget) async throws -> MemberSnapshotBatch
    func fetchAcceptedParticipantCount(target: MemberSnapshotSyncTarget) async throws -> Int
}

struct MemberSnapshotSyncTarget: Equatable {
    let zoneName: String
    let ownerUserRecordName: String?
    let isShareOwner: Bool
    let participantCount: Int

    var isOwner: Bool { ownerUserRecordName == nil }

    @MainActor
    init(_ club: BookClub) {
        zoneName = club.cloudZoneName
        ownerUserRecordName = club.ownerUserRecordName
        isShareOwner = club.isShareOwner
        participantCount = club.shareParticipantCount
    }
}

/// Owns the CKShare invite handshake AND the per-author snapshot read/write
/// loop. The collaboration model:
///
/// - The shared zone holds one `BookClubShareRoot` record per club, which is
///   the share anchor and carries the owner's club metadata (name, createdAt).
/// - Each participant (including the owner) writes one `MemberShareSnapshot`
///   record into the shared zone, named `MemberSnapshot-<memberID>`. That
///   record contains a JSON `MemberShareSnapshot` of *only* that member's
///   contributions (their own submissions, ratings, notes, votes, RSVPs, plus
///   any status overrides they performed).
/// - All clients fetch every `MemberShareSnapshot` record in the zone and
///   merge them locally — no participant ever writes another participant's
///   record, so there are no merge conflicts.
///
/// SwiftData (`cloudKitDatabase: .automatic`) still replicates the local
/// store across the user's own devices via their private CloudKit DB. The
/// CKShare layer is purely for cross-Apple-ID collaboration and now flows
/// bidirectionally.
///
/// ⚠️ This file references `CKContainer(identifier:)`, which traps at runtime
/// in signed builds if the container isn't registered on the developer portal
/// AND deployed to Production in CloudKit Console. All callers must check
/// `Features.cloudKitSharing` first. The singleton is fine to import — it only
/// touches the container lazily.
@MainActor
final class CloudKitSharingService: MemberSnapshotSyncing {
    static let shared = CloudKitSharingService()

    private static let logger = Logger(subsystem: "net.shadowpuppet.BookLoom", category: "CloudKitSharing")
    /// Custom record type for the share root. NEVER prefix with `_` — that's
    /// a CloudKit-reserved namespace and `modifyRecords` will reject it.
    static let rootRecordType = "BookClubShareRoot"
    static let memberSnapshotRecordType = "MemberShareSnapshot"
    private static let rootRecordName = "ShareRoot"
    private static let memberRecordPrefix = "MemberSnapshot-"
    private static let clubNameKey = "clubName"
    private static let clubCreatedAtKey = "clubCreatedAt"
    private static let snapshotDataKey = "snapshotData"
    private static let snapshotUpdatedAtKey = "snapshotUpdatedAt"
    private static let memberIDKey = "memberID"
    private static let memberNameKey = "memberName"
    /// Snapshot payload cap, held a comfortable margin below CloudKit's hard
    /// 1 MB (1024 * 1024) per-record limit so the encoded record — which also
    /// carries metadata fields and CloudKit's own overhead — stays under it.
    private static let maxSnapshotBytes = 900 * 1024

    /// Lazy so we never construct a CKContainer until a code path that has
    /// already passed the `Features.cloudKitSharing` gate calls a method.
    private lazy var container = CKContainer(identifier: BookLoomCloudKit.containerIdentifier)
    private var privateDB: CKDatabase { container.privateCloudDatabase }
    private var sharedDB: CKDatabase { container.sharedCloudDatabase }

    private let queryFactory: @MainActor (CKDatabase) -> any MemberSnapshotQuerying

    private init(
        queryFactory: @escaping @MainActor (CKDatabase) -> any MemberSnapshotQuerying = { CloudKitMemberSnapshotQuery(database: $0) }
    ) {
        self.queryFactory = queryFactory
    }

    // MARK: - Owner-side: create or fetch share

    /// Creates (or returns the existing) CKShare for `club`. The share URL
    /// can then be surfaced through the platform's private-recipient sharing
    /// UI. Re-runs are idempotent — calling twice returns the same share.
    func createOrFetchShare(for club: BookClub, context: ModelContext, ownerMemberID: String, ownerName: String) async throws -> CKShare {
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

        let rootID = CKRecord.ID(recordName: Self.rootRecordName, zoneID: zone.zoneID)
        let rootRecord: CKRecord

        // Reuse an existing root record when a prior build created one but
        // failed before surfacing the share. Re-inserting the same root ID
        // causes CloudKit to reject the save on later invite attempts.
        if let existingRoot = try? await privateDB.record(for: rootID) {
            rootRecord = existingRoot
            applyClubMeta(to: rootRecord, club: club)
            if let existingShare = try await existingShare(for: existingRoot) {
                try await saveRootRecord(rootRecord, in: privateDB)
                markShareActive(existingShare, for: club)
                try await publishOwnerMemberSnapshot(for: club, context: context, ownerMemberID: ownerMemberID, ownerName: ownerName, parentRootID: rootID)
                return existingShare
            }
        } else {
            rootRecord = CKRecord(recordType: Self.rootRecordType, recordID: rootID)
            applyClubMeta(to: rootRecord, club: club)
        }

        let share = CKShare(rootRecord: rootRecord)
        share[CKShare.SystemFieldKey.title] = "Book Club: \(club.name)" as CKRecordValue
        // Private participants retain bidirectional write access, but knowing
        // the share URL alone no longer grants access. The system sharing UI
        // adds specified recipients to the share.
        share.publicPermission = .none

        let saveResults = try await saveRootAndShare(rootRecord: rootRecord, share: share)
        // Some OS releases return only the root record in saveResults even
        // though the CKShare save succeeded. When the resolver falls back to
        // our locally-built share, hydrate it from the database; when CloudKit
        // gave us the saved share directly, skip the extra round-trip.
        let resolution = try ShareSaveResultResolver.resolve(
            saveResults: saveResults,
            fallback: share
        )
        let finalShare: CKShare
        if resolution.needsHydration {
            finalShare = (try? await privateDB.record(for: resolution.share.recordID) as? CKShare) ?? resolution.share
        } else {
            finalShare = resolution.share
        }

        markShareActive(finalShare, for: club)
        try await publishOwnerMemberSnapshot(for: club, context: context, ownerMemberID: ownerMemberID, ownerName: ownerName, parentRootID: rootID)
        Self.logger.info("✅ Created share for club '\(club.name, privacy: .private)' (zone \(club.cloudZoneName, privacy: .public))")
        return finalShare
    }

    // MARK: - Member-side: accept share

    /// Accepts an incoming CKShare and returns the share root payload when the
    /// owner has published one. The async batch API reports a per-share
    /// `Result`, so both the operation and that individual result must succeed
    /// before local membership is created.
    func acceptShare(metadata: CKShare.Metadata) async throws -> AcceptedShareInfo {
        guard Features.cloudKitSharing else {
            throw SharingError.featureDisabled
        }
        let acceptedShare = try await acceptedShare(for: metadata)
        let zoneID = acceptedShare.recordID.zoneID
        let rootRecord: CKRecord?
        do {
            rootRecord = try await acceptedRootRecord(zoneID: zoneID)
        } catch {
            // A pending invitation can be accepted before CloudKit has made
            // the shared zone visible locally. Preserve the accepted
            // membership and let the normal sync retry once the zone appears;
            // an already-accepted share must instead surface a real failure so
            // restoration never creates an orphan local club.
            guard metadata.participantStatus != .accepted,
                  CKZoneAvailability.classify(error) == .zoneRemoved else {
                throw error
            }
            rootRecord = nil
        }

        let shareForData: CKShare
        if let rootRecord,
           let shareReference = rootRecord.share,
           let hydratedShare = try? await sharedDB.record(for: shareReference.recordID) as? CKShare {
            shareForData = hydratedShare
        } else {
            shareForData = acceptedShare
        }

        let memberSnapshots: MemberSnapshotBatch
        if rootRecord != nil {
            memberSnapshots = try await fetchMemberSnapshotBatch(
                zoneID: zoneID,
                in: sharedDB,
                share: shareForData
            )
        } else {
            memberSnapshots = MemberSnapshotBatch(
                ownerUserRecordName: shareForData.owner.userIdentity.userRecordID?.recordName
                    ?? zoneID.ownerName,
                approvedParticipantUserRecordNames: Self.approvedParticipantUserRecordNames(in: shareForData),
                snapshots: []
            )
        }
        let clubName = clubName(from: rootRecord)
            ?? memberSnapshots.snapshots.compactMap { $0.snapshot.clubMeta?.name }.first
            ?? Self.cleanShareTitle(shareForData[CKShare.SystemFieldKey.title] as? String)
            ?? "Shared Book Club"
        return AcceptedShareInfo(
            zoneName: zoneID.zoneName,
            ownerUserRecordName: zoneID.ownerName,
            title: clubName,
            participantCount: Self.acceptedParticipantCount(in: shareForData),
            memberSnapshotBatch: memberSnapshots
        )
    }

    /// Rebuild local membership from shared zones that CloudKit already
    /// accepted. SwiftData's automatic mirroring only covers the user's own
    /// private database; a cross-Apple-ID CKShare must be re-associated with a
    /// local `BookClub` after an app reinstall or store rebuild.
    func restoreAcceptedShares() async throws -> [AcceptedShareInfo] {
        guard Features.cloudKitSharing else {
            throw SharingError.featureDisabled
        }

        let zones = try await sharedDB.allRecordZones()
        var restored: [AcceptedShareInfo] = []
        for zone in zones where zone.zoneID.zoneName.hasPrefix("BookClub-") {
            do {
                let root = try await rootRecord(zoneID: zone.zoneID, in: sharedDB)
                guard root.recordType == Self.rootRecordType,
                      let shareReference = root.share,
                      let share = try? await sharedDB.record(for: shareReference.recordID) as? CKShare else {
                    continue
                }

                let batch = try await fetchMemberSnapshotBatch(
                    zoneID: zone.zoneID,
                    in: sharedDB,
                    share: share
                )
                let title = clubName(from: root)
                    ?? batch.snapshots.compactMap { $0.snapshot.clubMeta?.name }.first
                    ?? Self.cleanShareTitle(share[CKShare.SystemFieldKey.title] as? String)
                    ?? "Shared Book Club"
                restored.append(
                    AcceptedShareInfo(
                        zoneName: zone.zoneID.zoneName,
                        ownerUserRecordName: zone.zoneID.ownerName,
                        title: title,
                        participantCount: Self.acceptedParticipantCount(in: share),
                        memberSnapshotBatch: batch
                    )
                )
            } catch {
                // One stale or temporarily unavailable zone must not prevent
                // other accepted clubs from being restored. A later launch or
                // the normal sync path can retry this zone.
                if CKZoneAvailability.classify(error) == .zoneRemoved {
                    continue
                }
                Self.logger.warning("Could not restore accepted shared zone \(zone.zoneID.zoneName, privacy: .public): \(CloudKitErrorDescriber.describe(error), privacy: .public)")
            }
        }
        return restored
    }

    private func acceptedShare(for metadata: CKShare.Metadata) async throws -> CKShare {
        switch metadata.participantStatus {
        case .accepted:
            return metadata.share
        case .removed:
            throw SharingError.shareAccessRemoved
        case .pending, .unknown:
            let results = try await container.accept([metadata])
            guard let result = results[metadata] else {
                throw SharingError.acceptanceResultMissing
            }
            return try result.get()
        @unknown default:
            let results = try await container.accept([metadata])
            guard let result = results[metadata] else {
                throw SharingError.acceptanceResultMissing
            }
            return try result.get()
        }
    }

    /// Publish (or update) the local member's snapshot record for `club`.
    /// `localMemberID` is the unique-per-device identity captured at app
    /// launch (`MemberIdentity.memberID`) — each participant writes a single
    /// record named after this ID.
    func publishMemberSnapshot(
        _ snapshot: MemberShareSnapshot,
        for club: BookClub,
        localMemberID: String
    ) async throws {
        try await publishMemberSnapshot(
            snapshot,
            target: MemberSnapshotSyncTarget(club),
            localMemberID: localMemberID
        )
    }

    func publishMemberSnapshot(
        _ snapshot: MemberShareSnapshot,
        target: MemberSnapshotSyncTarget,
        localMemberID: String
    ) async throws {
        guard Features.cloudKitSharing else {
            throw SharingError.featureDisabled
        }
        guard !localMemberID.isEmpty else {
            throw SharingError.missingLocalMemberID
        }
        let database = try database(for: target)
        let zoneID = try zoneID(for: target)
        let rootRecord = try await rootRecord(zoneID: zoneID, in: database)
        // Owner-side branch that writes canonical ClubMeta into the shared
        // zone's root record — gate on isShareOwner so it only runs once a
        // CKShare actually exists, not for a never-shared local club.
        if target.isShareOwner, let clubMeta = snapshot.clubMeta {
            applyClubMeta(to: rootRecord, clubMeta: clubMeta)
            try await saveRootRecord(rootRecord, in: database)
        }
        let recordID = CKRecord.ID(recordName: Self.memberRecordPrefix + localMemberID, zoneID: zoneID)
        let record: CKRecord
        if let existing = try? await database.record(for: recordID) {
            record = existing
        } else {
            record = CKRecord(recordType: Self.memberSnapshotRecordType, recordID: recordID)
        }
        record.parent = CKRecord.Reference(record: rootRecord, action: .none)
        try applyMemberSnapshot(snapshot, to: record)
        try await saveMemberSnapshot(snapshot, record: record, in: database)
    }

    func fetchMemberSnapshotBatch(target: MemberSnapshotSyncTarget) async throws -> MemberSnapshotBatch {
        guard Features.cloudKitSharing else {
            throw SharingError.featureDisabled
        }
        let database = try database(for: target)
        let zoneID = try zoneID(for: target)
        let root = try await rootRecord(zoneID: zoneID, in: database)
        guard let shareReference = root.share,
              let share = try await database.record(for: shareReference.recordID) as? CKShare else {
            throw SharingError.missingShare
        }
        return try await fetchMemberSnapshotBatch(zoneID: zoneID, in: database, share: share)
    }

    /// Convert a legacy public share to a specified-recipient share. CloudKit
    /// removes public participants when this is saved; their contribution
    /// records remain in the owner's shared hierarchy for re-import after the
    /// owner invites them privately.
    func migrateShareToPrivate(_ share: CKShare, for club: BookClub) async throws -> CKShare {
        guard club.isOwner else { throw SharingError.notOwner }
        guard share.publicPermission != .none else { return share }
        share.publicPermission = .none
        let result = try await privateDB.modifyRecords(saving: [share], deleting: [])
        let resolution = try ShareSaveResultResolver.resolve(
            saveResults: result.saveResults,
            fallback: share
        )
        let saved = if resolution.needsHydration {
            (try? await privateDB.record(for: resolution.share.recordID) as? CKShare) ?? resolution.share
        } else {
            resolution.share
        }
        club.inviteURLString = ""
        club.shareParticipantCount = Self.acceptedParticipantCount(in: saved)
        return saved
    }

    func fetchAcceptedParticipantCount(for club: BookClub) async throws -> Int {
        try await fetchAcceptedParticipantCount(target: MemberSnapshotSyncTarget(club))
    }

    func fetchAcceptedParticipantCount(target: MemberSnapshotSyncTarget) async throws -> Int {
        guard Features.cloudKitSharing else {
            throw SharingError.featureDisabled
        }
        let database = try database(for: target)
        let zoneID = try zoneID(for: target)
        let root = try await rootRecord(zoneID: zoneID, in: database)
        guard let shareReference = root.share,
              let share = try await database.record(for: shareReference.recordID) as? CKShare else {
            return max(1, target.participantCount)
        }
        return Self.acceptedParticipantCount(in: share)
    }

    func cloudKitContainer() -> CKContainer {
        container
    }

    // MARK: - Deletion

    /// Owner-side cleanup: delete the entire shared zone from `privateDB`.
    /// CloudKit cascades the delete to the share, the root record, and every
    /// `MemberShareSnapshot` record participants wrote into the zone, so all
    /// other devices see a `zoneNotFound` on their next refresh.
    func deleteSharedZone(for club: BookClub) async throws {
        guard Features.cloudKitSharing else { return }
        guard club.isOwner else {
            throw SharingError.notOwner
        }
        try await deleteSharedZone(zoneName: club.cloudZoneName)
    }

    func deleteSharedZone(zoneName: String) async throws {
        guard Features.cloudKitSharing else { return }
        let zoneID = CKRecordZone.ID(zoneName: zoneName)
        _ = try await privateDB.modifyRecordZones(saving: [], deleting: [zoneID])
        Self.logger.info("🗑 Deleted shared zone \(zoneName, privacy: .public)")
    }

    /// Owner-side: delete a specific participant's `MemberShareSnapshot`
    /// record from the shared zone AND revoke their CKShare access so removal
    /// is a single atomic-feeling action from the user's perspective. Their
    /// content is gone for everyone, the owner's `removedMemberIDs` list
    /// (synced via `ClubMeta`) prevents any re-published snapshot from being
    /// applied, and they're dropped from the share's participant list.
    func removeMemberSnapshot(for club: BookClub, memberID: String) async throws {
        guard Features.cloudKitSharing else { return }
        guard club.isOwner else {
            throw SharingError.notOwner
        }
        guard !memberID.isEmpty else {
            throw SharingError.missingLocalMemberID
        }
        let zoneID = try zoneID(for: club)
        let recordID = CKRecord.ID(recordName: Self.memberRecordPrefix + memberID, zoneID: zoneID)
        // Capture the participant's CloudKit user identity from the snapshot
        // record's system field BEFORE deletion, so we can revoke share access
        // afterward. Best-effort — the record may already be gone if they
        // leftShare on their device.
        let participantUserRecordID = (try? await privateDB.record(for: recordID))?.creatorUserRecordID
        do {
            _ = try await privateDB.modifyRecords(saving: [], deleting: [recordID])
            Self.logger.info("✂️ Removed member snapshot \(memberID, privacy: .private) from \(club.cloudZoneName, privacy: .public)")
        } catch {
            Self.logger.warning("⚠️ Best-effort removeMemberSnapshot failed for \(memberID, privacy: .private): \(CloudKitErrorDescriber.describe(error), privacy: .public)")
        }
        if let participantUserRecordID {
            await revokeShareParticipant(for: club, userRecordID: participantUserRecordID, memberID: memberID)
        }
    }

    /// Best-effort revoke of a participant's CKShare access. Looks up the
    /// share, removes the participant matching `userRecordID`, and saves.
    /// Failures are logged but not thrown — the snapshot has already been
    /// removed, so the member's content is gone either way; share-list cleanup
    /// is the secondary effect.
    private func revokeShareParticipant(for club: BookClub, userRecordID: CKRecord.ID, memberID: String) async {
        guard let zoneID = try? zoneID(for: club) else { return }
        let rootID = CKRecord.ID(recordName: Self.rootRecordName, zoneID: zoneID)
        guard let rootRecord = try? await privateDB.record(for: rootID),
              let shareReference = rootRecord.share,
              let share = try? await privateDB.record(for: shareReference.recordID) as? CKShare else {
            Self.logger.warning("⚠️ Could not load CKShare to revoke participant for \(memberID, privacy: .private)")
            return
        }
        guard let target = share.participants.first(where: { $0.userIdentity.userRecordID == userRecordID }) else {
            // No matching participant — likely already left the share or never
            // accepted on this Apple ID. Nothing to revoke.
            return
        }
        guard target.role != .owner else {
            Self.logger.warning("⚠️ Refusing to revoke owner participant for club \(club.cloudZoneName, privacy: .public)")
            return
        }
        share.removeParticipant(target)
        do {
            _ = try await privateDB.modifyRecords(saving: [share], deleting: [])
            Self.logger.info("🚫 Revoked share access for member \(memberID, privacy: .private) in \(club.cloudZoneName, privacy: .public)")
            let count = Self.acceptedParticipantCount(in: share)
            if club.shareParticipantCount != count {
                club.shareParticipantCount = count
            }
        } catch {
            Self.logger.warning("⚠️ Failed to save share after removing participant \(memberID, privacy: .private): \(CloudKitErrorDescriber.describe(error), privacy: .public)")
        }
    }

    /// Member-side cleanup: remove the local member's `MemberShareSnapshot`
    /// record so other participants stop seeing their contributions, then
    /// drop the shared zone from `sharedCloudDatabase`. The latter is how
    /// CloudKit models a participant leaving a share — it removes them from
    /// the share's participant list without affecting the owner's data.
    func leaveShare(for club: BookClub, localMemberID: String) async throws {
        guard Features.cloudKitSharing else { return }
        guard !club.isOwner else {
            throw SharingError.cannotLeaveOwnShare
        }
        try await leaveShare(
            zoneName: club.cloudZoneName,
            ownerUserRecordName: club.ownerUserRecordName,
            localMemberID: localMemberID
        )
    }

    func leaveShare(zoneName: String, ownerUserRecordName: String?, localMemberID: String) async throws {
        guard Features.cloudKitSharing else { return }
        guard let ownerName = ownerUserRecordName?.trimmedOrNil else {
            throw SharingError.missingOwnerUserRecordName
        }
        guard !localMemberID.isEmpty else { throw SharingError.missingLocalMemberID }
        let zoneID = CKRecordZone.ID(zoneName: zoneName, ownerName: ownerName)
        let memberRecordID = CKRecord.ID(recordName: Self.memberRecordPrefix + localMemberID, zoneID: zoneID)
        // Best-effort: clear our own contribution record. The zone-delete
        // below is what actually removes us from the share.
        _ = try? await sharedDB.modifyRecords(saving: [], deleting: [memberRecordID])
        _ = try await sharedDB.modifyRecordZones(saving: [], deleting: [zoneID])
        Self.logger.info("👋 Left share \(zoneName, privacy: .public)")
    }

    // MARK: - Private helpers

    private func ensureZoneExists(_ zone: CKRecordZone) async throws {
        let existing = try await privateDB.allRecordZones()
        if existing.contains(where: { $0.zoneID.zoneName == zone.zoneID.zoneName }) {
            return
        }
        _ = try await privateDB.modifyRecordZones(saving: [zone], deleting: [])
    }

    private func existingShare(for rootRecord: CKRecord) async throws -> CKShare? {
        guard let shareReference = rootRecord.share else { return nil }
        do {
            return try await privateDB.record(for: shareReference.recordID) as? CKShare
        } catch {
            Self.logger.error("⚠️ Existing share reference could not be fetched: \(error.localizedDescription, privacy: .public)")
            throw error
        }
    }

    private func applyClubMeta(to rootRecord: CKRecord, club: BookClub) {
        rootRecord[Self.clubNameKey] = club.name as CKRecordValue
        rootRecord[Self.clubCreatedAtKey] = club.createdAt as CKRecordValue
    }

    private func applyClubMeta(to rootRecord: CKRecord, clubMeta: MemberShareSnapshot.ClubMeta) {
        rootRecord[Self.clubNameKey] = clubMeta.name as CKRecordValue
        rootRecord[Self.clubCreatedAtKey] = clubMeta.createdAt as CKRecordValue
    }

    private func clubName(from record: CKRecord?) -> String? {
        (record?[Self.clubNameKey] as? String)?.trimmedOrNil
    }

    private func applyMemberSnapshot(_ snapshot: MemberShareSnapshot, to record: CKRecord) throws {
        let data = try cloudSafeSnapshotData(from: snapshot)
        record[Self.snapshotDataKey] = data as NSData
        record[Self.snapshotUpdatedAtKey] = snapshot.capturedAt as CKRecordValue
        record[Self.memberIDKey] = snapshot.authorMemberID as CKRecordValue
        record[Self.memberNameKey] = snapshot.authorName as CKRecordValue
    }

    private func cloudSafeSnapshotData(from snapshot: MemberShareSnapshot) throws -> Data {
        let encoder = JSONEncoder()
        let data = try encoder.encode(snapshot)
        guard data.count <= Self.maxSnapshotBytes else {
            throw SharingError.snapshotTooLarge
        }
        return data
    }

    private func decodeMemberSnapshot(from record: CKRecord) throws -> MemberShareSnapshot {
        let data: Data?
        if let value = record[Self.snapshotDataKey] as? Data {
            data = value
        } else if let value = record[Self.snapshotDataKey] as? NSData {
            data = Data(referencing: value)
        } else {
            data = nil
        }
        guard let data else { throw SharingError.malformedMemberSnapshot(record.recordID.recordName) }
        do {
            return try JSONDecoder().decode(MemberShareSnapshot.self, from: data)
        } catch {
            throw SharingError.malformedMemberSnapshot(record.recordID.recordName)
        }
    }

    private func rootRecord(zoneID: CKRecordZone.ID, in database: CKDatabase) async throws -> CKRecord {
        try await database.record(for: CKRecord.ID(recordName: Self.rootRecordName, zoneID: zoneID))
    }

    private func fetchMemberSnapshots(zoneID: CKRecordZone.ID, in database: CKDatabase) async throws -> [MemberShareSnapshot] {
        try await Self.fetchMemberSnapshots(
            zoneID: zoneID,
            query: queryFactory(database),
            decode: decodeMemberSnapshot
        )
    }

    private func fetchMemberSnapshotBatch(
        zoneID: CKRecordZone.ID,
        in database: CKDatabase,
        share: CKShare
    ) async throws -> MemberSnapshotBatch {
        let query = queryFactory(database)
        let snapshots = try await Self.fetchProvenancedMemberSnapshots(
            zoneID: zoneID,
            query: query,
            decode: decodeMemberSnapshot
        )
        return MemberSnapshotBatch(
            ownerUserRecordName: share.owner.userIdentity.userRecordID?.recordName ?? zoneID.ownerName,
            approvedParticipantUserRecordNames: Self.approvedParticipantUserRecordNames(in: share),
            snapshots: snapshots
        )
    }

    private static func approvedParticipantUserRecordNames(in share: CKShare) -> Set<String> {
        Set(share.participants.compactMap { participant in
            guard participant.role == .owner || participant.acceptanceStatus == .accepted else { return nil }
            return participant.userIdentity.userRecordID?.recordName
        })
    }

    static func fetchProvenancedMemberSnapshots(
        zoneID: CKRecordZone.ID,
        query: any MemberSnapshotQuerying,
        decode: (CKRecord) throws -> MemberShareSnapshot
    ) async throws -> [ProvenancedMemberSnapshot] {
        var snapshots: [ProvenancedMemberSnapshot] = []
        var page = try await query.firstPage(recordType: memberSnapshotRecordType, zoneID: zoneID)
        while true {
            for recordResult in page.records {
                let record = try recordResult.get()
                snapshots.append(
                    ProvenancedMemberSnapshot(
                        snapshot: try decode(record),
                        provenance: MemberSnapshotProvenance(
                            recordName: record.recordID.recordName,
                            creatorUserRecordName: record.creatorUserRecordID?.recordName,
                            lastModifiedUserRecordName: record.lastModifiedUserRecordID?.recordName
                        )
                    )
                )
            }
            guard page.hasMore else { break }
            page = try await query.nextPage()
        }
        return snapshots
    }

    static func fetchMemberSnapshots(
        zoneID: CKRecordZone.ID,
        query: any MemberSnapshotQuerying,
        decode: (CKRecord) throws -> MemberShareSnapshot
    ) async throws -> [MemberShareSnapshot] {
        var snapshots: [MemberShareSnapshot] = []
        var page = try await query.firstPage(recordType: memberSnapshotRecordType, zoneID: zoneID)
        while true {
            for recordResult in page.records {
                snapshots.append(try decode(recordResult.get()))
            }
            guard page.hasMore else { break }
            page = try await query.nextPage()
        }
        return snapshots
    }

    /// Owner-side bootstrap: write the owner's MemberShareSnapshot record
    /// immediately after creating the share so members joining for the first
    /// time have something to import.
    private func publishOwnerMemberSnapshot(
        for club: BookClub,
        context: ModelContext,
        ownerMemberID: String,
        ownerName: String,
        parentRootID: CKRecord.ID
    ) async throws {
        let snapshot = MemberShareSnapshotStore.snapshot(
            from: club,
            context: context,
            authorMemberID: ownerMemberID,
            authorName: ownerName,
            includeClubMeta: true
        )
        let recordID = CKRecord.ID(recordName: Self.memberRecordPrefix + ownerMemberID, zoneID: parentRootID.zoneID)
        let record: CKRecord
        if let existing = try? await privateDB.record(for: recordID) {
            record = existing
        } else {
            record = CKRecord(recordType: Self.memberSnapshotRecordType, recordID: recordID)
        }
        // Tie the per-member record to the share root so it's covered by the
        // CKShare permissions.
        if let rootRecord = try? await privateDB.record(for: parentRootID) {
            record.parent = CKRecord.Reference(record: rootRecord, action: .none)
        }
        try applyMemberSnapshot(snapshot, to: record)
        try await saveRootRecord(record, in: privateDB)
    }

    /// Immediately after `container.accept`, the shared zone may not be
    /// queryable yet — CloudKit needs a moment to plumb the share through to
    /// `sharedCloudDatabase`. Retry with exponential backoff (250ms → 500ms →
    /// 1s, ~1.75s total budget) before giving up. Preserve the final error so
    /// callers can distinguish a materializing zone from a network or
    /// permission failure.
    private func acceptedRootRecord(zoneID: CKRecordZone.ID) async throws -> CKRecord {
        var delay: Duration = .milliseconds(250)
        var lastError: Error?
        for attempt in 0..<4 {
            do {
                return try await rootRecord(zoneID: zoneID, in: sharedDB)
            } catch {
                lastError = error
                if attempt < 3 {
                    try? await Task.sleep(for: delay)
                    delay *= 2
                }
            }
        }
        if let lastError {
            Self.logger.error("Shared root was not available after accept: \(CloudKitErrorDescriber.describe(lastError), privacy: .public)")
            throw lastError
        }
        throw SharingError.missingShare
    }

    private func database(for club: BookClub) throws -> CKDatabase {
        if club.isOwner {
            return privateDB
        }
        guard club.ownerUserRecordName?.trimmedOrNil != nil else {
            throw SharingError.missingOwnerUserRecordName
        }
        return sharedDB
    }

    private func zoneID(for club: BookClub) throws -> CKRecordZone.ID {
        if club.isOwner {
            return CKRecordZone.ID(zoneName: club.cloudZoneName)
        }
        guard let ownerName = club.ownerUserRecordName?.trimmedOrNil else {
            throw SharingError.missingOwnerUserRecordName
        }
        return CKRecordZone.ID(zoneName: club.cloudZoneName, ownerName: ownerName)
    }

    private func database(for target: MemberSnapshotSyncTarget) throws -> CKDatabase {
        if target.isOwner { return privateDB }
        guard target.ownerUserRecordName?.trimmedOrNil != nil else {
            throw SharingError.missingOwnerUserRecordName
        }
        return sharedDB
    }

    private func zoneID(for target: MemberSnapshotSyncTarget) throws -> CKRecordZone.ID {
        if target.isOwner { return CKRecordZone.ID(zoneName: target.zoneName) }
        guard let ownerName = target.ownerUserRecordName?.trimmedOrNil else {
            throw SharingError.missingOwnerUserRecordName
        }
        return CKRecordZone.ID(zoneName: target.zoneName, ownerName: ownerName)
    }

    private func saveRootRecord(_ rootRecord: CKRecord, in database: CKDatabase) async throws {
        _ = try await database.modifyRecords(saving: [rootRecord], deleting: [])
    }

    /// A publish can race a write from another device. Reapply the local
    /// snapshot to CloudKit's current server record once instead of allowing
    /// an older completion to overwrite or discard the latest local state.
    private func saveMemberSnapshot(
        _ snapshot: MemberShareSnapshot,
        record: CKRecord,
        in database: CKDatabase
    ) async throws {
        do {
            try await saveRootRecord(record, in: database)
        } catch {
            guard let serverRecord = conflictServerRecord(from: error) else { throw error }
            try applyMemberSnapshot(snapshot, to: serverRecord)
            try await saveRootRecord(serverRecord, in: database)
        }
    }

    private func conflictServerRecord(from error: Error) -> CKRecord? {
        let nsError = error as NSError
        if nsError.domain == CKErrorDomain,
           nsError.code == CKError.serverRecordChanged.rawValue {
            return nsError.userInfo[CKRecordChangedErrorServerRecordKey] as? CKRecord
        }
        if let partials = nsError.userInfo[CKPartialErrorsByItemIDKey] as? [AnyHashable: Error] {
            return partials.values.lazy.compactMap(conflictServerRecord).first
        }
        return nil
    }

    private func saveRootAndShare(rootRecord: CKRecord, share: CKShare) async throws -> [CKRecord.ID: Result<CKRecord, Error>] {
        do {
            let result = try await privateDB.modifyRecords(
                saving: [rootRecord, share],
                deleting: []
            )
            return result.saveResults
        } catch {
            Self.logger.error("⚠️ CKShare modifyRecords failed: \(CloudKitErrorDescriber.describe(error), privacy: .public)")
            throw error
        }
    }

    private func markShareActive(_ share: CKShare, for club: BookClub) {
        if !club.shareIsActive { club.shareIsActive = true }
        let count = Self.acceptedParticipantCount(in: share)
        if club.shareParticipantCount != count { club.shareParticipantCount = count }
        // Invitation URLs are intentionally not replicated through snapshots.
        // A private share URL is useful only after the owner adds its intended
        // recipient, and treating it as a reusable club credential is unsafe.
        if !club.inviteURLString.isEmpty { club.inviteURLString = "" }
    }

    private static func acceptedParticipantCount(in share: CKShare) -> Int {
        let count = share.participants.filter { participant in
            participant.acceptanceStatus == .accepted || participant.role == .owner
        }.count
        return max(1, count)
    }

    private static func cleanShareTitle(_ rawTitle: String?) -> String? {
        guard let rawTitle = rawTitle?.trimmedOrNil else { return nil }
        let prefix = "Book Club: "
        if rawTitle.hasPrefix(prefix) {
            return String(rawTitle.dropFirst(prefix.count)).trimmedOrNil
        }
        return rawTitle
    }
}

struct AcceptedShareInfo: Sendable {
    let zoneName: String
    let ownerUserRecordName: String
    let title: String
    let participantCount: Int
    let memberSnapshotBatch: MemberSnapshotBatch
}

enum SharingError: LocalizedError {
    case featureDisabled
    case missingOwnerUserRecordName
    case missingLocalMemberID
    case snapshotTooLarge
    case notOwner
    case cannotLeaveOwnShare
    case missingShare
    case shareAccessRemoved
    case acceptanceResultMissing
    case malformedMemberSnapshot(String)

    var errorDescription: String? {
        switch self {
        case .featureDisabled:
            return "iCloud sharing isn't available in this build yet."
        case .missingOwnerUserRecordName:
            return "The shared club is missing its CloudKit owner identifier."
        case .missingLocalMemberID:
            return "Set your member name in Settings before sharing changes."
        case .snapshotTooLarge:
            return "The shared club is too large to publish right now."
        case .notOwner:
            return "Only the club owner can delete the shared CloudKit zone."
        case .cannotLeaveOwnShare:
            return "You own this club — delete it instead of leaving."
        case .missingShare:
            return "The shared club's CloudKit share record is unavailable."
        case .shareAccessRemoved:
            return "This invitation no longer grants access to the book club. Ask its owner for a new invitation."
        case .acceptanceResultMissing:
            return "CloudKit did not confirm access to this book club. Try the invitation again."
        case .malformedMemberSnapshot(let recordName):
            return "The shared club contains an unreadable member snapshot (\(recordName)). No local data was changed."
        }
    }
}

/// Distinguish CloudKit "this zone/share has been removed by the owner" errors
/// from transient network errors. We treat the former as a signal to drop the
/// local club row; the latter is just retried.
enum CKZoneAvailability {
    case available
    case zoneRemoved

    static func classify(_ error: Error) -> CKZoneAvailability {
        let ns = error as NSError
        guard ns.domain == CKErrorDomain else { return .available }
        switch ns.code {
        case CKError.zoneNotFound.rawValue,
             CKError.userDeletedZone.rawValue,
             CKError.unknownItem.rawValue:
            return .zoneRemoved
        default:
            // Walk partial errors (which is how `modifyRecords` reports
            // per-record failures) to see if any individual record failure
            // matches.
            if let partials = ns.userInfo[CKPartialErrorsByItemIDKey] as? [AnyHashable: Error] {
                for partial in partials.values {
                    if classify(partial) == .zoneRemoved { return .zoneRemoved }
                }
            }
            return .available
        }
    }
}

enum CloudKitErrorDescriber {
    static func describe(_ error: Error) -> String {
        let ns = error as NSError
        var parts = ["\(ns.domain)#\(ns.code): \(ns.localizedDescription)"]
        if let partials = ns.userInfo[CKPartialErrorsByItemIDKey] as? [AnyHashable: Error] {
            let details = partials.map { key, value -> String in
                let child = value as NSError
                return "\(key): \(child.domain)#\(child.code) \(child.localizedDescription)"
            }
            .sorted()
            parts.append("partialErrors=[\(details.joined(separator: "; "))]")
        }
        return parts.joined(separator: " ")
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
