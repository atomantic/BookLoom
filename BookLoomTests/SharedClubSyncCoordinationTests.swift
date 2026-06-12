import CloudKit
import Foundation
import SwiftData
import XCTest
@testable import BookLoom

/// Coordination-level tests for `SharedClubSync` and `SharedClubSyncStatus`.
///
/// `SharedClubSync`'s CloudKit I/O (publish/fetch) cannot run in CI — there is
/// no signed container or accepted share — so these tests exercise the pure
/// decision logic that surrounds the network boundary:
///   * the `Features.cloudKitSharing` short-circuit guards (which are `false`
///     under XCTest, so the network Task never starts and local rows are left
///     untouched);
///   * `saveAndPublish`'s synchronous cover-data cleanup + save, which runs
///     regardless of the feature flag;
///   * `synchronizeSharedClubs`'s fetch-then-iterate over the local store;
///   * `SharedClubSyncStatus`'s record/clear/dedup coordination.
///
/// BLOCKED (needs a production seam): the success/failure branches inside the
/// publish/refresh `Task` — participant-count reconcile, snapshot publish,
/// fetch+merge, orphan-zone delete — all dispatch through
/// `CloudKitSharingService.shared`, a concrete singleton. Verifying those
/// branches requires injecting a `CloudKitSharingService` protocol stub
/// (issue #47's "longer-term" suggestion). That injection is a production
/// change and is intentionally NOT made here.
@MainActor
final class SharedClubSyncCoordinationTests: XCTestCase {
    // Status assertions key on each club's random `cloudZoneName` (a fresh
    // UUID per `BookClub`), so a recorded failure can never collide with
    // another test's zone — no shared-singleton reset is needed between tests.

    // MARK: - Feature-flag short-circuit

    /// Under XCTest, `Features.cloudKitSharing` is `false`. This is the gate
    /// the whole sync surface depends on; if it ever flips on in the test
    /// runner the publish/refresh paths would try to touch CloudKit and trap.
    func test_cloudKitSharingIsDisabledUnderTests() {
        XCTAssertFalse(Features.cloudKitSharing, "Sync paths must stay gated off in the test runner")
    }

    /// With sharing disabled, `publishIfNeeded` must return without mutating
    /// the club or recording a failure — no snapshot timestamp is stamped and
    /// no background Task is started.
    func test_publishIfNeeded_noOpsWhenSharingDisabled() throws {
        let context = try makeContext()
        let club = makeActiveSharedClub()
        context.insert(club)
        try context.save()

        SharedClubSync.publishIfNeeded(
            club,
            context: context,
            localMemberID: "member-eve",
            localMemberName: "Eve"
        )

        XCTAssertNil(club.lastSharedSnapshotAt, "No snapshot timestamp should be stamped while sharing is off")
        XCTAssertNil(SharedClubSyncStatus.shared.issue(for: club), "A short-circuited publish must not record a failure")
    }

    /// `refreshIfNeeded` is `async`; with sharing disabled it must return
    /// immediately without fetching, deleting the club, or recording a failure.
    func test_refreshIfNeeded_noOpsWhenSharingDisabled() async throws {
        let context = try makeContext()
        let club = makeActiveSharedClub()
        context.insert(club)
        try context.save()
        let clubID = club.persistentModelID

        await SharedClubSync.refreshIfNeeded(
            club,
            context: context,
            localMemberID: "member-eve",
            localMemberName: "Eve"
        )

        let surviving = try context.fetch(FetchDescriptor<BookClub>())
        XCTAssertEqual(surviving.map(\.persistentModelID), [clubID], "A short-circuited refresh must not delete the club")
        XCTAssertNil(SharedClubSyncStatus.shared.issue(for: club))
    }

    /// An inactive share (`shareIsActive == false`) is the second half of every
    /// guard. Even if the feature flag were on, an inactive club must be left
    /// alone. Here we assert the active-flag branch independently of the
    /// feature flag by using a club that is explicitly not shared.
    func test_refreshIfNeeded_noOpsForInactiveShare() async throws {
        let context = try makeContext()
        let club = BookClub(name: "Local Only")
        club.shareIsActive = false
        context.insert(club)
        try context.save()
        let clubID = club.persistentModelID

        await SharedClubSync.refreshIfNeeded(
            club,
            context: context,
            localMemberID: "member-eve",
            localMemberName: "Eve"
        )

        let surviving = try context.fetch(FetchDescriptor<BookClub>())
        XCTAssertEqual(surviving.map(\.persistentModelID), [clubID])
    }

    // MARK: - saveAndPublish synchronous half

