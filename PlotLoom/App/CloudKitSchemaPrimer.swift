import CloudKit
import Darwin
import Foundation
import os
import SwiftData

#if DEBUG
@MainActor
enum CloudKitSchemaPrimer {
    private static let logger = Logger(subsystem: "net.shadowpuppet.PlotLoom", category: "CloudKitSchemaPrimer")
    private static let environmentKey = "PLOTLOOM_PRIME_CLOUDKIT_SCHEMA"
    private static let launchArgument = "--prime-cloudkit-schema"
    private static let containerID = "iCloud.net.shadowpuppet.PlotLoom"
    private static let rootRecordType = "BookClubShareRoot"

    static func runIfRequested(modelContext: ModelContext) async {
        guard shouldRun else { return }

        var exitCode: Int32 = 0
        do {
            log("Starting CloudKit Development schema prime")
            try primeSwiftDataSchema(in: modelContext)
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

    private static func primeSwiftDataSchema(in modelContext: ModelContext) throws {
        let club = BookClub(name: "Schema Prime", createdAt: .now)
        let submission = BookSubmission(
            title: "Schema Prime",
            author: "PlotLoom",
            bookDescription: "Development-only record used to register CloudKit schema.",
            submittedBy: "PlotLoom",
            status: .proposed
        )
        let rating = Rating(memberName: "PlotLoom", stars: 5)
        let note = BookNote(memberName: "PlotLoom", text: "CloudKit schema prime")

        modelContext.insert(club)
        club.addSubmission(submission)
        submission.ratings = [rating]
        submission.notes = [note]
        try modelContext.save()
        log("Saved SwiftData schema-prime graph")
    }

    private static func primeShareSchema() async throws {
        let container = CKContainer(identifier: containerID)
        let status = try await container.accountStatus()
        guard status == .available else {
            throw PrimeError.iCloudAccountUnavailable(status)
        }

        let db = container.privateCloudDatabase
        let zone = CKRecordZone(zoneName: "BookClub-SchemaPrime-\(UUID().uuidString)")
        _ = try await db.modifyRecordZones(saving: [zone], deleting: [])

        let rootID = CKRecord.ID(recordName: "ShareRoot", zoneID: zone.zoneID)
        let root = CKRecord(recordType: rootRecordType, recordID: rootID)
        root["clubName"] = "Schema Prime" as CKRecordValue

        let share = CKShare(rootRecord: root)
        share[CKShare.SystemFieldKey.title] = "Book Club: Schema Prime" as CKRecordValue
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
