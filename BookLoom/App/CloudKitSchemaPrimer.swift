import CloudKit
import Darwin
import Foundation
import os

#if DEBUG
@MainActor
enum CloudKitSchemaPrimer {
    private static let logger = Logger(subsystem: "net.shadowpuppet.BookLoom", category: "CloudKitSchemaPrimer")
    private static let environmentKey = "BOOKLOOM_PRIME_CLOUDKIT_SCHEMA"
    private static let launchArgument = "--prime-cloudkit-schema"
    private static let rootRecordType = "BookClubShareRoot"
    private static var hasRun = false

    static var isRequested: Bool {
        shouldRun
    }

    static func runIfRequested() async {
        // Never construct a CKContainer under XCTest: CI strips entitlements
        // (CODE_SIGNING_ALLOWED=NO), where CKContainer construction traps.
        guard !Features.isRunningTests else { return }
        guard shouldRun, !hasRun else { return }
        hasRun = true

        var exitCode: Int32 = 0
        do {
            log("Starting CloudKit Development schema prime")
            try await primeShareSchema()
            log("Finished CloudKit Development schema prime")
        } catch {
            exitCode = 1
            log("CloudKit Development schema prime failed: \(CloudKitErrorDescriber.describe(error))", isError: true)
        }

        if ProcessInfo.processInfo.arguments.contains(launchArgument) {
            fflush(stdout)
            fflush(stderr)
            exit(exitCode)
        }
    }

    private static var shouldRun: Bool {
        ProcessInfo.processInfo.environment[environmentKey] == "1"
        || ProcessInfo.processInfo.arguments.contains(launchArgument)
    }

    private static func primeShareSchema() async throws {
        let container = CKContainer(identifier: BookLoomCloudKit.containerIdentifier)
        let status = try await container.accountStatus()
        guard status == .available else {
            throw PrimeError.iCloudAccountUnavailable(status)
        }

        let db = container.privateCloudDatabase
        let zone = CKRecordZone(zoneName: "\(SchemaPrimeIdentity.cloudZonePrefix)\(UUID().uuidString)")
        _ = try await db.modifyRecordZones(saving: [zone], deleting: [])

        let rootID = CKRecord.ID(recordName: "ShareRoot", zoneID: zone.zoneID)
        let root = CKRecord(recordType: rootRecordType, recordID: rootID)
        root["clubName"] = SchemaPrimeIdentity.clubName as CKRecordValue
        root["clubCreatedAt"] = Date.now as CKRecordValue

        let memberRecordID = CKRecord.ID(recordName: "MemberSnapshot-schema-prime", zoneID: zone.zoneID)
        let memberRecord = CKRecord(recordType: "MemberShareSnapshot", recordID: memberRecordID)
        memberRecord.parent = CKRecord.Reference(record: root, action: .none)
        let snapshot = MemberShareSnapshot(
            authorMemberID: "schema-prime",
            authorName: "Schema Prime",
            clubMeta: MemberShareSnapshot.ClubMeta(
                name: SchemaPrimeIdentity.clubName,
                createdAt: .now,
                cloudZoneName: zone.zoneID.zoneName,
                shareParticipantCount: 1,
                creatorMemberID: nil,
                adminMemberIDs: nil,
                removedMemberIDs: nil,
                inviteURLString: nil,
                nameUpdatedAt: nil
            )
        )
        memberRecord["snapshotData"] = try JSONEncoder().encode(snapshot) as NSData
        memberRecord["snapshotUpdatedAt"] = snapshot.capturedAt as CKRecordValue
        memberRecord["memberID"] = snapshot.authorMemberID as CKRecordValue
        memberRecord["memberName"] = snapshot.authorName as CKRecordValue

        let share = CKShare(rootRecord: root)
        share[CKShare.SystemFieldKey.title] = "Book Club: \(SchemaPrimeIdentity.clubName)" as CKRecordValue
        share.publicPermission = .none

        _ = try await db.modifyRecords(saving: [root, memberRecord, share], deleting: [])
        log("Saved CKShare schema-prime records in zone \(zone.zoneID.zoneName)")
    }

    private static func log(_ message: String, isError: Bool = false) {
        if isError {
            logger.error("\(message, privacy: .public)")
        } else {
            logger.info("\(message, privacy: .public)")
        }
    }
}

private enum PrimeError: LocalizedError {
    case iCloudAccountUnavailable(CKAccountStatus)

    var errorDescription: String? {
        switch self {
        case .iCloudAccountUnavailable(let status):
            return "iCloud account is not available for schema prime: \(status)"
        }
    }
}
#endif
