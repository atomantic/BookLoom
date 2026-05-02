import Foundation
import CloudKit
import os
import SwiftData

/// Owns the CKShare invite handshake. SwiftData (`cloudKitDatabase: .automatic`)
/// already replicates `BookClub` and its descendants across the user's own
/// devices; this service overlays a `CKShare` so users on **different Apple
/// IDs** can join the same club.
///
/// This service creates the inviteable share root. SwiftData's `.automatic`
/// CloudKit mode still primarily handles private-database sync; cross-account
/// collaboration uses a compact JSON snapshot stored on the shared root record.
/// A signed two-account TestFlight smoke test still needs to verify mutation
/// propagation before calling collaboration done.
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
    private static let logger = Logger(subsystem: "net.shadowpuppet.BookLoom", category: "CloudKitSharing")
    /// Custom record type for the share root. NEVER prefix with `_` — that's
    /// a CloudKit-reserved namespace and `modifyRecords` will reject it.
    private static let rootRecordType = "BookClubShareRoot"
    private static let rootRecordName = "ShareRoot"
    private static let clubNameKey = "clubName"
    private static let snapshotDataKey = "snapshotData"
    private static let snapshotUpdatedAtKey = "snapshotUpdatedAt"
    private static let maxSnapshotBytes = 900 * 1024

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
    func createOrFetchShare(for club: BookClub, context: ModelContext) async throws -> CKShare {
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
            try updateRootRecord(rootRecord, with: club, context: context)
            if let existingShare = try await existingShare(for: existingRoot) {
                try await saveRootRecord(rootRecord, in: privateDB)
                markShareActive(existingShare, for: club)
                return existingShare
            }
        } else {
            rootRecord = CKRecord(recordType: Self.rootRecordType, recordID: rootID)
            try updateRootRecord(rootRecord, with: club, context: context)
        }

        let share = CKShare(rootRecord: rootRecord)
        share[CKShare.SystemFieldKey.title] = "Book Club: \(club.name)" as CKRecordValue
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
        Self.logger.info("✅ Created share for club '\(club.name, privacy: .public)' (zone \(club.cloudZoneName, privacy: .public))")
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
        let snapshot = rootRecord.flatMap { decodeSnapshot(from: $0) }
        let title = snapshot?.club.name
            ?? rootRecord?[Self.clubNameKey] as? String
            ?? Self.cleanShareTitle(metadata.share[CKShare.SystemFieldKey.title] as? String)
            ?? "Shared Book Club"
        return AcceptedShareInfo(
            zoneName: metadata.share.recordID.zoneID.zoneName,
            ownerUserRecordName: metadata.share.recordID.zoneID.ownerName,
            title: title,
            participantCount: metadata.share.participants.count,
            snapshot: snapshot
        )
    }

    func publishSnapshot(_ snapshot: SharedClubSnapshot, for club: BookClub) async throws {
        guard Features.cloudKitSharing else {
            throw SharingError.featureDisabled
        }
        let database = try database(for: club)
        let zoneID = try zoneID(for: club)
        let root = try await rootRecord(zoneID: zoneID, in: database)
        try applySnapshot(snapshot, to: root)
        try await saveRootRecord(root, in: database)
    }

    func fetchSnapshot(for club: BookClub) async throws -> SharedClubSnapshot? {
        guard Features.cloudKitSharing else {
            throw SharingError.featureDisabled
        }
        let database = try database(for: club)
        let zoneID = try zoneID(for: club)
        let root = try await rootRecord(zoneID: zoneID, in: database)
        return decodeSnapshot(from: root)
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

    private func existingShare(for rootRecord: CKRecord) async throws -> CKShare? {
        guard let shareReference = rootRecord.share else { return nil }
        do {
            return try await privateDB.record(for: shareReference.recordID) as? CKShare
        } catch {
            Self.logger.error("⚠️ Existing share reference could not be fetched: \(error.localizedDescription, privacy: .public)")
            throw error
        }
    }

    private func updateRootRecord(_ rootRecord: CKRecord, with club: BookClub, context: ModelContext) throws {
        let snapshot = SharedClubSnapshotStore.snapshot(from: club, context: context)
        try applySnapshot(snapshot, to: rootRecord)
    }

    private func applySnapshot(_ snapshot: SharedClubSnapshot, to rootRecord: CKRecord) throws {
        let snapshotData = try cloudSafeSnapshotData(from: snapshot)
        rootRecord[Self.clubNameKey] = snapshot.club.name as CKRecordValue
        rootRecord[Self.snapshotDataKey] = snapshotData as NSData
        rootRecord[Self.snapshotUpdatedAtKey] = snapshot.capturedAt as CKRecordValue
    }

    private func cloudSafeSnapshotData(from snapshot: SharedClubSnapshot) throws -> Data {
        let encoder = JSONEncoder()
        let data = try encoder.encode(snapshot)
        guard data.count <= Self.maxSnapshotBytes else {
            throw SharingError.snapshotTooLarge
        }
        return data
    }

    private func decodeSnapshot(from rootRecord: CKRecord) -> SharedClubSnapshot? {
        let data: Data?
        if let value = rootRecord[Self.snapshotDataKey] as? Data {
            data = value
        } else if let value = rootRecord[Self.snapshotDataKey] as? NSData {
            data = Data(referencing: value)
        } else {
            data = nil
        }
        guard let data else {
            return nil
        }
        return try? JSONDecoder().decode(SharedClubSnapshot.self, from: data)
    }

    private func rootRecord(zoneID: CKRecordZone.ID, in database: CKDatabase) async throws -> CKRecord {
        try await database.record(for: CKRecord.ID(recordName: Self.rootRecordName, zoneID: zoneID))
    }

    /// Immediately after `container.accept`, the shared zone may not be
    /// queryable yet — CloudKit needs a moment to plumb the share through to
    /// `sharedCloudDatabase`. Retry with exponential backoff (250ms → 500ms →
    /// 1s, ~1.75s total budget) before giving up. Returns nil on persistent
    /// failure so the caller can fall back to the metadata-only join path.
    private func acceptedRootRecord(zoneID: CKRecordZone.ID) async -> CKRecord? {
        var delay: UInt64 = 250_000_000
        var lastError: Error?
        for attempt in 0..<4 {
            do {
                return try await rootRecord(zoneID: zoneID, in: sharedDB)
            } catch {
                lastError = error
                if attempt < 3 {
                    try? await Task.sleep(nanoseconds: delay)
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
        club.shareIsActive = true
        club.shareParticipantCount = share.participants.count
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
    let snapshot: SharedClubSnapshot?
}

enum SharingError: LocalizedError {
    case featureDisabled
    case missingOwnerUserRecordName
    case snapshotTooLarge

    var errorDescription: String? {
        switch self {
        case .featureDisabled:
            return "iCloud sharing isn't available in this build yet."
        case .missingOwnerUserRecordName:
            return "The shared club is missing its CloudKit owner identifier."
        case .snapshotTooLarge:
            return "The shared club is too large to publish right now."
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
