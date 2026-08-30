import Foundation
import SwiftData
import XCTest
@testable import BookLoom

@MainActor
final class SharedClubSnapshotTests: XCTestCase {
    /// `MemberShareSnapshotStore.merge` prunes acknowledged overrides into the
    /// per-zone UserDefaults-backed stores (Status/SubmissionDetails/Submission
    /// Deletion), keyed by `cloudZoneName`. Clearing every key under those store
    /// prefixes after each test prevents global-state leakage across runs and
    /// across test targets that share the standard defaults domain. Scanning by
    /// prefix (rather than a hardcoded zone list) keeps this correct when new
    /// tests introduce new zones.
    override func tearDown() {
        let prefixes = [
            StatusOverrideStore.prefix,
            SubmissionDetailsOverrideStore.prefix,
            SubmissionDeletionStore.prefix
        ]
        let defaults = UserDefaults.standard
        for key in defaults.dictionaryRepresentation().keys
        where prefixes.contains(where: key.hasPrefix) {
            defaults.removeObject(forKey: key)
        }
        super.tearDown()
    }

    func test_perAuthorSnapshotCapturesOnlyOwnContributions() throws {
        let context = try makeContext()
        let owner = BookClub(name: "Sunday Pages", createdAt: Date(timeIntervalSince1970: 1_000))
        owner.cloudZoneName = "BookClub-Test"
        owner.shareIsActive = true
        owner.shareParticipantCount = 3
        context.insert(owner)

        let alexSubmission = BookSubmission(
            title: "Piranesi",
            author: "Susanna Clarke",
            isbn: "9781635575637",
            bookDescription: "A labyrinthine novel.",
            publishedYear: 2020,
            coverURL: "https://example.com/piranesi.jpg",
            externalProvider: "Open Library",
            externalID: "OL20893680W",
            submittedBy: "Alex",
            submittedByMemberID: "member-alex",
            submittedAt: Date(timeIntervalSince1970: 1_100),
            status: .current
        )
        alexSubmission.selectionID = "selection-piranesi"
        owner.addSubmission(alexSubmission)
        context.insert(alexSubmission)

        let samSubmission = BookSubmission(
            title: "Annihilation",
            author: "Jeff VanderMeer",
            submittedBy: "Sam",
            submittedByMemberID: "member-sam",
            submittedAt: Date(timeIntervalSince1970: 1_200),
            status: .proposed
        )
        samSubmission.selectionID = "selection-annihilation"
        owner.addSubmission(samSubmission)
        context.insert(samSubmission)

        // Sam rates Alex's book and writes a note.
        let samRating = Rating(memberID: "member-sam", memberName: "Sam", stars: 5)
        samRating.submission = alexSubmission
        context.insert(samRating)
        alexSubmission.ratings = [samRating]

        let alexNote = BookNote(memberID: "member-alex", memberName: "Alex", text: "Great pick.")
        alexNote.submission = alexSubmission
        context.insert(alexNote)
        alexSubmission.notes = [alexNote]

        try context.save()

        let alexSlice = MemberShareSnapshotStore.snapshot(
            from: owner,
            context: context,
            authorMemberID: "member-alex",
            authorName: "Alex",
            includeClubMeta: true,
            capturedAt: Date(timeIntervalSince1970: 3_000)
        )

        XCTAssertEqual(alexSlice.submissions.map(\.selectionID), ["selection-piranesi"])
        XCTAssertEqual(alexSlice.ratings.count, 0, "Alex did not rate, so no ratings in his slice")
        XCTAssertEqual(alexSlice.notes.first?.submissionSelectionID, "selection-piranesi")
        XCTAssertNotNil(alexSlice.clubMeta, "Owner publishes canonical club meta")

        let samSlice = MemberShareSnapshotStore.snapshot(
            from: owner,
            context: context,
            authorMemberID: "member-sam",
            authorName: "Sam",
            includeClubMeta: false,
            capturedAt: Date(timeIntervalSince1970: 3_000)
        )
        XCTAssertEqual(samSlice.submissions.map(\.selectionID), ["selection-annihilation"])
        XCTAssertEqual(samSlice.ratings.first?.submissionSelectionID, "selection-piranesi")
        XCTAssertEqual(samSlice.ratings.first?.stars, 5)
        XCTAssertNil(samSlice.clubMeta, "Non-owner participants don't carry canonical club meta")
    }

    func test_mergeOfTwoMemberSnapshotsBuildsUnifiedClub() throws {
        let context = try makeContext()
        let joined = BookClub(name: "Sunday Pages")
        joined.cloudZoneName = "BookClub-Test"
        joined.ownerUserRecordName = "owner-record"
        joined.shareIsActive = true
        context.insert(joined)
        try context.save()

        let alexSubmission = MemberShareSnapshot.SubmissionPayload(
            selectionID: "sel-piranesi",
            title: "Piranesi",
            author: "Susanna Clarke",
            isbn: "9781635575637",
            submittedBy: "Alex",
            submittedByMemberID: "member-alex",
            submittedAt: Date(timeIntervalSince1970: 1_100),
            initialStatusRaw: BookSubmissionStatus.current.rawValue,
            initialPickedAt: Date(timeIntervalSince1970: 1_500),
            initialCompletedAt: nil,
            bookDescription: "Labyrinthine novel.",
            publishedYear: 2020,
            coverURL: "https://example.com/piranesi.jpg",
            externalProvider: "Open Library",
            externalID: "OL1"
        )
        let samSubmission = MemberShareSnapshot.SubmissionPayload(
            selectionID: "sel-annihilation",
            title: "Annihilation",
            author: "Jeff VanderMeer",
            isbn: "",
            submittedBy: "Sam",
            submittedByMemberID: "member-sam",
            submittedAt: Date(timeIntervalSince1970: 1_200),
            initialStatusRaw: BookSubmissionStatus.proposed.rawValue,
            initialPickedAt: nil,
            initialCompletedAt: nil,
            bookDescription: "",
            publishedYear: 2014,
            coverURL: "",
            externalProvider: "",
            externalID: ""
        )

        let ownerSlice = MemberShareSnapshot(
            capturedAt: Date(timeIntervalSince1970: 3_000),
            authorMemberID: "member-alex",
            authorName: "Alex",
            clubMeta: MemberShareSnapshot.ClubMeta(
                name: "Sunday Pages",
                createdAt: Date(timeIntervalSince1970: 1_000),
                cloudZoneName: "BookClub-Test",
                shareParticipantCount: 2,
                creatorMemberID: nil,
                adminMemberIDs: nil,
                removedMemberIDs: nil,
                inviteURLString: nil,
                nameUpdatedAt: nil
            ),
            submissions: [alexSubmission],
            ratings: [],
            notes: [
                MemberShareSnapshot.NotePayload(
                    submissionSelectionID: "sel-piranesi",
                    memberID: "member-alex",
                    memberName: "Alex",
                    text: "Set up for great discussion.",
                    createdAt: Date(timeIntervalSince1970: 1_700)
                )
            ]
        )

        let samSlice = MemberShareSnapshot(
            capturedAt: Date(timeIntervalSince1970: 3_500),
            authorMemberID: "member-sam",
            authorName: "Sam",
            submissions: [samSubmission],
            ratings: [
                MemberShareSnapshot.RatingPayload(
                    submissionSelectionID: "sel-piranesi",
                    memberID: "member-sam",
                    memberName: "Sam",
                    stars: 5,
                    createdAt: Date(timeIntervalSince1970: 1_800)
                )
            ]
        )

        try MemberShareSnapshotStore.merge(
            snapshots: [ownerSlice, samSlice],
            into: joined,
            context: context,
            localMemberID: "member-eve" // a neutral local user
        )

        let allSubmissions = (try context.fetch(FetchDescriptor<BookSubmission>()))
            .filter { $0.bookClub?.persistentModelID == joined.persistentModelID }
            .sorted(by: { $0.submittedAt < $1.submittedAt })

        XCTAssertEqual(allSubmissions.map(\.selectionID).sorted(), ["sel-annihilation", "sel-piranesi"])
        let piranesi = allSubmissions.first { $0.selectionID == "sel-piranesi" }!
        XCTAssertEqual(piranesi.status, .current)
        XCTAssertEqual(piranesi.ratings?.count, 1)
        XCTAssertEqual(piranesi.ratings?.first?.stars, 5)
        XCTAssertEqual(piranesi.notes?.first?.text, "Set up for great discussion.")

        let annihilation = allSubmissions.first { $0.selectionID == "sel-annihilation" }!
        XCTAssertEqual(annihilation.status, .proposed)
    }

