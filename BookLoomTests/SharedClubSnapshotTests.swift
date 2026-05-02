import Foundation
import SwiftData
import XCTest
@testable import BookLoom

@MainActor
final class SharedClubSnapshotTests: XCTestCase {
    func test_snapshotImportReplacesPlaceholderWithFullClubGraph() throws {
        let context = try makeContext()
        let owner = BookClub(name: "Sunday Pages", createdAt: Date(timeIntervalSince1970: 1_000))
        owner.cloudZoneName = "BookClub-Test"
        owner.shareIsActive = true
        owner.shareParticipantCount = 3
        context.insert(owner)

        let submission = BookSubmission(
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
        submission.selectionID = "selection-piranesi"
        submission.coverData = Data([1, 2, 3, 4])
        owner.addSubmission(submission)
        context.insert(submission)

        let rating = Rating(memberID: "member-sam", memberName: "Sam", stars: 5)
        rating.submission = submission
        context.insert(rating)
        submission.ratings = [rating]

        let note = BookNote(memberID: "member-alex", memberName: "Alex", text: "Great meeting pick.")
        note.submission = submission
        context.insert(note)
        submission.notes = [note]

        let prompt = DiscussionPrompt(question: "What changes when the house feels infinite?", orderIndex: 0, source: .starter)
        prompt.submission = submission
        context.insert(prompt)
        submission.discussionPrompts = [prompt]

        let meeting = ClubMeeting(
            title: "Piranesi Discussion",
            scheduledAt: Date(timeIntervalSince1970: 2_000),
            hostName: "Alex",
            hostMemberID: "member-alex",
            location: "Library",
            reminderOffsets: [60],
            agenda: "Talk endings."
        )
        meeting.bookSubmission = submission
        owner.addMeeting(meeting)
        context.insert(meeting)
        let rsvp = meeting.upsertRSVP(memberID: "member-sam", memberName: "Sam", status: .attending)
        context.insert(rsvp)

        let poll = SelectionPoll(title: "Next Book Vote", candidates: [submission])
        owner.addSelectionPoll(poll)
        context.insert(poll)
        let vote = poll.replaceVote(memberID: "member-sam", memberName: "Sam", rankedSubmissionIDs: [submission.selectionID])
        context.insert(vote)
        try context.save()

        let snapshot = SharedClubSnapshotStore.snapshot(from: owner, capturedAt: Date(timeIntervalSince1970: 3_000))
        let encodedSnapshot = try JSONEncoder().encode(snapshot)
        XCTAssertFalse(String(data: encodedSnapshot, encoding: .utf8)?.contains("coverData") ?? true)

        let joined = BookClub(name: "Book Club: Sunday Pages")
        joined.cloudZoneName = "BookClub-Test"
        joined.ownerUserRecordName = "owner-record"
        joined.shareIsActive = true
        context.insert(joined)

        try SharedClubSnapshotStore.apply(snapshot, to: joined, context: context)

        XCTAssertEqual(joined.name, "Sunday Pages")
        XCTAssertEqual(joined.shareParticipantCount, 3)
        XCTAssertEqual(joined.lastSharedSnapshotAt, snapshot.capturedAt)
        XCTAssertEqual(joined.submissions?.count, 1)
        XCTAssertEqual(joined.submissions?.first?.selectionID, "selection-piranesi")
        XCTAssertEqual(joined.submissions?.first?.coverURL, "https://example.com/piranesi.jpg")
        XCTAssertNil(joined.submissions?.first?.coverData)
        XCTAssertEqual(joined.submissions?.first?.ratings?.first?.stars, 5)
        XCTAssertEqual(joined.submissions?.first?.notes?.first?.text, "Great meeting pick.")
        XCTAssertEqual(joined.submissions?.first?.discussionPrompts?.first?.source, .starter)
        XCTAssertEqual(joined.meetings?.first?.bookSubmission?.selectionID, "selection-piranesi")
        XCTAssertEqual(joined.meetings?.first?.rsvps?.first?.memberName, "Sam")
        XCTAssertEqual(joined.selectionPolls?.first?.votes?.first?.rankedSubmissionIDs, ["selection-piranesi"])
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
