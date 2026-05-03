import CloudKit
import XCTest
@testable import BookLoom

final class CKZoneAvailabilityTests: XCTestCase {
    func test_zoneNotFoundClassifiedAsRemoved() {
        let error = NSError(domain: CKErrorDomain, code: CKError.zoneNotFound.rawValue)
        XCTAssertEqual(CKZoneAvailability.classify(error), .zoneRemoved)
    }

    func test_userDeletedZoneClassifiedAsRemoved() {
        let error = NSError(domain: CKErrorDomain, code: CKError.userDeletedZone.rawValue)
        XCTAssertEqual(CKZoneAvailability.classify(error), .zoneRemoved)
    }

    func test_unknownItemClassifiedAsRemoved() {
        let error = NSError(domain: CKErrorDomain, code: CKError.unknownItem.rawValue)
        XCTAssertEqual(CKZoneAvailability.classify(error), .zoneRemoved)
    }

    func test_networkUnavailableNotClassifiedAsRemoved() {
        let error = NSError(domain: CKErrorDomain, code: CKError.networkUnavailable.rawValue)
        XCTAssertEqual(CKZoneAvailability.classify(error), .available)
    }

    func test_partialErrorContainingZoneNotFoundClassifiedAsRemoved() {
        let inner = NSError(domain: CKErrorDomain, code: CKError.zoneNotFound.rawValue)
        let recordID = CKRecord.ID(recordName: "any", zoneID: CKRecordZone.ID(zoneName: "Z"))
        let error = NSError(
            domain: CKErrorDomain,
            code: CKError.partialFailure.rawValue,
            userInfo: [CKPartialErrorsByItemIDKey: [recordID: inner]]
        )
        XCTAssertEqual(CKZoneAvailability.classify(error), .zoneRemoved)
    }

    func test_nonCloudKitErrorClassifiedAsAvailable() {
        let error = NSError(domain: NSURLErrorDomain, code: NSURLErrorTimedOut)
        XCTAssertEqual(CKZoneAvailability.classify(error), .available)
    }
}
