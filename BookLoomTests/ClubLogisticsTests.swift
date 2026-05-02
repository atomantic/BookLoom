import SwiftData
import XCTest
@testable import BookLoom

final class ClubLogisticsTests: XCTestCase {
    func test_meetingReminderPlanner_filtersPastReminderDatesAndSortsAscending() {
        let now = Date(timeIntervalSince1970: 1_000)
        let meetingDate = Date(timeIntervalSince1970: 4_600)

        let reminders = MeetingReminderPlanner.reminderDates(
            scheduledAt: meetingDate,
            offsetsMinutes: [1440, 15, 60, 0],
            now: now
        )

        XCTAssertEqual(reminders, [
            Date(timeIntervalSince1970: 1_000),
            Date(timeIntervalSince1970: 3_700),
            Date(timeIntervalSince1970: 4_600)
        ].filter { $0 > now })
    }

    func test_selectionPollReplacesBallotForSameMember() {
        let first = BookSubmission(title: "A")
        let second = BookSubmission(title: "B")
        let poll = SelectionPoll(title: "Vote", candidates: [first, second])

        poll.replaceVote(memberID: "member-1", memberName: "Alex", rankedSubmissionIDs: [first.selectionID])
        poll.replaceVote(memberID: "member-1", memberName: "Alex", rankedSubmissionIDs: [second.selectionID, first.selectionID])

        XCTAssertEqual(poll.votes?.count, 1)
        XCTAssertEqual(poll.votes?.first?.rankedSubmissionIDs, [second.selectionID, first.selectionID])
    }

    func test_selectionPollScoringDetectsTie() {
        let first = BookSubmission(title: "A")
        let second = BookSubmission(title: "B")
        let poll = SelectionPoll(title: "Vote", candidates: [first, second])

        poll.replaceVote(memberID: "member-1", memberName: "Alex", rankedSubmissionIDs: [first.selectionID])
        poll.replaceVote(memberID: "member-2", memberName: "Sam", rankedSubmissionIDs: [second.selectionID])

        let tally = SelectionPollScorer.tally(votes: poll.votes ?? [], candidateIDs: poll.candidateIDs)

        XCTAssertTrue(tally.hasTie)
        XCTAssertEqual(Set(tally.winningResults.map(\.id)), Set([first.selectionID, second.selectionID]))
    }

    func test_promoteWinnerCompletesExistingCurrentBook() {
        let club = BookClub(name: "Tuesday")
        let current = BookSubmission(title: "Current", status: .current)
        let winner = BookSubmission(title: "Winner", status: .proposed)
        club.addSubmission(current)
        club.addSubmission(winner)

        let pickedAt = Date(timeIntervalSince1970: 10)
        SelectionPollCoordinator.promoteWinner(winner, in: club, pickedAt: pickedAt)

        XCTAssertEqual(current.status, .completed)
        XCTAssertEqual(current.completedAt, pickedAt)
        XCTAssertEqual(winner.status, .current)
        XCTAssertEqual(winner.pickedAt, pickedAt)
    }

    func test_discussionPromptLibraryAddsStarterPromptsOnce() throws {
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
        let context = ModelContext(container)
        let submission = BookSubmission(title: "Piranesi")
        context.insert(submission)

        DiscussionPromptLibrary.ensureStarterPrompts(for: submission, context: context)
        DiscussionPromptLibrary.ensureStarterPrompts(for: submission, context: context)

        XCTAssertEqual(submission.activeDiscussionPrompts.count, DiscussionPromptLibrary.starterQuestions.count)
    }
}
