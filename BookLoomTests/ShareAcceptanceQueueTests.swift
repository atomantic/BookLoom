import XCTest
import CloudKit
@testable import BookLoom

@MainActor
final class ShareAcceptanceQueueTests: XCTestCase {
    private enum TestError: Error {
        case unavailable
    }

    func testSuccessRemovesPendingShareAndPublishesSucceededState() async {
        let queue = ShareAcceptanceQueue<String>(identifier: { $0 })
        queue.configure { _ in "The Readers" }

        queue.enqueue("share-1")
        await waitUntilSettled(queue)

        XCTAssertEqual(queue.state, .succeeded(clubName: "The Readers"))
        XCTAssertEqual(queue.pendingCount, 0)
    }

    func testTransientFailurePreservesShareForRetry() async {
        let queue = ShareAcceptanceQueue<String>(identifier: { $0 })
        var attempts = 0
        queue.configure { _ in
            attempts += 1
            if attempts == 1 { throw TestError.unavailable }
            return "Retry Club"
        }

        queue.enqueue("share-2")
        await waitUntilSettled(queue)
        guard case .failed = queue.state else {
            return XCTFail("Expected the first attempt to fail")
        }
        XCTAssertEqual(queue.pendingCount, 1)

        queue.retry()
        await waitUntilSettled(queue)

        XCTAssertEqual(attempts, 2)
        XCTAssertEqual(queue.state, .succeeded(clubName: "Retry Club"))
        XCTAssertEqual(queue.pendingCount, 0)
    }

    func testPermanentFailureRemainsPendingUntilDismissed() async {
        let queue = ShareAcceptanceQueue<String>(identifier: { $0 })
        queue.configure { _ in throw TestError.unavailable }

        queue.enqueue("share-3")
        await waitUntilSettled(queue)

        guard case .failed(let message, let retryable) = queue.state else {
            return XCTFail("Expected a visible failure")
        }
        XCTAssertFalse(message.isEmpty)
        XCTAssertTrue(retryable)
        XCTAssertEqual(queue.pendingCount, 1)

        queue.dismiss()

        XCTAssertEqual(queue.state, .idle)
        XCTAssertEqual(queue.pendingCount, 0)
    }

    func testDuplicateDeliveryAndOverlappingRetryImportOnce() async {
        let queue = ShareAcceptanceQueue<String>(identifier: { $0 })
        var attempts = 0
        queue.configure { _ in
            attempts += 1
            try await Task.sleep(for: .milliseconds(30))
            return "Only Once"
        }

        XCTAssertTrue(queue.enqueue("share-4"))
        XCTAssertFalse(queue.enqueue("share-4"))
        queue.retry()
        await waitUntilSettled(queue)

        XCTAssertEqual(attempts, 1)
        XCTAssertEqual(queue.state, .succeeded(clubName: "Only Once"))
        XCTAssertFalse(queue.enqueue("share-4"))

        queue.dismiss()
        XCTAssertTrue(queue.enqueue("share-4"), "Acknowledging success must permit a legitimate later rejoin")
    }

    func testFailureMessagesGiveActionableRecoveryGuidance() {
        let notAuthenticated = NSError(domain: CKErrorDomain, code: CKError.notAuthenticated.rawValue)
        XCTAssertTrue(ShareAcceptance.failureMessage(for: notAuthenticated).contains("Sign in to iCloud"))

        let permissionFailure = NSError(domain: CKErrorDomain, code: CKError.permissionFailure.rawValue)
        XCTAssertTrue(ShareAcceptance.failureMessage(for: permissionFailure).contains("new invitation"))
        XCTAssertFalse(ShareAcceptance.isRetryable(permissionFailure))

        let removedShare = SharingError.shareAccessRemoved
        XCTAssertTrue(ShareAcceptance.failureMessage(for: removedShare).contains("new invitation"))
        XCTAssertFalse(ShareAcceptance.isRetryable(removedShare))
    }

    func testEnqueuedBeforeConfigurationStartsWhenConfigured() async {
        let queue = ShareAcceptanceQueue<String>(identifier: { $0 })
        XCTAssertTrue(queue.enqueue("early-share"))
        XCTAssertEqual(queue.state, .idle)

        queue.configure { _ in "Early Club" }
        await waitUntilSettled(queue)

        XCTAssertEqual(queue.state, .succeeded(clubName: "Early Club"))
    }

    func testQueuedSharesRunSeriallyAfterSuccessIsDismissed() async {
        let queue = ShareAcceptanceQueue<String>(identifier: { $0 })
        var accepted: [String] = []
        queue.configure { payload in
            accepted.append(payload)
            return payload
        }

        queue.enqueue("first")
        queue.enqueue("second")
        await waitUntilSettled(queue)
        XCTAssertEqual(accepted, ["first"])
        XCTAssertEqual(queue.pendingCount, 1)

        queue.dismiss()
        await waitUntilSettled(queue)
        XCTAssertEqual(accepted, ["first", "second"])
    }

    func testDeferredAlertDismissDoesNotDiscardRetry() async {
        let queue = ShareAcceptanceQueue<String>(identifier: { $0 })
        var attempts = 0
        queue.configure { _ in
            attempts += 1
            if attempts == 1 { throw TestError.unavailable }
            return "Recovered Club"
        }
        queue.enqueue("share")
        await waitUntilSettled(queue)

        let failedState = queue.state
        queue.retry()
        queue.dismissAlert(ifUnchangedFrom: failedState)
        await waitUntilSettled(queue)

        XCTAssertEqual(queue.state, .succeeded(clubName: "Recovered Club"))
        XCTAssertEqual(attempts, 2)
    }

    private func waitUntilSettled(_ queue: ShareAcceptanceQueue<String>) async {
        for _ in 0..<100 {
            guard queue.state == .accepting else { return }
            try? await Task.sleep(for: .milliseconds(5))
        }
        XCTFail("Share acceptance did not settle before the test timeout")
    }
}
