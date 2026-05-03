import CloudKit
import XCTest
@testable import BookLoom

final class CloudKitSchemaPrimeTests: XCTestCase {
    func test_primeShareSchemaWhenExplicitlyEnabled() async throws {
        guard ProcessInfo.processInfo.environment["BOOKLOOM_PRIME_CLOUDKIT_SCHEMA"] == "1" else {
            throw XCTSkip("Set BOOKLOOM_PRIME_CLOUDKIT_SCHEMA=1 to create CloudKit Development share schema.")
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
        root["clubCreatedAt"] = Date.now as CKRecordValue

        let memberID = CKRecord.ID(recordName: "MemberSnapshot-schema-prime", zoneID: zone.zoneID)
        let memberRecord = CKRecord(recordType: "MemberShareSnapshot", recordID: memberID)
        memberRecord.parent = CKRecord.Reference(record: root, action: .none)
        let snapshot = MemberShareSnapshot(
            authorMemberID: "schema-prime",
            authorName: "Schema Prime",
            clubMeta: MemberShareSnapshot.ClubMeta(
                name: "Schema Prime",
                createdAt: .now,
                cloudZoneName: zone.zoneID.zoneName,
                shareParticipantCount: 1
            )
        )
        memberRecord["snapshotData"] = try JSONEncoder().encode(snapshot) as NSData
        memberRecord["snapshotUpdatedAt"] = snapshot.capturedAt as CKRecordValue
        memberRecord["memberID"] = snapshot.authorMemberID as CKRecordValue
        memberRecord["memberName"] = snapshot.authorName as CKRecordValue

        let share = CKShare(rootRecord: root)
        share[CKShare.SystemFieldKey.title] = "Book Club: Schema Prime" as CKRecordValue
        share.publicPermission = .readWrite

        _ = try await db.modifyRecords(saving: [root, memberRecord, share], deleting: [])

        // The schema is registered the moment CloudKit accepts the save above —
        // tear the zone back down so repeated priming runs don't accumulate
        // zones in the developer's Development container.
        _ = try? await db.modifyRecordZones(saving: [], deleting: [zone.zoneID])
    }
}
