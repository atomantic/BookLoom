import Foundation
import SwiftData
import XCTest
@testable import BookLoom

/// Coverage adjacent to the mass-delete failure mode that issue #25 fixed.
///
/// `MemberShareSnapshotStore.merge` indexes the club's existing local rows
/// (step 2) with `try context.fetch(...)` rather than `try?`. The earlier bug
/// swallowed a failing fetch with `try?`, handing the delete passes (steps
/// 5/6/7/8) an EMPTY "existing" index against a full canonical set — which then
/// deleted every remote-authored row on a transient read failure. The fix makes
/// the fetch failure propagate so `merge()` aborts BEFORE any delete pass runs.
///
/// BLOCKED — the actual fetch-failure abort path cannot be induced from test
/// code without a production seam. An in-memory `ModelContext` does not throw
/// from `FetchDescriptor` fetches on demand (even a container whose schema
/// omits the child types returns empty rather than throwing), so there is no
/// way to drive a `try context.fetch` failure inside `merge` from outside.
/// Verifying the abort-before-delete branch directly would require injecting a
/// fetch seam into `MemberShareSnapshotStore` (a production change, not made
/// here). A follow-up that adds such a seam could assert: (1) `merge` rethrows,
/// and (2) `club.lastSharedSnapshotAt` — stamped only at the very end of a
/// successful merge (step 12) — stays untouched, proving no delete/save ran.
///
/// What IS feasible and falsifiable: the non-corrupted baseline the fix
/// protects — a remote-authored row present in the canonical set survives a
/// successful merge (a populated "existing" index reconciles instead of
/// deleting). That is asserted below.
@MainActor
final class MemberShareSnapshotMergeAbortTests: XCTestCase {

    /// The non-corrupted baseline: on a fully-wired context, a remote row
    /// that IS present in the canonical set survives the merge. This is the
    /// non-corrupted baseline the #25 fix protects — a populated "existing"
    /// index reconciles instead of deleting.
    func test_merge_preservesRemoteRowWhenCanonicalStillContainsIt() throws {
        let context = try makeFullContext()
        let club = BookClub(name: "Sunday Pages")
        club.cloudZoneName = "BookClub-MergeOK"
        club.shareIsActive = true
        context.insert(club)

        // Seed an existing remote-authored submission locally.
        let existing = BookSubmission(
            title: "Remote Book",
            submittedBy: "Alex",
            submittedByMemberID: "member-alex",
            status: .proposed
        )
        existing.selectionID = "sel-remote"
        context.insert(existing)
        club.addSubmission(existing)
        try context.save()

        let remote = MemberShareSnapshot(
            capturedAt: Date(timeIntervalSince1970: 9_000),
            authorMemberID: "member-alex",
            authorName: "Alex",
            submissions: [
                MemberShareSnapshot.SubmissionPayload(
                    selectionID: "sel-remote",
                    title: "Remote Book",
                    author: "Alex",
                    isbn: "",
                    submittedBy: "Alex",
                    submittedByMemberID: "member-alex",
                    submittedAt: Date(timeIntervalSince1970: 1_100),
                    initialStatusRaw: BookSubmissionStatus.proposed.rawValue,
                    initialPickedAt: nil,
                    initialCompletedAt: nil,
                    bookDescription: "",
                    publishedYear: nil,
                    coverURL: "",
                    externalProvider: "",
                    externalID: ""
                )
            ]
        )

        try MemberShareSnapshotStore.merge(
            snapshots: [remote],
            into: club,
            context: context,
            localMemberID: "member-eve"
        )

        let surviving = (try context.fetch(FetchDescriptor<BookSubmission>()))
            .filter { $0.bookClub?.persistentModelID == club.persistentModelID }
        XCTAssertEqual(surviving.map(\.selectionID), ["sel-remote"], "A remote row still in canonical must survive merge")
    }

    private func makeFullContext() throws -> ModelContext {
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