    func test_mergeKeepsNewestRatingWhenSnapshotsContainSameMemberRating() throws {
        let context = try makeContext()
        let club = BookClub(name: "Sunday Pages")
        club.cloudZoneName = "BookClub-Test"
        club.shareIsActive = true
        context.insert(club)

        let submission = MemberShareSnapshot.SubmissionPayload(
            selectionID: "sel-piranesi",
            title: "Piranesi",
            author: "Susanna Clarke",
            isbn: "",
            submittedBy: "Alex",
            submittedByMemberID: "member-alex",
            submittedAt: Date(timeIntervalSince1970: 1_000),
            initialStatusRaw: BookSubmissionStatus.proposed.rawValue,
            initialPickedAt: nil,
            initialCompletedAt: nil,
            bookDescription: "",
            publishedYear: nil,
            coverURL: "",
            externalProvider: "",
            externalID: ""
        )
        let olderRating = MemberShareSnapshot.RatingPayload(
            submissionSelectionID: "sel-piranesi",
            memberID: "member-sam",
            memberName: "Sam",
            stars: 2,
            createdAt: Date(timeIntervalSince1970: 2_000)
        )
        let newerRating = MemberShareSnapshot.RatingPayload(
            submissionSelectionID: "sel-piranesi",
            memberID: "member-sam",
            memberName: "Sam",
            stars: 5,
            createdAt: Date(timeIntervalSince1970: 3_000)
        )
        let newerSnapshot = MemberShareSnapshot(
            capturedAt: Date(timeIntervalSince1970: 4_000),
            authorMemberID: "member-sam",
            authorName: "Sam",
            submissions: [submission],
            ratings: [newerRating]
        )
        let olderSnapshot = MemberShareSnapshot(
            capturedAt: Date(timeIntervalSince1970: 5_000),
            authorMemberID: "member-sam",
            authorName: "Sam",
            submissions: [submission],
            ratings: [olderRating]
        )

        try MemberShareSnapshotStore.merge(
            snapshots: [newerSnapshot, olderSnapshot],
            into: club,
            context: context,
            localMemberID: "member-eve"
        )

        let persisted = try context.fetch(FetchDescriptor<Rating>())
        XCTAssertEqual(persisted.count, 1)
        XCTAssertEqual(persisted.first?.stars, 5)
        XCTAssertEqual(persisted.first?.createdAt, newerRating.createdAt)
    }

    func test_statusOverridesFromAnotherMemberWinByOccurredAt() throws {
        let context = try makeContext()
        let joined = BookClub(name: "Sunday Pages")
        joined.cloudZoneName = "BookClub-Test"
        joined.ownerUserRecordName = "owner-record"
        joined.shareIsActive = true
        context.insert(joined)
        try context.save()

        let basePayload = MemberShareSnapshot.SubmissionPayload(
            selectionID: "sel-x",
            title: "Book X",
            author: "X",
            isbn: "",
            submittedBy: "Alex",
            submittedByMemberID: "member-alex",
            submittedAt: Date(timeIntervalSince1970: 1_000),
            initialStatusRaw: BookSubmissionStatus.proposed.rawValue,
            initialPickedAt: nil,
            initialCompletedAt: nil,
            bookDescription: "",
            publishedYear: nil,
            coverURL: "",
            externalProvider: "",
            externalID: ""
        )

        let alex = MemberShareSnapshot(
            capturedAt: Date(timeIntervalSince1970: 2_000),
            authorMemberID: "member-alex",
            authorName: "Alex",
            clubMeta: MemberShareSnapshot.ClubMeta(
                name: "Sunday Pages",
                createdAt: Date(timeIntervalSince1970: 1_000),
                cloudZoneName: "BookClub-Test",
                shareParticipantCount: 2,
                creatorMemberID: nil,
                adminMemberIDs: nil,
                removedMemberIDs: nil,
                inviteURLString: nil,
                nameUpdatedAt: nil
            ),
            submissions: [basePayload]
        )

        // Sam picks the book as current at t=2_500.
        let sam = MemberShareSnapshot(
            capturedAt: Date(timeIntervalSince1970: 2_500),
            authorMemberID: "member-sam",
            authorName: "Sam",
            statusOverrides: [
                MemberShareSnapshot.StatusOverride(
                    submissionSelectionID: "sel-x",
                    statusRaw: BookSubmissionStatus.current.rawValue,
                    pickedAt: Date(timeIntervalSince1970: 2_500),
                    completedAt: nil,
                    occurredAt: Date(timeIntervalSince1970: 2_500)
                )
            ]
        )

        try MemberShareSnapshotStore.merge(
            snapshots: [alex, sam],
            into: joined,
            context: context,
            localMemberID: "member-eve"
        )

        let submission = (try context.fetch(FetchDescriptor<BookSubmission>())).first!
        XCTAssertEqual(submission.status, .current)
        XCTAssertEqual(submission.pickedAt, Date(timeIntervalSince1970: 2_500))
    }

    func test_localAuthoredItemsSurviveMergeWithoutRemoteEcho() throws {
        let context = try makeContext()
        let club = BookClub(name: "Sunday Pages")
        club.cloudZoneName = "BookClub-Test"
        club.shareIsActive = true
        context.insert(club)

        let localPick = BookSubmission(
            title: "Local Draft",
            submittedBy: "Eve",
            submittedByMemberID: "member-eve",
            submittedAt: Date(timeIntervalSince1970: 5_000),
            status: .proposed
        )
        localPick.selectionID = "sel-local"
        club.addSubmission(localPick)
        context.insert(localPick)
        try context.save()

        // Merge in a snapshot that doesn't include the local item — Eve hasn't
        // pushed yet. The local item must stick around.
        let owner = MemberShareSnapshot(
            capturedAt: Date(timeIntervalSince1970: 6_000),
            authorMemberID: "member-alex",
            authorName: "Alex",
            clubMeta: MemberShareSnapshot.ClubMeta(
                name: "Sunday Pages",
                createdAt: Date(timeIntervalSince1970: 1_000),
                cloudZoneName: "BookClub-Test",
                shareParticipantCount: 2,
                creatorMemberID: nil,
                adminMemberIDs: nil,
                removedMemberIDs: nil,
                inviteURLString: nil,
                nameUpdatedAt: nil
            ),
            submissions: []
        )

        try MemberShareSnapshotStore.merge(
            snapshots: [owner],
            into: club,
            context: context,
            localMemberID: "member-eve"
        )

        let surviving = (try context.fetch(FetchDescriptor<BookSubmission>()))
            .filter { $0.bookClub?.persistentModelID == club.persistentModelID }
        XCTAssertEqual(surviving.map(\.selectionID), ["sel-local"])
    }

