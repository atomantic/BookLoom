import XCTest
import CloudKit
import SwiftData
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

    func testMaterializingAcceptedSharePersistsUntilFirstSuccessfulSync() async throws {
        let context = try makeContext()
        let info = AcceptedShareInfo(
            zoneName: "BookClub-Materializing",
            ownerUserRecordName: "cloud-owner",
            title: "Newly Joined",
            participantCount: 2,
            memberSnapshotBatch: MemberSnapshotBatch(
                ownerUserRecordName: "cloud-owner",
                approvedParticipantUserRecordNames: ["cloud-owner", "cloud-eve"],
                snapshots: []
            ),
            isMaterializing: true
        )

        let name = try await ShareAcceptance.importAcceptedShare(
            info,
            context: context,
            localMemberID: "member-eve",
            localMemberName: "Eve"
        )

        let club = try XCTUnwrap(context.fetch(FetchDescriptor<BookClub>()).first)
        XCTAssertEqual(name, "Newly Joined")
        XCTAssertEqual(club.ownerUserRecordName, "cloud-owner")
        XCTAssertTrue(club.shareIsActive)
        XCTAssertTrue(club.shareAwaitingInitialSync, "A transient unknown-item refresh must not delete a newly accepted club")
    }

    func testAcceptedShareRejectsSameZoneFromDifferentOwnerWithoutMutation() async throws {
        let context = try makeContext()
        let existing = BookClub(name: "My Private Club")
        existing.cloudZoneName = "BookClub-Collision"
        existing.shareIsActive = true
        context.insert(existing)
        try context.save()
        let existingID = existing.persistentModelID

        let info = AcceptedShareInfo(
            zoneName: existing.cloudZoneName,
            ownerUserRecordName: "attacker-owner",
            title: "Lookalike Club",
            participantCount: 2,
            memberSnapshotBatch: MemberSnapshotBatch(
                ownerUserRecordName: "attacker-owner",
                approvedParticipantUserRecordNames: ["attacker-owner"],
                snapshots: []
            )
        )

        do {
            _ = try await ShareAcceptance.importAcceptedShare(
                info,
                context: context,
                localMemberID: "member-eve",
                localMemberName: "Eve"
            )
            XCTFail("Owner-scoped zone collision should be rejected")
        } catch SharingError.conflictingLocalClub {
            // Expected: zone name alone is not a globally unique share identity.
        }

        let clubs = try context.fetch(FetchDescriptor<BookClub>())
        XCTAssertEqual(clubs.map(\.persistentModelID), [existingID])
        XCTAssertEqual(existing.name, "My Private Club")
        XCTAssertNil(existing.ownerUserRecordName)
    }

    func testNativeSharingStateTracksSaveAndStopCallbacks() throws {
        let context = try makeContext()
        let club = BookClub(name: "Callback Club")
        club.shareAwaitingInitialSync = true
        club.inviteURLString = "https://example.invalid/invite"
        club.lastSharedSnapshotAt = Date(timeIntervalSince1970: 123)
        context.insert(club)
        try context.save()

        let root = CKRecord(
            recordType: "BookClub",
            recordID: CKRecord.ID(
                recordName: "BookClubRoot",
                zoneID: CKRecordZone.ID(zoneName: club.cloudZoneName)
            )
        )
        let share = CKShare(rootRecord: root)
        try ClubSharingState.recordSavedShare(share, for: club, context: context)
        XCTAssertTrue(club.shareIsActive)
        XCTAssertFalse(club.shareAwaitingInitialSync)
        XCTAssertGreaterThanOrEqual(club.shareParticipantCount, 1)

        try ClubSharingState.recordStoppedSharing(for: club, context: context)
        XCTAssertFalse(club.shareIsActive)
        XCTAssertFalse(club.shareAwaitingInitialSync)
        XCTAssertEqual(club.shareParticipantCount, 1)
        XCTAssertTrue(club.inviteURLString.isEmpty)
        XCTAssertNil(club.lastSharedSnapshotAt)
    }

    func testConfirmedRemovalRequiresEveryCloudKitPartialFailureToBeAbsent() {
        XCTAssertTrue(CKZoneAvailability.confirmsRemoval(CKError(.unknownItem)))
        XCTAssertFalse(CKZoneAvailability.confirmsRemoval(CKError(.networkUnavailable)))

        let allAbsent = NSError(
            domain: CKErrorDomain,
            code: CKError.partialFailure.rawValue,
            userInfo: [
                CKPartialErrorsByItemIDKey: [
                    AnyHashable("first"): CKError(.unknownItem),
                    AnyHashable("second"): CKError(.zoneNotFound)
                ] as [AnyHashable: Error]
            ]
        )
        XCTAssertTrue(CKZoneAvailability.confirmsRemoval(allAbsent))

        let mixed = NSError(
            domain: CKErrorDomain,
            code: CKError.partialFailure.rawValue,
            userInfo: [
                CKPartialErrorsByItemIDKey: [
                    AnyHashable("gone"): CKError(.unknownItem),
                    AnyHashable("offline"): CKError(.networkUnavailable)
                ] as [AnyHashable: Error]
            ]
        )
        XCTAssertFalse(CKZoneAvailability.confirmsRemoval(mixed), "A transient partial failure must keep destructive cleanup fail-closed")
    }

    private func waitUntilSettled(_ queue: ShareAcceptanceQueue<String>) async {
        for _ in 0..<100 {
            guard queue.state == .accepting else { return }
            try? await Task.sleep(for: .milliseconds(5))
        }
        XCTFail("Share acceptance did not settle before the test timeout")
    }

    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: BookClub.self,
            BookSubmission.self,
            Rating.self,
            BookNote.self,
            ClubMeeting.self,
            MeetingRSVP.self,
            SelectionPoll.self,
            BookVote.self,
            DiscussionPrompt.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return ModelContext(container)
    }
}
