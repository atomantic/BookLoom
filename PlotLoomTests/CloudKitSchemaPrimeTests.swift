import CloudKit
import XCTest

final class CloudKitSchemaPrimeTests: XCTestCase {
    func test_primeShareSchemaWhenExplicitlyEnabled() async throws {
        guard ProcessInfo.processInfo.environment["PLOTLOOM_PRIME_CLOUDKIT_SCHEMA"] == "1" else {
            throw XCTSkip("Set PLOTLOOM_PRIME_CLOUDKIT_SCHEMA=1 to create CloudKit Development share schema.")
        }

        let container = CKContainer(identifier: "iCloud.net.shadowpuppet.PlotLoom")
        let status = try await container.accountStatus()
        XCTAssertEqual(status, .available, "Simulator/device must be signed into iCloud before priming CloudKit schema.")

        let db = container.privateCloudDatabase
        let zone = CKRecordZone(zoneName: "BookClub-SchemaPrime-\(UUID().uuidString)")
        _ = try await db.modifyRecordZones(saving: [zone], deleting: [])

        let rootID = CKRecord.ID(recordName: "ShareRoot", zoneID: zone.zoneID)
        let root = CKRecord(recordType: "BookClubShareRoot", recordID: rootID)
        root["clubName"] = "Schema Prime" as CKRecordValue

        let share = CKShare(rootRecord: root)
        share[CKShare.SystemFieldKey.title] = "Book Club: Schema Prime" as CKRecordValue
        share.publicPermission = .none

        _ = try await db.modifyRecords(saving: [root, share], deleting: [])

        // The schema is registered the moment CloudKit accepts the save above —
        // tear the zone back down so repeated priming runs don't accumulate
        // zones in the developer's Development container.
        _ = try? await db.modifyRecordZones(saving: [], deleting: [zone.zoneID])
    }
}