    func test_removedMembersHaveTheirSnapshotIgnoredAndRowsCleaned() throws {
        let context = try makeContext()
        let club = BookClub(name: "Sunday Pages")
        club.cloudZoneName = "BookClub-Test"
        club.ownerUserRecordName = "owner-record"
        club.shareIsActive = true
        club.knownMemberRoster = [
            "member-alex": "Alex",
            "member-kim": "Kim",
            "member-kim-tablet": "Kim"
        ]
        club.memberIdentityBindings = [
            "member-alex": "cloud-alex",
            "member-kim": "cloud-kim",
            "member-kim-tablet": "cloud-kim"
        ]
        context.insert(club)
        try context.save()

        let kickedSubmission = MemberShareSnapshot.SubmissionPayload(
            selectionID: "sel-kicked",
            title: "Vanishing",
            author: "Kim",
            isbn: "",
            submittedBy: "Kim",
            submittedByMemberID: "member-kim",
            submittedAt: Date(timeIntervalSince1970: 1_000),
            initialStatusRaw: BookSubmissionStatus.proposed.rawValue,
            initialPickedAt: nil,
            initialCompletedAt: nil,
            bookDescription: "",
            publishedYear: nil,
            coverURL: "",
            externalProvider: "",
            externalID: ""
        )

        let owner = MemberShareSnapshot(
            capturedAt: Date(timeIntervalSince1970: 5_000),
            authorMemberID: "member-alex",
            authorName: "Alex",
            clubMeta: MemberShareSnapshot.ClubMeta(
                name: "Sunday Pages",
                createdAt: Date(timeIntervalSince1970: 1_000),
                cloudZoneName: "BookClub-Test",
                shareParticipantCount: 2,
                creatorMemberID: "member-alex",
                adminMemberIDs: [],
                removedMemberIDs: ["member-kim"],
                inviteURLString: nil,
                nameUpdatedAt: nil
            ),
            submissions: []
        )

        // The kicked member's snapshot is still in CloudKit (their record may
        // not have been deleted yet, or they re-published from another device).
        let kicked = MemberShareSnapshot(
            capturedAt: Date(timeIntervalSince1970: 5_500),
            authorMemberID: "member-kim",
            authorName: "Kim",
            submissions: [kickedSubmission]
        )
        let kickedTablet = MemberShareSnapshot(
            capturedAt: Date(timeIntervalSince1970: 5_600),
            authorMemberID: "member-kim-tablet",
            authorName: "Kim",
            submissions: [kickedSubmission]
        )

        try MemberShareSnapshotStore.merge(
            snapshots: [owner, kicked, kickedTablet],
            into: club,
            context: context,
            localMemberID: "member-eve"
        )

        let surviving = (try context.fetch(FetchDescriptor<BookSubmission>()))
            .filter { $0.bookClub?.persistentModelID == club.persistentModelID }
        XCTAssertTrue(surviving.isEmpty, "Removed member's submissions must not appear after merge")
        XCTAssertEqual(club.removedMemberIDs, ["member-kim"], "Owner-published removal list propagates locally")
        XCTAssertNil(club.knownMemberRoster["member-kim"], "Removed members must disappear from the roster and member count")
        XCTAssertNil(club.knownMemberRoster["member-kim-tablet"], "A removed person's other device IDs must also disappear")
    }

