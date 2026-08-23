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
    func publishMemberSnapshot(_ snapshot: MemberShareSnapshot, for club: BookClub, localMemberID: String) async throws
    func fetchMemberSnapshots(for club: BookClub) async throws -> [MemberShareSnapshot]
    func fetchAcceptedParticipantCount(for club: BookClub) async throws -> Int
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
    /// can then be surfaced via `UICloudSharingController` (iOS) or copied to
    /// the pasteboard (macOS). Re-runs are idempotent — calling twice returns
    /// the same share.
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
        // Anyone with the invite link can read AND write — required for
        // bidirectional collaboration. Each participant only ever writes to
        // their *own* MemberShareSnapshot record by convention, so write
        // access is safe.
        share.publicPermission = .readWrite

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
    /// owner has published one. Older builds may still return metadata only.
    func acceptShare(metadata: CKShare.Metadata) async throws -> AcceptedShareInfo {
        guard Features.cloudKitSharing else {
            throw SharingError.featureDisabled
        }
        // Discard the return — the compiler warns if it's ignored implicitly.
        _ = try await container.accept([metadata])
        let rootRecord = await acceptedRootRecord(zoneID: metadata.share.recordID.zoneID)
        let memberSnapshots = (try? await fetchMemberSnapshots(zoneID: metadata.share.recordID.zoneID, in: sharedDB)) ?? []
        let clubName = clubName(from: rootRecord)
            ?? memberSnapshots.compactMap { $0.clubMeta?.name }.first
            ?? Self.cleanShareTitle(metadata.share[CKShare.SystemFieldKey.title] as? String)
            ?? "Shared Book Club"
        return AcceptedShareInfo(
            zoneName: metadata.share.recordID.zoneID.zoneName,
            ownerUserRecordName: metadata.share.recordID.zoneID.ownerName,
            title: clubName,
            participantCount: Self.acceptedParticipantCount(in: metadata.share),
            memberSnapshots: memberSnapshots
        )
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
        guard Features.cloudKitSharing else {
            throw SharingError.featureDisabled
        }
        guard !localMemberID.isEmpty else {
            throw SharingError.missingLocalMemberID
        }
        let database = try database(for: club)
        let zoneID = try zoneID(for: club)
        let rootRecord = try await rootRecord(zoneID: zoneID, in: database)
        // Owner-side branch that writes canonical ClubMeta into the shared
        // zone's root record — gate on isShareOwner so it only runs once a
        // CKShare actually exists, not for a never-shared local club.
        if club.isShareOwner {
            applyClubMeta(to: rootRecord, club: club)
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

    /// Fetch every member snapshot record in the shared zone for `club`.
    func fetchMemberSnapshots(for club: BookClub) async throws -> [MemberShareSnapshot] {
        guard Features.cloudKitSharing else {
            throw SharingError.featureDisabled
        }
        let database = try database(for: club)
        let zoneID = try zoneID(for: club)
        return try await fetchMemberSnapshots(zoneID: zoneID, in: database)
    }

    func fetchAcceptedParticipantCount(for club: BookClub) async throws -> Int {
        guard Features.cloudKitSharing else {
            throw SharingError.featureDisabled
        }
        let database = try database(for: club)
        let zoneID = try zoneID(for: club)
        let root = try await rootRecord(zoneID: zoneID, in: database)
        guard let shareReference = root.share,
              let share = try await database.record(for: shareReference.recordID) as? CKShare else {
            return max(1, club.shareParticipantCount)
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
    /// 1s, ~1.75s total budget) before giving up. Returns nil on persistent
    /// failure so the caller can fall back to the metadata-only join path.
    private func acceptedRootRecord(zoneID: CKRecordZone.ID) async -> CKRecord? {
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
        }
        return nil
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
        if let urlString = share.url?.absoluteString.trimmedOrNil,
           club.inviteURLString != urlString {
            club.inviteURLString = urlString
        }
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
    let memberSnapshots: [MemberShareSnapshot]
}

enum SharingError: LocalizedError {
    case featureDisabled
    case missingOwnerUserRecordName
    case missingLocalMemberID
    case snapshotTooLarge
    case notOwner
    case cannotLeaveOwnShare
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
