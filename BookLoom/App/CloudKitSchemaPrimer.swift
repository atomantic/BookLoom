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
    private static let containerID = "iCloud.net.shadowpuppet.PlotLoom"
    private static let rootRecordType = "BookClubShareRoot"

    static func runIfRequested() async {
        guard shouldRun else { return }

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
        let container = CKContainer(identifier: containerID)
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
        let snapshot = SharedClubSnapshot(
            club: .init(
                name: SchemaPrimeIdentity.clubName,
                createdAt: .now,
                cloudZoneName: zone.zoneID.zoneName,
                shareParticipantCount: 1
            ),
            submissions: [],
            meetings: [],
            polls: []
        )
        root["snapshotData"] = try JSONEncoder().encode(snapshot) as NSData
        root["snapshotUpdatedAt"] = snapshot.capturedAt as CKRecordValue

        let share = CKShare(rootRecord: root)
        share[CKShare.SystemFieldKey.title] = "Book Club: \(SchemaPrimeIdentity.clubName)" as CKRecordValue
        share.publicPermission = .none

        _ = try await db.modifyRecords(saving: [root, share], deleting: [])
        log("Saved CKShare schema-prime records in zone \(zone.zoneID.zoneName)")
    }

    private static func log(_ message: String, isError: Bool = false) {
        print("[CloudKitSchemaPrimer] \(message)")
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