    func test_ownerAuthorizedReinviteClearsTombstoneWithoutRestoringAdmin() throws {
        let context = try makeContext()
        let club = BookClub(name: "Sunday Pages")
        club.cloudZoneName = "BookClub-Test"
        club.shareIsActive = true
        club.creatorMemberID = "member-alex"
        club.adminMemberIDs = ["member-kim"]
        club.memberIdentityBindings = [
            "member-alex": "cloud-alex",
            "member-kim": "cloud-kim"
        ]
        context.insert(club)
        try context.save()

        let owner = MemberShareSnapshot(
            capturedAt: Date(timeIntervalSince1970: 5_000),
            authorMemberID: "member-alex",
            authorName: "Alex",
            clubMeta: .init(
                name: "Sunday Pages",
                createdAt: Date(timeIntervalSince1970: 1_000),
                cloudZoneName: "BookClub-Test",
                shareParticipantCount: 2,
                creatorMemberID: "member-alex",
                adminMemberIDs: [],
                removedMemberIDs: ["member-kim"],
                memberIdentityBindings: [
                    .init(memberID: "member-alex", cloudKitUserRecordName: "cloud-alex"),
                    .init(memberID: "member-kim", cloudKitUserRecordName: "cloud-kim")
                ],
                inviteURLString: nil,
                nameUpdatedAt: nil
            )
        )
        let returning = MemberShareSnapshot(
            capturedAt: Date(timeIntervalSince1970: 6_000),
            authorMemberID: "member-kim",
            authorName: "Kim",
            submissions: [
                .init(
                    selectionID: "sel-returning",
                    title: "The Return",
                    author: "Kim",
                    isbn: "",
                    submittedBy: "Kim",
                    submittedByMemberID: "member-kim",
                    submittedAt: Date(timeIntervalSince1970: 5_500),
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
            snapshots: [owner, returning],
            into: club,
            context: context,
            localMemberID: "member-alex",
            reactivatedMemberIDs: ["member-kim"]
        )

        XCTAssertTrue(club.removedMemberIDs.isEmpty)
        XCTAssertFalse(club.isAdmin(memberID: "member-kim"), "Rejoining never restores the prior admin role")
        XCTAssertEqual(club.knownMemberRoster["member-kim"], "Kim")
        let submissions = try context.fetch(FetchDescriptor<BookSubmission>())
        XCTAssertEqual(submissions.map(\.selectionID), ["sel-returning"])
    }

    func test_participantMergeCannotClearOwnerRemovalTombstone() throws {
        let context = try makeContext()
        let club = BookClub(name: "Sunday Pages")
        club.ownerUserRecordName = "cloud-owner"
        club.shareIsActive = true
        club.removedMemberIDs = ["member-kim"]
        context.insert(club)
        try context.save()

        try MemberShareSnapshotStore.merge(
            snapshots: [],
            into: club,
            context: context,
            localMemberID: "member-sam",
            reactivatedMemberIDs: ["member-kim"]
        )

        XCTAssertEqual(club.removedMemberIDs, ["member-kim"])
    }

    func test_adminNameProposalAdoptedWhenNewerThanOwnerMeta() throws {
        let context = try makeContext()
        let club = BookClub(name: "Sunday Pages")
        club.cloudZoneName = "BookClub-Test"
        club.ownerUserRecordName = "owner-record"
        club.shareIsActive = true
        context.insert(club)
        try context.save()

        // Owner's published meta carries the original name with no recorded
        // rename timestamp.
        let owner = MemberShareSnapshot(
            capturedAt: Date(timeIntervalSince1970: 5_000),
            authorMemberID: "member-alex",
            authorName: "Alex",
            clubMeta: MemberShareSnapshot.ClubMeta(
                name: "Sunday Pages",
                createdAt: Date(timeIntervalSince1970: 1_000),
                cloudZoneName: "BookClub-Test",
                shareParticipantCount: 2,
                creatorMemberID: "member-alex",
                adminMemberIDs: ["member-lena"],
                removedMemberIDs: [],
                inviteURLString: nil,
                nameUpdatedAt: nil
            )
        )

        // Admin Lena pushes a rename through her own snapshot's nameProposal.
        let adminRename = MemberShareSnapshot(
            capturedAt: Date(timeIntervalSince1970: 6_000),
            authorMemberID: "member-lena",
            authorName: "Lena",
            nameProposal: MemberShareSnapshot.NameProposal(
                name: "Sunday Mornings",
                updatedAt: Date(timeIntervalSince1970: 5_500),
                proposerMemberID: "member-lena"
            )
        )

        try MemberShareSnapshotStore.merge(
            snapshots: [owner, adminRename],
            into: club,
            context: context,
            localMemberID: "member-eve"
        )

        XCTAssertEqual(club.name, "Sunday Mornings", "Admin's later rename proposal should override owner's stale name")
        XCTAssertEqual(club.nameUpdatedAt, Date(timeIntervalSince1970: 5_500))
    }

    func test_nonAdminNameProposalIsIgnored() throws {
        let context = try makeContext()
        let club = BookClub(name: "Sunday Pages")
        club.cloudZoneName = "BookClub-Test"
        club.ownerUserRecordName = "owner-record"
        club.shareIsActive = true
        context.insert(club)
        try context.save()

        let owner = MemberShareSnapshot(
            capturedAt: Date(timeIntervalSince1970: 5_000),
            authorMemberID: "member-alex",
            authorName: "Alex",
            clubMeta: MemberShareSnapshot.ClubMeta(
                name: "Sunday Pages",
                createdAt: Date(timeIntervalSince1970: 1_000),
                cloudZoneName: "BookClub-Test",
                shareParticipantCount: 2,
                creatorMemberID: "member-alex",
                adminMemberIDs: [],
                removedMemberIDs: [],
                inviteURLString: nil,
                nameUpdatedAt: nil
            )
        )

        // Sam is a regular member, not in adminMemberIDs.
        let sneaky = MemberShareSnapshot(
            capturedAt: Date(timeIntervalSince1970: 6_000),
            authorMemberID: "member-sam",
            authorName: "Sam",
            nameProposal: MemberShareSnapshot.NameProposal(
                name: "Sam's Pages",
                updatedAt: Date(timeIntervalSince1970: 5_999),
                proposerMemberID: "member-sam"
            )
        )

        try MemberShareSnapshotStore.merge(
            snapshots: [owner, sneaky],
            into: club,
            context: context,
            localMemberID: "member-eve"
        )

        XCTAssertEqual(club.name, "Sunday Pages", "Non-admin members should not be able to rename via nameProposal")
    }

    func test_legacyInviteURLIsNotPropagatedThroughClubMeta() throws {
        let context = try makeContext()
        let club = BookClub(name: "Sunday Pages")
        club.cloudZoneName = "BookClub-Test"
        club.ownerUserRecordName = "owner-record"
        club.shareIsActive = true
        context.insert(club)
        try context.save()

        let inviteURL = "https://www.icloud.com/share/0Aabcdef"
        let owner = MemberShareSnapshot(
            capturedAt: Date(timeIntervalSince1970: 5_000),
            authorMemberID: "member-alex",
            authorName: "Alex",
            clubMeta: MemberShareSnapshot.ClubMeta(
                name: "Sunday Pages",
                createdAt: Date(timeIntervalSince1970: 1_000),
                cloudZoneName: "BookClub-Test",
                shareParticipantCount: 2,
                creatorMemberID: "member-alex",
                adminMemberIDs: ["member-lena"],
                removedMemberIDs: [],
                inviteURLString: inviteURL,
                nameUpdatedAt: nil
            )
        )

        try MemberShareSnapshotStore.merge(
            snapshots: [owner],
            into: club,
            context: context,
            localMemberID: "member-lena"
        )

        XCTAssertTrue(club.inviteURLString.isEmpty, "Reusable legacy invite URLs must not propagate to member devices")
    }

    func test_coverDataCleanupRemovesPersistedImageBytes() throws {
        let context = try makeContext()
        let club = BookClub(name: "Local Cache Only")
        let submission = BookSubmission(title: "Cached Cover", coverURL: "https://example.com/cover.jpg")
        submission.coverData = Data([9, 8, 7])

        context.insert(club)
        context.insert(submission)
        club.addSubmission(submission)
        try context.save()

        XCTAssertTrue(CoverDataCleanup.clearPersistedCoverData(in: club))
        try context.save()

        XCTAssertNil(submission.coverData)
    }

    func test_perAuthorSnapshotIncludesPersistedClubChildrenViaContext() throws {
        let context = try makeContext()
        let club = BookClub(name: "Sunday Pages")
        let submission = BookSubmission(
            title: "Accelerando",
            author: "Charles Stross",
            submittedBy: "Alex",
            submittedByMemberID: "member-alex"
        )
        let meeting = ClubMeeting(title: "Accelerando Discussion", hostMemberID: "member-alex")
        let poll = SelectionPoll(title: "Next Pick", candidates: [submission])
        poll.createdByMemberID = "member-alex"

        context.insert(club)
        context.insert(submission)
        context.insert(meeting)
        context.insert(poll)
        submission.bookClub = club
        meeting.bookClub = club
        poll.bookClub = club
        try context.save()

        let slice = MemberShareSnapshotStore.snapshot(
            from: club,
            context: context,
            authorMemberID: "member-alex",
            authorName: "Alex",
            includeClubMeta: true
        )

        XCTAssertEqual(slice.submissions.map(\.title), ["Accelerando"])
        XCTAssertEqual(slice.meetings.map(\.title), ["Accelerando Discussion"])
        XCTAssertEqual(slice.polls.map(\.title), ["Next Pick"])
    }

    func test_mergeAppliesLatestSubmissionDetailsOverride() throws {
        let context = try makeContext()
        let club = BookClub(name: "Sunday Pages")
        club.cloudZoneName = "BookClub-DetailsOverride"
        club.ownerUserRecordName = "owner-record"
        club.shareIsActive = true
        context.insert(club)
        try context.save()

        let ownerSubmission = MemberShareSnapshot.SubmissionPayload(
            selectionID: "selection-piranesi",
            title: "Piranesi",
            author: "Susanna Clarke",
            isbn: "9781635575637",
            submittedBy: "Alex",
            submittedByMemberID: "member-alex",
            submittedAt: Date(timeIntervalSince1970: 1_100),
            initialStatusRaw: BookSubmissionStatus.proposed.rawValue,
            initialPickedAt: nil,
            initialCompletedAt: nil,
            bookDescription: "Original description.",
            publishedYear: 2020,
            coverURL: "https://example.com/old.jpg",
            externalProvider: "Open Library",
            externalID: "OL1"
        )
        let owner = MemberShareSnapshot(
            capturedAt: Date(timeIntervalSince1970: 2_000),
            authorMemberID: "member-alex",
            authorName: "Alex",
            submissions: [ownerSubmission]
        )
        let lena = MemberShareSnapshot(
            capturedAt: Date(timeIntervalSince1970: 2_100),
            authorMemberID: "member-lena",
            authorName: "Lena",
            detailsOverrides: [
                MemberShareSnapshot.SubmissionDetailsOverride(
                    submissionSelectionID: "selection-piranesi",
                    title: "Piranesi: Deluxe Edition",
                    author: "Susanna Clarke",
                    isbn: "9781635575637",
                    bookDescription: "Updated description.",
                    publishedYear: 2021,
                    coverURL: "https://example.com/new.jpg",
                    externalProvider: "Google Books",
                    externalID: "gb-1",
                    updatedAt: Date(timeIntervalSince1970: 2_050),
                    actorMemberID: "member-lena"
                )
            ]
        )

        try MemberShareSnapshotStore.merge(
            snapshots: [owner, lena],
            into: club,
            context: context,
            localMemberID: "member-lena"
        )

        let submissions = try context.fetch(FetchDescriptor<BookSubmission>())
        XCTAssertEqual(submissions.first?.title, "Piranesi: Deluxe Edition")
        XCTAssertEqual(submissions.first?.bookDescription, "Updated description.")
        XCTAssertEqual(submissions.first?.publishedYear, 2021)
        XCTAssertEqual(submissions.first?.coverURL, "https://example.com/new.jpg")
        XCTAssertEqual(submissions.first?.externalProvider, "Google Books")
    }

    func test_mergeDeletesSubmissionWithDeletionMarkerFromAnyMember() throws {
        let context = try makeContext()
        let club = BookClub(name: "Sunday Pages")
        club.cloudZoneName = "BookClub-DeletionMarker"
        club.ownerUserRecordName = "owner-record"
        club.shareIsActive = true
        context.insert(club)
        try context.save()

        let ownerSubmission = MemberShareSnapshot.SubmissionPayload(
            selectionID: "selection-annihilation",
            title: "Annihilation",
            author: "Jeff VanderMeer",
            isbn: "",
            submittedBy: "Alex",
            submittedByMemberID: "member-alex",
            submittedAt: Date(timeIntervalSince1970: 1_100),
            initialStatusRaw: BookSubmissionStatus.proposed.rawValue,
            initialPickedAt: nil,
            initialCompletedAt: nil,
            bookDescription: "",
            publishedYear: 2014,
            coverURL: "",
            externalProvider: "",
            externalID: ""
        )
        let owner = MemberShareSnapshot(
            capturedAt: Date(timeIntervalSince1970: 2_000),
            authorMemberID: "member-alex",
            authorName: "Alex",
            submissions: [ownerSubmission]
        )
        let lena = MemberShareSnapshot(
            capturedAt: Date(timeIntervalSince1970: 2_100),
            authorMemberID: "member-lena",
            authorName: "Lena",
            deletedSubmissions: [
                MemberShareSnapshot.SubmissionDeletion(
                    submissionSelectionID: "selection-annihilation",
                    deletedAt: Date(timeIntervalSince1970: 2_050),
                    actorMemberID: "member-lena"
                )
            ]
        )

        try MemberShareSnapshotStore.merge(
            snapshots: [owner, lena],
            into: club,
            context: context,
            localMemberID: "member-lena"
        )

        let submissions = try context.fetch(FetchDescriptor<BookSubmission>())
        XCTAssertTrue(submissions.isEmpty)
    }

    // MARK: - Merge engine steps 6-11 (prompts, polls, votes, meetings, RSVPs)

    /// Builds a joined club whose canonical state is owned by `member-alex`,
    /// with the local device acting as a neutral `member-eve`.
    private func makeJoinedClub(
        zone: String,
        in context: ModelContext
    ) throws -> BookClub {
        let club = BookClub(name: "Sunday Pages")
        club.cloudZoneName = zone
        club.ownerUserRecordName = "owner-record"
        club.shareIsActive = true
        context.insert(club)
        try context.save()
        return club
    }

    private func ownerSubmissionPayload(
        selectionID: String,
        title: String = "Owned Book"
    ) -> MemberShareSnapshot.SubmissionPayload {
        MemberShareSnapshot.SubmissionPayload(
            selectionID: selectionID,
            title: title,
            author: "Author",
            isbn: "",
            submittedBy: "Alex",
            submittedByMemberID: "member-alex",
            submittedAt: Date(timeIntervalSince1970: 1_000),
            initialStatusRaw: BookSubmissionStatus.proposed.rawValue,
            initialPickedAt: nil,
            initialCompletedAt: nil,
            bookDescription: "",
            publishedYear: nil,
            coverURL: "",
            externalProvider: "",
            externalID: ""
        )
    }

    /// A minimal owner-hosted meeting payload with empty optional fields. Used
    /// by tests that only care about the meeting's child RSVPs.
    private func emptyMeetingPayload(
        meetingID: String = "meeting-1",
        title: String = "Meeting"
    ) -> MemberShareSnapshot.MeetingPayload {
        MemberShareSnapshot.MeetingPayload(
            meetingID: meetingID,
            title: title,
            scheduledAt: Date(timeIntervalSince1970: 8_000),
            hostName: "Alex",
            hostMemberID: "member-alex",
            location: "",
            meetingURL: "",
            reminderOffsetsRaw: "",
            agenda: "",
            createdAt: Date(timeIntervalSince1970: 4_000),
            completedAt: nil,
            submissionSelectionID: nil
        )
    }

    func test_mergeUpsertsMeetingWithRSVPsFromRemoteMember() throws {
        let context = try makeContext()
        let club = try makeJoinedClub(zone: "BookClub-Meetings", in: context)

        let owner = MemberShareSnapshot(
            capturedAt: Date(timeIntervalSince1970: 5_000),
            authorMemberID: "member-alex",
            authorName: "Alex",
            submissions: [ownerSubmissionPayload(selectionID: "sel-book")],
            meetings: [
                MemberShareSnapshot.MeetingPayload(
                    meetingID: "meeting-1",
                    title: "Chapter Club",
                    scheduledAt: Date(timeIntervalSince1970: 8_000),
                    hostName: "Alex",
                    hostMemberID: "member-alex",
                    location: "Library",
                    meetingURL: "https://example.com/call",
                    reminderOffsetsRaw: "1440,60",
                    agenda: "Discuss the ending.",
                    createdAt: Date(timeIntervalSince1970: 4_000),
                    completedAt: nil,
                    submissionSelectionID: "sel-book"
                )
            ]
        )
        // A different remote member RSVPs to the owner's meeting.
        let sam = MemberShareSnapshot(
            capturedAt: Date(timeIntervalSince1970: 5_100),
            authorMemberID: "member-sam",
            authorName: "Sam",
            rsvps: [
                MemberShareSnapshot.RSVPPayload(
                    meetingID: "meeting-1",
                    memberID: "member-sam",
                    memberName: "Sam",
                    statusRaw: MeetingRSVPStatus.maybe.rawValue,
                    bringingNote: "Dessert",
                    updatedAt: Date(timeIntervalSince1970: 5_050)
                )
            ]
        )

        try MemberShareSnapshotStore.merge(
            snapshots: [owner, sam],
            into: club,
            context: context,
            localMemberID: "member-eve"
        )

        let meetings = (try context.fetch(FetchDescriptor<ClubMeeting>()))
            .filter { $0.bookClub?.persistentModelID == club.persistentModelID }
        XCTAssertEqual(meetings.map(\.meetingID), ["meeting-1"])
        let meeting = try XCTUnwrap(meetings.first)
        XCTAssertEqual(meeting.title, "Chapter Club")
        XCTAssertEqual(meeting.agenda, "Discuss the ending.")
        XCTAssertEqual(meeting.bookSubmission?.selectionID, "sel-book", "Meeting must relink to its book by selectionID")

        let rsvps = meeting.rsvps ?? []
        XCTAssertEqual(rsvps.map(\.memberID), ["member-sam"])
        XCTAssertEqual(rsvps.first?.status, .maybe)
        XCTAssertEqual(rsvps.first?.bringingNote, "Dessert")
    }

    func test_mergeUpdatesExistingRemoteRSVPByLatestUpdatedAt() throws {
        let context = try makeContext()
        let club = try makeJoinedClub(zone: "BookClub-RSVPUpdate", in: context)

        let owner = MemberShareSnapshot(
            capturedAt: Date(timeIntervalSince1970: 5_000),
            authorMemberID: "member-alex",
            authorName: "Alex",
            meetings: [emptyMeetingPayload()]
        )
        // Two snapshots carrying the same (meeting, member) RSVP — the later
        // updatedAt must win, exercising the votesByKey/rsvpsByKey freshness gate.
        let stale = MemberShareSnapshot(
            capturedAt: Date(timeIntervalSince1970: 5_100),
            authorMemberID: "member-sam",
            authorName: "Sam",
            rsvps: [
                MemberShareSnapshot.RSVPPayload(
                    meetingID: "meeting-1",
                    memberID: "member-sam",
                    memberName: "Sam",
                    statusRaw: MeetingRSVPStatus.declined.rawValue,
                    bringingNote: "old",
                    updatedAt: Date(timeIntervalSince1970: 5_000)
                )
            ]
        )
        let fresh = MemberShareSnapshot(
            capturedAt: Date(timeIntervalSince1970: 5_200),
            authorMemberID: "member-sam",
            authorName: "Sam",
            rsvps: [
                MemberShareSnapshot.RSVPPayload(
                    meetingID: "meeting-1",
                    memberID: "member-sam",
                    memberName: "Sam",
                    statusRaw: MeetingRSVPStatus.attending.rawValue,
                    bringingNote: "new",
                    updatedAt: Date(timeIntervalSince1970: 6_000)
                )
            ]
        )

        try MemberShareSnapshotStore.merge(
            snapshots: [owner, stale, fresh],
            into: club,
            context: context,
            localMemberID: "member-eve"
        )

        let meeting = try XCTUnwrap(
            (try context.fetch(FetchDescriptor<ClubMeeting>())).first
        )
        let rsvps = meeting.rsvps ?? []
        XCTAssertEqual(rsvps.count, 1, "Only one canonical RSVP per (meeting, member)")
        XCTAssertEqual(rsvps.first?.status, .attending)
        XCTAssertEqual(rsvps.first?.bringingNote, "new")
    }

    func test_mergeDeletesRemoteMeetingNoLongerInCanonical() throws {
        let context = try makeContext()
        let club = try makeJoinedClub(zone: "BookClub-MeetingDelete", in: context)

        // Seed an existing meeting hosted by a remote member.
        let meeting = ClubMeeting(title: "Stale", hostMemberID: "member-sam")
        meeting.meetingID = "meeting-stale"
        context.insert(meeting)
        club.addMeeting(meeting)
        try context.save()

        // Owner's snapshot no longer carries that meeting; no other snapshot
        // reintroduces it. Eve is local and is not the host, so it must go.
        let owner = MemberShareSnapshot(
            capturedAt: Date(timeIntervalSince1970: 5_000),
            authorMemberID: "member-alex",
            authorName: "Alex",
            meetings: []
        )

        try MemberShareSnapshotStore.merge(
            snapshots: [owner],
            into: club,
            context: context,
            localMemberID: "member-eve"
        )

        let meetings = (try context.fetch(FetchDescriptor<ClubMeeting>()))
            .filter { $0.bookClub?.persistentModelID == club.persistentModelID }
        XCTAssertTrue(meetings.isEmpty, "A remote meeting absent from canonical must be deleted")
    }

    func test_mergeKeepsLocallyHostedMeetingAbsentFromCanonical() throws {
        let context = try makeContext()
        let club = try makeJoinedClub(zone: "BookClub-LocalMeeting", in: context)

        // Eve (local) hosts an unpublished meeting.
        let meeting = ClubMeeting(title: "Eve's draft", hostMemberID: "member-eve")
        meeting.meetingID = "meeting-eve"
        context.insert(meeting)
        club.addMeeting(meeting)
        try context.save()

        let owner = MemberShareSnapshot(
            capturedAt: Date(timeIntervalSince1970: 5_000),
            authorMemberID: "member-alex",
            authorName: "Alex",
            meetings: []
        )

        try MemberShareSnapshotStore.merge(
            snapshots: [owner],
            into: club,
            context: context,
            localMemberID: "member-eve"
        )

        let meetings = (try context.fetch(FetchDescriptor<ClubMeeting>()))
            .filter { $0.bookClub?.persistentModelID == club.persistentModelID }
        XCTAssertEqual(meetings.map(\.meetingID), ["meeting-eve"], "Locally-hosted meetings survive even when absent from canonical")
    }

    func test_mergeUpsertsPromptFromNonLocalMember() throws {
        let context = try makeContext()
        let club = try makeJoinedClub(zone: "BookClub-Prompts", in: context)

        let owner = MemberShareSnapshot(
            capturedAt: Date(timeIntervalSince1970: 5_000),
            authorMemberID: "member-alex",
            authorName: "Alex",
            submissions: [ownerSubmissionPayload(selectionID: "sel-book")],
            prompts: [
                MemberShareSnapshot.PromptPayload(
                    promptID: "prompt-1",
                    submissionSelectionID: "sel-book",
                    createdByMemberID: "member-alex",
                    question: "What surprised you most?",
                    orderIndex: 2,
                    sourceRaw: DiscussionPromptSource.custom.rawValue,
                    createdAt: Date(timeIntervalSince1970: 4_500),
                    isArchived: false
                )
            ]
        )

        try MemberShareSnapshotStore.merge(
            snapshots: [owner],
            into: club,
            context: context,
            localMemberID: "member-eve"
        )

        let prompts = try context.fetch(FetchDescriptor<DiscussionPrompt>())
        XCTAssertEqual(prompts.map(\.promptID), ["prompt-1"])
        let prompt = try XCTUnwrap(prompts.first)
        XCTAssertEqual(prompt.question, "What surprised you most?")
        XCTAssertEqual(prompt.orderIndex, 2)
        XCTAssertEqual(prompt.createdByMemberID, "member-alex")
        XCTAssertEqual(prompt.submission?.selectionID, "sel-book", "Prompt must be parented to its submission")
    }

    func test_mergeDeletesRemotePromptNoLongerInCanonical() throws {
        let context = try makeContext()
        let club = try makeJoinedClub(zone: "BookClub-PromptDelete", in: context)

        // Seed a submission + a remote-authored prompt.
        let submission = BookSubmission(
            title: "Owned Book",
            submittedBy: "Alex",
            submittedByMemberID: "member-alex"
        )
        submission.selectionID = "sel-book"
        context.insert(submission)
        club.addSubmission(submission)
        let prompt = DiscussionPrompt(question: "Stale?")
        prompt.promptID = "prompt-stale"
        prompt.createdByMemberID = "member-sam"
        prompt.submission = submission
        context.insert(prompt)
        submission.discussionPrompts = [prompt]
        try context.save()

        // Owner still carries the submission, but the prompt is gone from
        // canonical and Eve (local) didn't author it.
        let owner = MemberShareSnapshot(
            capturedAt: Date(timeIntervalSince1970: 5_000),
            authorMemberID: "member-alex",
            authorName: "Alex",
            submissions: [ownerSubmissionPayload(selectionID: "sel-book")],
            prompts: []
        )

        try MemberShareSnapshotStore.merge(
            snapshots: [owner],
            into: club,
            context: context,
            localMemberID: "member-eve"
        )

        let prompts = try context.fetch(FetchDescriptor<DiscussionPrompt>())
        XCTAssertTrue(prompts.isEmpty, "A remote prompt absent from canonical must be deleted")
    }

    func test_mergeKeepsStarterPromptWithEmptyAuthorOnMerge() throws {
        let context = try makeContext()
        let club = try makeJoinedClub(zone: "BookClub-Starter", in: context)

        let submission = BookSubmission(
            title: "Owned Book",
            submittedBy: "Alex",
            submittedByMemberID: "member-alex"
        )
        submission.selectionID = "sel-book"
        context.insert(submission)
        club.addSubmission(submission)
        // Auto-generated starter prompt: empty createdByMemberID, not synced.
        let starter = DiscussionPrompt(question: "Starter", source: .starter)
        starter.promptID = "prompt-starter"
        starter.createdByMemberID = ""
        starter.submission = submission
        context.insert(starter)
        submission.discussionPrompts = [starter]
        try context.save()

        let owner = MemberShareSnapshot(
            capturedAt: Date(timeIntervalSince1970: 5_000),
            authorMemberID: "member-alex",
            authorName: "Alex",
            submissions: [ownerSubmissionPayload(selectionID: "sel-book")],
            prompts: []
        )

        try MemberShareSnapshotStore.merge(
            snapshots: [owner],
            into: club,
            context: context,
            localMemberID: "member-eve"
        )

        let prompts = try context.fetch(FetchDescriptor<DiscussionPrompt>())
        XCTAssertEqual(prompts.map(\.promptID), ["prompt-starter"], "Starter prompts (empty author) survive merge")
    }

    func test_mergeUpsertsPollAndVoteFromRemoteMember() throws {
        let context = try makeContext()
        let club = try makeJoinedClub(zone: "BookClub-Polls", in: context)

        let owner = MemberShareSnapshot(
            capturedAt: Date(timeIntervalSince1970: 5_000),
            authorMemberID: "member-alex",
            authorName: "Alex",
            polls: [
                MemberShareSnapshot.PollPayload(
                    pollID: "poll-1",
                    createdByMemberID: "member-alex",
                    title: "June Pick",
                    createdAt: Date(timeIntervalSince1970: 4_000),
                    closesAt: Date(timeIntervalSince1970: 9_000),
                    statusRaw: SelectionPollStatus.open.rawValue,
                    isAnonymousResults: true,
                    candidateIDsRaw: "sel-a,sel-b",
                    winnerSubmissionID: ""
                )
            ]
        )
        // A remote member's ballot on the owner's poll.
        let sam = MemberShareSnapshot(
            capturedAt: Date(timeIntervalSince1970: 5_100),
            authorMemberID: "member-sam",
            authorName: "Sam",
            votes: [
                MemberShareSnapshot.VotePayload(
                    pollID: "poll-1",
                    memberID: "member-sam",
                    memberName: "Sam",
                    rankedSubmissionIDsRaw: "sel-b,sel-a",
                    updatedAt: Date(timeIntervalSince1970: 5_050)
                )
            ]
        )

        try MemberShareSnapshotStore.merge(
            snapshots: [owner, sam],
            into: club,
            context: context,
            localMemberID: "member-eve"
        )

        let polls = (try context.fetch(FetchDescriptor<SelectionPoll>()))
            .filter { $0.bookClub?.persistentModelID == club.persistentModelID }
        XCTAssertEqual(polls.map(\.pollID), ["poll-1"])
        let poll = try XCTUnwrap(polls.first)
        XCTAssertEqual(poll.title, "June Pick")
        XCTAssertEqual(poll.candidateIDs, ["sel-a", "sel-b"])

        let votes = poll.votes ?? []
        XCTAssertEqual(votes.map(\.memberID), ["member-sam"])
        XCTAssertEqual(votes.first?.rankedSubmissionIDs, ["sel-b", "sel-a"], "Vote must be keyed to the correct poll and decode its ranks")
    }

    func test_mergeDoesNotMisKeyVotesAcrossPolls() throws {
        let context = try makeContext()
        let club = try makeJoinedClub(zone: "BookClub-MultiPoll", in: context)

        let owner = MemberShareSnapshot(
            capturedAt: Date(timeIntervalSince1970: 5_000),
            authorMemberID: "member-alex",
            authorName: "Alex",
            polls: [
                MemberShareSnapshot.PollPayload(
                    pollID: "poll-1",
                    createdByMemberID: "member-alex",
                    title: "Poll One",
                    createdAt: Date(timeIntervalSince1970: 4_000),
                    closesAt: nil,
                    statusRaw: SelectionPollStatus.open.rawValue,
                    isAnonymousResults: true,
                    candidateIDsRaw: "sel-a",
                    winnerSubmissionID: ""
                ),
                MemberShareSnapshot.PollPayload(
                    pollID: "poll-2",
                    createdByMemberID: "member-alex",
                    title: "Poll Two",
                    createdAt: Date(timeIntervalSince1970: 4_100),
                    closesAt: nil,
                    statusRaw: SelectionPollStatus.open.rawValue,
                    isAnonymousResults: true,
                    candidateIDsRaw: "sel-b",
                    winnerSubmissionID: ""
                )
            ],
            votes: [
                MemberShareSnapshot.VotePayload(
                    pollID: "poll-1",
                    memberID: "member-alex",
                    memberName: "Alex",
                    rankedSubmissionIDsRaw: "sel-a",
                    updatedAt: Date(timeIntervalSince1970: 4_500)
                ),
                MemberShareSnapshot.VotePayload(
                    pollID: "poll-2",
                    memberID: "member-alex",
                    memberName: "Alex",
                    rankedSubmissionIDsRaw: "sel-b",
                    updatedAt: Date(timeIntervalSince1970: 4_600)
                )
            ]
        )

        try MemberShareSnapshotStore.merge(
            snapshots: [owner],
            into: club,
            context: context,
            localMemberID: "member-eve"
        )

        let polls = (try context.fetch(FetchDescriptor<SelectionPoll>()))
            .filter { $0.bookClub?.persistentModelID == club.persistentModelID }
        let pollOne = try XCTUnwrap(polls.first { $0.pollID == "poll-1" })
        let pollTwo = try XCTUnwrap(polls.first { $0.pollID == "poll-2" })
        XCTAssertEqual(pollOne.votes?.map(\.rankedSubmissionIDs), [["sel-a"]], "poll-1 keeps only its own vote")
        XCTAssertEqual(pollTwo.votes?.map(\.rankedSubmissionIDs), [["sel-b"]], "poll-2 keeps only its own vote")
    }

    func test_mergeDeletesRemotePollNoLongerInCanonical() throws {
        let context = try makeContext()
        let club = try makeJoinedClub(zone: "BookClub-PollDelete", in: context)

        let poll = SelectionPoll(title: "Stale Poll")
        poll.pollID = "poll-stale"
        poll.createdByMemberID = "member-sam"
        context.insert(poll)
        club.addSelectionPoll(poll)
        try context.save()

        let owner = MemberShareSnapshot(
            capturedAt: Date(timeIntervalSince1970: 5_000),
            authorMemberID: "member-alex",
            authorName: "Alex",
            polls: []
        )

        try MemberShareSnapshotStore.merge(
            snapshots: [owner],
            into: club,
            context: context,
            localMemberID: "member-eve"
        )

        let polls = (try context.fetch(FetchDescriptor<SelectionPoll>()))
            .filter { $0.bookClub?.persistentModelID == club.persistentModelID }
        XCTAssertTrue(polls.isEmpty, "A remote poll absent from canonical must be deleted")
    }

    func test_mergeDeletesRemoteVoteNoLongerInCanonical() throws {
        let context = try makeContext()
        let club = try makeJoinedClub(zone: "BookClub-VoteDelete", in: context)

        // Owner poll exists locally with a stale remote vote attached.
        let poll = SelectionPoll(title: "Poll")
        poll.pollID = "poll-1"
        poll.createdByMemberID = "member-alex"
        poll.candidateIDsRaw = "sel-a"
        context.insert(poll)
        club.addSelectionPoll(poll)
        let staleVote = BookVote(memberID: "member-sam", memberName: "Sam", rankedSubmissionIDs: ["sel-a"])
        staleVote.poll = poll
        context.insert(staleVote)
        poll.votes = [staleVote]
        try context.save()

        // Owner re-publishes the poll but Sam's vote is gone from canonical.
        let owner = MemberShareSnapshot(
            capturedAt: Date(timeIntervalSince1970: 5_000),
            authorMemberID: "member-alex",
            authorName: "Alex",
            polls: [
                MemberShareSnapshot.PollPayload(
                    pollID: "poll-1",
                    createdByMemberID: "member-alex",
                    title: "Poll",
                    createdAt: Date(timeIntervalSince1970: 4_000),
                    closesAt: nil,
                    statusRaw: SelectionPollStatus.open.rawValue,
                    isAnonymousResults: true,
                    candidateIDsRaw: "sel-a",
                    winnerSubmissionID: ""
                )
            ],
            votes: []
        )

        try MemberShareSnapshotStore.merge(
            snapshots: [owner],
            into: club,
            context: context,
            localMemberID: "member-eve"
        )

        let poll1 = try XCTUnwrap(
            (try context.fetch(FetchDescriptor<SelectionPoll>())).first { $0.pollID == "poll-1" }
        )
        XCTAssertTrue((poll1.votes ?? []).isEmpty, "A remote vote absent from canonical must be deleted")
    }

    func test_mergeDeletesRemoteRSVPNoLongerInCanonical() throws {
        let context = try makeContext()
        let club = try makeJoinedClub(zone: "BookClub-RSVPDelete", in: context)

        let meeting = ClubMeeting(title: "Meeting", hostMemberID: "member-alex")
        meeting.meetingID = "meeting-1"
        context.insert(meeting)
        club.addMeeting(meeting)
        let staleRSVP = MeetingRSVP(memberID: "member-sam", memberName: "Sam", status: .attending)
        staleRSVP.meeting = meeting
        context.insert(staleRSVP)
        meeting.rsvps = [staleRSVP]
        try context.save()

        let owner = MemberShareSnapshot(
            capturedAt: Date(timeIntervalSince1970: 5_000),
            authorMemberID: "member-alex",
            authorName: "Alex",
            meetings: [emptyMeetingPayload()],
            rsvps: []
        )

        try MemberShareSnapshotStore.merge(
            snapshots: [owner],
            into: club,
            context: context,
            localMemberID: "member-eve"
        )

        let meeting1 = try XCTUnwrap(
            (try context.fetch(FetchDescriptor<ClubMeeting>())).first { $0.meetingID == "meeting-1" }
        )
        XCTAssertTrue((meeting1.rsvps ?? []).isEmpty, "A remote RSVP absent from canonical must be deleted")
    }

    func test_mergePreservesLocalMembersOwnRSVPAbsentFromCanonical() throws {
        let context = try makeContext()
        let club = try makeJoinedClub(zone: "BookClub-LocalRSVP", in: context)

        let meeting = ClubMeeting(title: "Meeting", hostMemberID: "member-alex")
        meeting.meetingID = "meeting-1"
        context.insert(meeting)
        club.addMeeting(meeting)
        // Eve (local) RSVP'd but hasn't published yet — must not be wiped.
        let localRSVP = MeetingRSVP(memberID: "member-eve", memberName: "Eve", status: .attending, bringingNote: "Wine")
        localRSVP.meeting = meeting
        context.insert(localRSVP)
        meeting.rsvps = [localRSVP]
        try context.save()

        let owner = MemberShareSnapshot(
            capturedAt: Date(timeIntervalSince1970: 5_000),
            authorMemberID: "member-alex",
            authorName: "Alex",
            meetings: [emptyMeetingPayload()],
            rsvps: []
        )

        try MemberShareSnapshotStore.merge(
            snapshots: [owner],
            into: club,
            context: context,
            localMemberID: "member-eve"
        )

        let meeting1 = try XCTUnwrap(
            (try context.fetch(FetchDescriptor<ClubMeeting>())).first { $0.meetingID == "meeting-1" }
        )
        let rsvps = meeting1.rsvps ?? []
        XCTAssertEqual(rsvps.map(\.memberID), ["member-eve"], "The local member's own RSVP must survive a merge that omits it")
        XCTAssertEqual(rsvps.first?.bringingNote, "Wine")
    }

    // MARK: - clubMeta selection (step 1)

    func test_mergeAdoptsClubMetaFromLatestMutationVersion() throws {
        let context = try makeContext()
        let club = try makeJoinedClub(zone: "BookClub-MetaTiebreak", in: context)

        // A stale owner snapshot reports a higher participant count, which
        // must not let stale admin/removal metadata outrank a newer snapshot.
        let stale = MemberShareSnapshot(
            capturedAt: Date(timeIntervalSince1970: 7_000),
            authorMemberID: "member-alex",
            authorName: "Alex",
            clubMeta: MemberShareSnapshot.ClubMeta(
                name: "Old Name",
                createdAt: Date(timeIntervalSince1970: 1_000),
                cloudZoneName: "BookClub-MetaTiebreak",
                shareParticipantCount: 5,
                creatorMemberID: "member-alex",
                adminMemberIDs: [],
                removedMemberIDs: [],
                metadataUpdatedAt: Date(timeIntervalSince1970: 2_000),
                inviteURLString: nil,
                nameUpdatedAt: nil
            )
        )
        // A fresher owner snapshot reports the new canonical state.
        let fresh = MemberShareSnapshot(
            capturedAt: Date(timeIntervalSince1970: 6_000),
            authorMemberID: "member-alex",
            authorName: "Alex",
            clubMeta: MemberShareSnapshot.ClubMeta(
                name: "New Name",
                createdAt: Date(timeIntervalSince1970: 1_000),
                cloudZoneName: "BookClub-MetaTiebreak",
                shareParticipantCount: 2,
                creatorMemberID: "member-alex",
                adminMemberIDs: [],
                removedMemberIDs: [],
                metadataUpdatedAt: Date(timeIntervalSince1970: 3_000),
                inviteURLString: nil,
                nameUpdatedAt: nil
            )
        )

        try MemberShareSnapshotStore.merge(
            snapshots: [stale, fresh],
            into: club,
            context: context,
            localMemberID: "member-eve"
        )

        XCTAssertEqual(club.name, "New Name", "a recaptured stale snapshot must not outrank a newer metadata mutation")
        XCTAssertEqual(club.shareParticipantCount, 2)
    }

    func test_mergeUsesCaptureTimeForLegacyClubMetaWithoutMutationVersion() throws {
        let context = try makeContext()
        let club = try makeJoinedClub(zone: "BookClub-LegacyMeta", in: context)
        let createdAt = Date(timeIntervalSince1970: 1_000)
        let stale = MemberShareSnapshot(
            capturedAt: Date(timeIntervalSince1970: 2_000),
            authorMemberID: "member-alex",
            authorName: "Alex",
            clubMeta: .init(
                name: "Old Name",
                createdAt: createdAt,
                cloudZoneName: "BookClub-LegacyMeta",
                shareParticipantCount: 4,
                creatorMemberID: "member-alex",
                adminMemberIDs: [],
                removedMemberIDs: [],
                inviteURLString: nil,
                nameUpdatedAt: nil
            )
        )
        let fresh = MemberShareSnapshot(
            capturedAt: Date(timeIntervalSince1970: 3_000),
            authorMemberID: "member-alex",
            authorName: "Alex",
            clubMeta: .init(
                name: "Fresh Name",
                createdAt: createdAt,
                cloudZoneName: "BookClub-LegacyMeta",
                shareParticipantCount: 2,
                creatorMemberID: "member-alex",
                adminMemberIDs: [],
                removedMemberIDs: [],
                inviteURLString: nil,
                nameUpdatedAt: nil
            )
        )

        try MemberShareSnapshotStore.merge(
            snapshots: [stale, fresh],
            into: club,
            context: context,
            localMemberID: "member-eve"
        )

        XCTAssertEqual(club.name, "Fresh Name")
        XCTAssertEqual(club.shareParticipantCount, 2)
        XCTAssertEqual(club.clubMetaUpdatedAt, fresh.capturedAt)
    }

    func test_mergeIgnoresNonOwnerSnapshotsCarryingNoClubMeta() throws {
        let context = try makeContext()
        let club = try makeJoinedClub(zone: "BookClub-NoMetaAdoption", in: context)
        club.name = "Canonical Name"
        club.shareParticipantCount = 3
        try context.save()

        // Only non-owner participants publish, none carrying clubMeta. The
        // club's existing canonical fields must be left intact (no clubMeta to
        // adopt → the step-1 block is skipped entirely).
        let sam = MemberShareSnapshot(
            capturedAt: Date(timeIntervalSince1970: 5_000),
            authorMemberID: "member-sam",
            authorName: "Sam",
            submissions: [ownerSubmissionPayload(selectionID: "sel-sam", title: "Sam's Book")]
        )

        try MemberShareSnapshotStore.merge(
            snapshots: [sam],
            into: club,
            context: context,
            localMemberID: "member-eve"
        )

        XCTAssertEqual(club.name, "Canonical Name", "Without clubMeta, a non-owner snapshot must not change the club name")
        XCTAssertEqual(club.shareParticipantCount, 3, "Participant count is owner-published; non-owner snapshots can't lower it")
    }

    func test_mergeCollapsesRatingsVotesAndRSVPsAcrossOnePersonsDevices() throws {
        let context = try makeContext()
        let club = try makeJoinedClub(zone: "BookClub-CrossDevice", in: context)
        club.memberIdentityBindings = [
            "member-alex": "cloud-owner",
            "member-sam-phone": "cloud-sam",
            "member-sam-mac": "cloud-sam"
        ]

        let owner = MemberShareSnapshot(
            capturedAt: Date(timeIntervalSince1970: 5_000),
            authorMemberID: "member-alex",
            authorName: "Alex",
            submissions: [ownerSubmissionPayload(selectionID: "sel-book")],
            polls: [
                .init(
                    pollID: "poll-1",
                    createdByMemberID: "member-alex",
                    title: "Pick One",
                    createdAt: Date(timeIntervalSince1970: 4_000),
                    closesAt: nil,
                    statusRaw: SelectionPollStatus.open.rawValue,
                    isAnonymousResults: false,
                    candidateIDsRaw: "sel-book",
                    winnerSubmissionID: ""
                )
            ],
            meetings: [emptyMeetingPayload()]
        )
        let phone = MemberShareSnapshot(
            capturedAt: Date(timeIntervalSince1970: 5_100),
            authorMemberID: "member-sam-phone",
            authorName: "Sam",
            ratings: [
                .init(
                    submissionSelectionID: "sel-book",
                    memberID: "member-sam-phone",
                    memberName: "Sam",
                    stars: 3,
                    createdAt: Date(timeIntervalSince1970: 5_010)
                )
            ],
            votes: [
                .init(
                    pollID: "poll-1",
                    memberID: "member-sam-phone",
                    memberName: "Sam",
                    rankedSubmissionIDsRaw: "sel-book",
                    updatedAt: Date(timeIntervalSince1970: 5_010)
                )
            ],
            rsvps: [
                .init(
                    meetingID: "meeting-1",
                    memberID: "member-sam-phone",
                    memberName: "Sam",
                    statusRaw: MeetingRSVPStatus.maybe.rawValue,
                    bringingNote: "",
                    updatedAt: Date(timeIntervalSince1970: 5_010)
                )
            ]
        )
        let mac = MemberShareSnapshot(
            capturedAt: Date(timeIntervalSince1970: 5_200),
            authorMemberID: "member-sam-mac",
            authorName: "Sam",
            ratings: [
                .init(
                    submissionSelectionID: "sel-book",
                    memberID: "member-sam-mac",
                    memberName: "Sam",
                    stars: 5,
                    createdAt: Date(timeIntervalSince1970: 5_020)
                )
            ],
            votes: [
                .init(
                    pollID: "poll-1",
                    memberID: "member-sam-mac",
                    memberName: "Sam",
                    rankedSubmissionIDsRaw: "sel-book",
                    updatedAt: Date(timeIntervalSince1970: 5_020)
                )
            ],
            rsvps: [
                .init(
                    meetingID: "meeting-1",
                    memberID: "member-sam-mac",
                    memberName: "Sam",
                    statusRaw: MeetingRSVPStatus.attending.rawValue,
                    bringingNote: "Snacks",
                    updatedAt: Date(timeIntervalSince1970: 5_020)
                )
            ]
        )

        try MemberShareSnapshotStore.merge(
            snapshots: [owner, phone, mac],
            into: club,
            context: context,
            localMemberID: "member-eve"
        )

        let submission = try XCTUnwrap(
            context.fetch(FetchDescriptor<BookSubmission>()).first { $0.selectionID == "sel-book" }
        )
        XCTAssertEqual(submission.ratings?.count, 1, "One Apple ID gets one rating")
        let rating = try XCTUnwrap(submission.ratings?.first)
        XCTAssertEqual(rating.memberID, "member-sam-mac")
        XCTAssertEqual(rating.stars, 5)

        let poll = try XCTUnwrap(
            context.fetch(FetchDescriptor<SelectionPoll>()).first { $0.pollID == "poll-1" }
        )
        XCTAssertEqual(poll.votes?.count, 1, "One Apple ID gets one ballot even when it publishes from multiple devices")
        XCTAssertEqual(poll.votes?.first?.memberID, "member-sam-mac")

        let meeting = try XCTUnwrap(
            context.fetch(FetchDescriptor<ClubMeeting>()).first { $0.meetingID == "meeting-1" }
        )
        XCTAssertEqual(meeting.rsvps?.count, 1, "One Apple ID gets one RSVP")
        XCTAssertEqual(meeting.rsvps?.first?.status, .attending)
        XCTAssertEqual(meeting.rsvps?.first?.bringingNote, "Snacks")
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
