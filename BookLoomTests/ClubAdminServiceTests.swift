import Foundation
import SwiftData
import XCTest
@testable import BookLoom

/// Tests for `ClubAdminService`, the `@MainActor` orchestrator extracted from
/// `ClubManagementView` (delete/leave, remove member, toggle admin, rename,
/// creator backfill).
///
/// Each method chains a SwiftData mutation with CloudKit + sync calls. Under
/// XCTest `Features.cloudKitSharing` is `false`, so the CloudKit half
/// short-circuits and the local SwiftData mutation + save runs in isolation —
/// which is exactly the layer these tests cover.
///
/// BLOCKED (needs a production seam): the CloudKit side-effects —
/// `removeMember`'s `removeMemberSnapshot` + post-delete refresh,
/// `cleanupBeforeDelete`'s zone delete / leave-share, and the snapshot publish
/// inside `saveAndPublish` — all route through the concrete
/// `CloudKitSharingService.shared` singleton and cannot be observed without a
/// protocol injection seam. That is a production change and is not made here.
@MainActor
final class ClubAdminServiceTests: XCTestCase {

    // MARK: - rename

    func test_rename_appliesTrimmedNameAndStampsTimestamp() throws {
        let context = try makeContext()
        let club = makeOwnedActiveClub(creator: "member-eve")
        context.insert(club)
        try context.save()

        let applied = try ClubAdminService.rename(
            club,
            to: "  Sunday Mornings  ",
            context: context,
            localMemberID: "member-eve",
            localMemberName: "Eve"
        )

        XCTAssertTrue(applied, "A real rename returns true")
        XCTAssertEqual(club.name, "Sunday Mornings", "Name is trimmed before applying")
        XCTAssertGreaterThan(club.nameUpdatedAt, .distantPast, "Rename stamps the tie-break clock")
    }

    func test_rename_isNoOpWhenNameUnchanged() throws {
        let context = try makeContext()
        let club = makeOwnedActiveClub(creator: "member-eve")
        club.name = "Sunday Pages"
        context.insert(club)
        try context.save()
        let originalStamp = club.nameUpdatedAt

        let applied = try ClubAdminService.rename(
            club,
            to: "Sunday Pages",
            context: context,
            localMemberID: "member-eve",
            localMemberName: "Eve"
        )

        XCTAssertFalse(applied, "Renaming to the same name is a no-op")
        XCTAssertEqual(club.nameUpdatedAt, originalStamp, "A no-op rename must not bump the timestamp")
    }

    func test_rename_isNoOpForBlankName() throws {
        let context = try makeContext()
        let club = makeOwnedActiveClub(creator: "member-eve")
        club.name = "Sunday Pages"
        context.insert(club)
        try context.save()

        let applied = try ClubAdminService.rename(
            club,
            to: "   ",
            context: context,
            localMemberID: "member-eve",
            localMemberName: "Eve"
        )

        XCTAssertFalse(applied, "A whitespace-only name trims to nil and is rejected")
        XCTAssertEqual(club.name, "Sunday Pages")
    }

    func test_rename_rejectedWhenCallerIsNotAdmin() throws {
        let context = try makeContext()
        // Creator is someone else; the local member has no admin rights.
        let club = makeOwnedActiveClub(creator: "member-alex")
        club.name = "Sunday Pages"
        context.insert(club)
        try context.save()

        let applied = try ClubAdminService.rename(
            club,
            to: "Hostile Takeover",
            context: context,
            localMemberID: "member-eve",
            localMemberName: "Eve"
        )

        XCTAssertFalse(applied, "A non-admin cannot rename the club")
        XCTAssertEqual(club.name, "Sunday Pages")
    }

    // MARK: - setAdmin

    func test_setAdmin_grantsAndRevokesAdminMembership() throws {
        let context = try makeContext()
        let club = makeOwnedActiveClub(creator: "member-eve")
        context.insert(club)
        try context.save()

        try ClubAdminService.setAdmin(
            true,
            memberID: "member-sam",
            in: club,
            context: context,
            localMemberID: "member-eve",
            localMemberName: "Eve"
        )
        XCTAssertTrue(club.isAdmin(memberID: "member-sam"), "Granting admin adds the member to the admin set")

        try ClubAdminService.setAdmin(
            false,
            memberID: "member-sam",
            in: club,
            context: context,
            localMemberID: "member-eve",
            localMemberName: "Eve"
        )
        XCTAssertFalse(club.isAdmin(memberID: "member-sam"), "Revoking admin removes the member from the admin set")
    }

    func test_setAdmin_cannotDemoteCreator() throws {
        let context = try makeContext()
        let club = makeOwnedActiveClub(creator: "member-eve")
        context.insert(club)
        try context.save()

        try ClubAdminService.setAdmin(
            false,
            memberID: "member-eve",
            in: club,
            context: context,
            localMemberID: "member-eve",
            localMemberName: "Eve"
        )

        XCTAssertTrue(club.isAdmin(memberID: "member-eve"), "The creator always counts as admin and can't be demoted")
    }

    // MARK: - removeMember

