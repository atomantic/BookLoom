import CloudKit
import XCTest
@testable import BookLoom

final class SyncIssueTests: XCTestCase {
    func test_networkErrorsRenderAsOfflineIndicator() {
        for code in [CKError.networkUnavailable.rawValue, CKError.networkFailure.rawValue] {
            let error = NSError(domain: CKErrorDomain, code: code)
            let issue = SyncIssue.classify(error, operation: .refresh)
            XCTAssertEqual(issue.severity, .offline, "CKError code \(code) should be offline severity")
            XCTAssertEqual(issue.systemImage, "icloud.slash")
            XCTAssertFalse(issue.message.contains("CKError"), "User-facing copy must not leak CKError text")
        }
    }

    func test_urlSessionNetworkErrorRendersAsOffline() {
        let error = NSError(domain: NSURLErrorDomain, code: NSURLErrorNotConnectedToInternet)
        let issue = SyncIssue.classify(error, operation: .publish)
        XCTAssertEqual(issue.severity, .offline)
    }

    func test_transientServiceErrorsRenderAsOffline() {
        for code in [CKError.serviceUnavailable.rawValue, CKError.requestRateLimited.rawValue, CKError.zoneBusy.rawValue] {
            let error = NSError(domain: CKErrorDomain, code: code)
            let issue = SyncIssue.classify(error, operation: .refresh)
            XCTAssertEqual(issue.severity, .offline, "CKError code \(code) should be offline severity")
        }
    }

    func test_authErrorsRenderAsActionableWarning() {
        let issue = SyncIssue.classify(
            NSError(domain: CKErrorDomain, code: CKError.notAuthenticated.rawValue),
            operation: .refresh
        )
        XCTAssertEqual(issue.severity, .warning)
        XCTAssertEqual(issue.title, "Sign in to iCloud")
    }

    func test_quotaExceededRendersAsActionableWarning() {
        let issue = SyncIssue.classify(
            NSError(domain: CKErrorDomain, code: CKError.quotaExceeded.rawValue),
            operation: .publish
        )
        XCTAssertEqual(issue.severity, .warning)
        XCTAssertEqual(issue.title, "iCloud storage is full")
    }

    func test_partialFailureUnwrapsInnerNetworkErrorToOffline() {
        let recordID = CKRecord.ID(recordName: "snapshot-1")
        let inner = NSError(domain: CKErrorDomain, code: CKError.networkFailure.rawValue)
        let partial = NSError(
            domain: CKErrorDomain,
            code: CKError.partialFailure.rawValue,
            userInfo: [CKPartialErrorsByItemIDKey: [recordID: inner]]
        )
        let issue = SyncIssue.classify(partial, operation: .publish)
        XCTAssertEqual(issue.severity, .offline)
        XCTAssertEqual(issue.systemImage, "icloud.slash")
    }

    func test_missingOwnerTrustRendersAsNonDestructiveWaitingState() {
        let issue = SyncIssue.classify(
            MemberSnapshotAuthorizationError(rejectedRecordNames: []),
            operation: .refresh
        )

        XCTAssertEqual(issue.severity, .offline)
        XCTAssertEqual(issue.title, "Waiting for Club data")
        XCTAssertTrue(issue.message.contains("local data"))
    }

    func test_rejectedSnapshotRendersAsSpecificVerificationWarning() {
        let issue = SyncIssue.classify(
            MemberSnapshotAuthorizationError(
                rejectedRecordNames: ["MemberSnapshot-member-sam"]
            ),
            operation: .refresh
        )

        XCTAssertEqual(issue.severity, .warning)
        XCTAssertEqual(issue.title, "Club data needs attention")
        XCTAssertFalse(issue.message.contains("MemberSnapshot"))
    }

    func test_rejectedSnapshotGivesOwnerRelevantRecoveryCopy() {
        let issue = SyncIssue.classify(
            MemberSnapshotAuthorizationError(
                rejectedRecordNames: ["MemberSnapshot-member-sam"]
            ),
            operation: .refresh,
            isShareOwner: true
        )

        XCTAssertEqual(issue.severity, .warning)
        XCTAssertTrue(issue.message.contains("each current member"))
        XCTAssertFalse(issue.message.contains("Ask the Club owner"))
    }

    func test_unknownErrorPicksFriendlyOperationCopy() {
        let error = NSError(domain: "ExampleDomain", code: 42, userInfo: [
            NSLocalizedDescriptionKey: "Specific failure"
        ])

        let publishIssue = SyncIssue.classify(error, operation: .publish)
        XCTAssertEqual(publishIssue.severity, .warning)
        XCTAssertEqual(publishIssue.title, "Couldn't share latest changes")
        XCTAssertFalse(publishIssue.message.contains("ExampleDomain"))

        let refreshIssue = SyncIssue.classify(error, operation: .refresh)
        XCTAssertEqual(refreshIssue.title, "Couldn't fetch latest changes")
    }
}