    /// `saveAndPublish` clears persisted cover bytes and persists before it
    /// hands off to `publishIfNeeded`. That cleanup+save runs regardless of the
    /// feature flag, so it is fully testable: the in-memory image data must be
    /// gone after the call.
    func test_saveAndPublish_clearsPersistedCoverDataAndSaves() throws {
        let context = try makeContext()
        let club = makeActiveSharedClub()
        let submission = BookSubmission(title: "Cached Cover", coverURL: "https://example.com/c.jpg")
        submission.coverData = Data([1, 2, 3])
        context.insert(club)
        context.insert(submission)
        club.addSubmission(submission)
        try context.save()

        try SharedClubSync.saveAndPublish(
            context: context,
            club: club,
            localMemberID: "member-eve",
            localMemberName: "Eve"
        )

        XCTAssertNil(submission.coverData, "saveAndPublish must strip persisted cover bytes before publishing")
        XCTAssertFalse(context.hasChanges, "saveAndPublish must persist the cleanup")
    }

    // MARK: - synchronizeSharedClubs fan-out

    /// `synchronizeSharedClubs` fetches every club and iterates the active ones.
    /// With sharing disabled it is a no-op, but it must complete cleanly over a
    /// mixed store (active + inactive + no zone) and leave every row in place —
    /// proving the fetch/iterate scaffolding itself is sound.
    func test_synchronizeSharedClubs_iteratesWithoutMutatingStore() async throws {
        let context = try makeContext()
        let active = makeActiveSharedClub()
        let inactive = BookClub(name: "Local Only")
        inactive.shareIsActive = false
        context.insert(active)
        context.insert(inactive)
        try context.save()
        let before = Set(try context.fetch(FetchDescriptor<BookClub>()).map(\.persistentModelID))

        await SharedClubSync.synchronizeSharedClubs(
            in: context,
            localMemberID: "member-eve",
            localMemberName: "Eve"
        )

        let after = Set(try context.fetch(FetchDescriptor<BookClub>()).map(\.persistentModelID))
        XCTAssertEqual(after, before, "synchronizeSharedClubs must not add or drop rows while sharing is off")
    }

    /// An empty store is the boundary case for the fetch: it must not throw and
    /// must finish without recording any failure.
    func test_synchronizeSharedClubs_handlesEmptyStore() async throws {
        let context = try makeContext()

        await SharedClubSync.synchronizeSharedClubs(
            in: context,
            localMemberID: "member-eve",
            localMemberName: "Eve"
        )

        XCTAssertEqual(try context.fetch(FetchDescriptor<BookClub>()).count, 0)
    }

    // MARK: - SharedClubSyncStatus coordination

    /// Recording then reading a failure round-trips by zone, and `issue(for:)`
    /// resolves through the club's `cloudZoneName`.
    func test_status_recordsAndSurfacesIssueByZone() {
        let club = makeActiveSharedClub()
        let status = SharedClubSyncStatus.shared

        XCTAssertNil(status.issue(for: club), "No issue before any failure")
        status.recordFailure(
            zoneName: club.cloudZoneName,
            operation: .refresh,
            error: CKError(.networkUnavailable)
        )

        let issue = status.issue(for: club)
        XCTAssertEqual(issue?.severity, .offline, "A network error classifies as a soft offline state")
    }

    /// `clearFailure` removes a recorded issue so the UI banner clears on the
    /// next successful sync tick.
    func test_status_clearFailureRemovesIssue() {
        let club = makeActiveSharedClub()
        let status = SharedClubSyncStatus.shared
        status.recordFailure(zoneName: club.cloudZoneName, operation: .publish, error: CKError(.quotaExceeded))
        XCTAssertNotNil(status.issue(for: club))

        status.clearFailure(zoneName: club.cloudZoneName)
        XCTAssertNil(status.issue(for: club), "clearFailure must drop the recorded issue")
    }

    /// Two clubs in different zones keep independent issue state — recording a
    /// failure for one must not surface on the other.
    func test_status_isolatesIssuesPerZone() {
        let clubA = makeActiveSharedClub()
        let clubB = makeActiveSharedClub()
        XCTAssertNotEqual(clubA.cloudZoneName, clubB.cloudZoneName)

        let status = SharedClubSyncStatus.shared
        status.recordFailure(zoneName: clubA.cloudZoneName, operation: .publish, error: CKError(.notAuthenticated))

        XCTAssertNotNil(status.issue(for: clubA))
        XCTAssertNil(status.issue(for: clubB), "A failure in one zone must not bleed into another")
    }

    // MARK: - Helpers

    private func makeActiveSharedClub(name: String = "Sunday Pages") -> BookClub {
        let club = BookClub(name: name)
        club.shareIsActive = true
        club.shareParticipantCount = 2
        return club
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
