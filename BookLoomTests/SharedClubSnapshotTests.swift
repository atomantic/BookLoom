import Foundation
import SwiftData
import XCTest
@testable import BookLoom

@MainActor
final class SharedClubSnapshotTests: XCTestCase {
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
                shareParticipantCount: 2
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
                shareParticipantCount: 2
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
                shareParticipantCount: 2
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