    func test_removeMember_marksMemberRemovedAndStripsAdmin() throws {
        let context = try makeContext()
        let club = makeOwnedActiveClub(creator: "member-eve")
        club.setAdmin(true, memberID: "member-sam")
        var roster = club.knownMemberRoster
        roster["member-sam"] = "Sam"
        club.knownMemberRoster = roster
        context.insert(club)
        try context.save()

        try ClubAdminService.removeMember(
            "member-sam",
            from: club,
            context: context,
            localMemberID: "member-eve",
            localMemberName: "Eve"
        )

        XCTAssertTrue(club.removedMemberIDs.contains("member-sam"), "Removed member is added to the removal list")
        XCTAssertFalse(club.isAdmin(memberID: "member-sam"), "A removed member loses admin status")
        XCTAssertNil(club.knownMemberRoster["member-sam"], "A removed member is dropped from the roster")
    }

    func test_removeMember_refusesToRemoveCreator() throws {
        let context = try makeContext()
        let club = makeOwnedActiveClub(creator: "member-eve")
        context.insert(club)
        try context.save()

        try ClubAdminService.removeMember(
            "member-eve",
            from: club,
            context: context,
            localMemberID: "member-eve",
            localMemberName: "Eve"
        )

        XCTAssertFalse(club.removedMemberIDs.contains("member-eve"), "The creator can never be removed")
    }

    func test_removeMember_ignoresEmptyMemberID() throws {
        let context = try makeContext()
        let club = makeOwnedActiveClub(creator: "member-eve")
        context.insert(club)
        try context.save()

        try ClubAdminService.removeMember(
            "",
            from: club,
            context: context,
            localMemberID: "member-eve",
            localMemberName: "Eve"
        )

        XCTAssertTrue(club.removedMemberIDs.isEmpty, "An empty memberID is a no-op")
    }

    // MARK: - backfillCreatorIfNeeded

    func test_backfillCreator_setsCreatorWhenAbsentAndOwner() throws {
        let context = try makeContext()
        let club = BookClub(name: "Legacy Club") // isOwner == true (no ownerUserRecordName)
        XCTAssertTrue(club.creatorMemberID.isEmpty)
        context.insert(club)
        try context.save()

        ClubAdminService.backfillCreatorIfNeeded(club, context: context, localMemberID: "member-eve")

        XCTAssertEqual(club.creatorMemberID, "member-eve", "A legacy owned club backfills the local member as creator")
    }

    func test_backfillCreator_isNoOpWhenAlreadySet() throws {
        let context = try makeContext()
        let club = BookClub(name: "Already Set")
        club.creatorMemberID = "member-original"
        context.insert(club)
        try context.save()

        ClubAdminService.backfillCreatorIfNeeded(club, context: context, localMemberID: "member-eve")

        XCTAssertEqual(club.creatorMemberID, "member-original", "An existing creator must not be overwritten")
    }

    func test_backfillCreator_isNoOpWhenNotOwner() throws {
        let context = try makeContext()
        let club = BookClub(name: "Joined Club")
        club.ownerUserRecordName = "remote-owner" // makes isOwner false
        context.insert(club)
        try context.save()

        ClubAdminService.backfillCreatorIfNeeded(club, context: context, localMemberID: "member-eve")

        XCTAssertTrue(club.creatorMemberID.isEmpty, "A participant (non-owner) must not claim creator")
    }

    func test_backfillCreator_isNoOpForEmptyLocalMember() throws {
        let context = try makeContext()
        let club = BookClub(name: "Owned, no identity yet")
        context.insert(club)
        try context.save()

        ClubAdminService.backfillCreatorIfNeeded(club, context: context, localMemberID: "")

        XCTAssertTrue(club.creatorMemberID.isEmpty, "An empty local member ID can't be backfilled as creator")
    }

    // MARK: - deleteClub

    func test_deleteClub_removesRowAndClearsActiveClubWhenActive() async throws {
        let context = try makeContext()
        let club = makeOwnedActiveClub(creator: "member-eve")
        context.insert(club)
        try context.save()

        let activeStore = ActiveClubStore()
        activeStore.setActiveClub(club)
        XCTAssertEqual(activeStore.activeClubZoneName, club.cloudZoneName)

        try await ClubAdminService.deleteClub(
            club,
            context: context,
            localMemberID: "member-eve",
            activeClubStore: activeStore
        )

        XCTAssertTrue(try context.fetch(FetchDescriptor<BookClub>()).isEmpty, "Deleting removes the local row")
        XCTAssertNil(activeStore.activeClubZoneName, "Deleting the active club clears the active selection")

        activeStore.clearActiveClub() // leave UserDefaults clean
    }

    func test_deleteClub_leavesActiveSelectionWhenDeletingDifferentClub() async throws {
        let context = try makeContext()
        let active = makeOwnedActiveClub(creator: "member-eve")
        let other = makeOwnedActiveClub(creator: "member-eve")
        context.insert(active)
        context.insert(other)
        try context.save()

        let activeStore = ActiveClubStore()
        activeStore.setActiveClub(active)

        try await ClubAdminService.deleteClub(
            other,
            context: context,
            localMemberID: "member-eve",
            activeClubStore: activeStore
        )

        XCTAssertEqual(
            activeStore.activeClubZoneName,
            active.cloudZoneName,
            "Deleting a non-active club must leave the active selection untouched"
        )

        activeStore.clearActiveClub()
    }

    // MARK: - Helpers

    /// A club this device owns (no `ownerUserRecordName`) with `creatorMemberID`
    /// set, so admin/rename rights resolve for the creator.
    private func makeOwnedActiveClub(creator: String, name: String = "Sunday Pages") -> BookClub {
        let club = BookClub(name: name)
        club.creatorMemberID = creator
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
