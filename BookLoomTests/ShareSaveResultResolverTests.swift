import CloudKit
import XCTest
@testable import BookLoom

final class ShareSaveResultResolverTests: XCTestCase {
    func test_returnsSavedShareWhenCloudKitIncludesItInResults() throws {
        let root = CKRecord(recordType: "BookClubShareRoot")
        let share = CKShare(rootRecord: root)

        let resolution = try ShareSaveResultResolver.resolve(
            saveResults: [share.recordID: .success(share)],
            fallback: CKShare(rootRecord: root)
        )

        XCTAssertTrue(resolution.share === share)
        XCTAssertFalse(resolution.needsHydration)
    }

    func test_fallsBackToCreatedShareWhenModifyRecordsSucceededWithoutShareResult() throws {
        let root = CKRecord(recordType: "BookClubShareRoot")
        let fallback = CKShare(rootRecord: root)

        let resolution = try ShareSaveResultResolver.resolve(
            saveResults: [root.recordID: .success(root)],
            fallback: fallback
        )

        XCTAssertTrue(resolution.share === fallback)
        XCTAssertTrue(resolution.needsHydration)
    }

    func test_throwsPerRecordFailureWhenCloudKitReportsOne() {
        let root = CKRecord(recordType: "BookClubShareRoot")
        let fallback = CKShare(rootRecord: root)
        let error = NSError(domain: CKErrorDomain, code: CKError.serverRejectedRequest.rawValue)

        XCTAssertThrowsError(
            try ShareSaveResultResolver.resolve(
                saveResults: [root.recordID: .failure(error)],
                fallback: fallback
            )
        )
    }
}
