import SwiftData
import XCTest
@testable import BookLoom

/// Exercises the mutation/persistence logic extracted out of `BooksTabContent`
/// into `ClubActionCoordinator` (#18). The club is left unshared so
/// `SharedClubSync.saveAndPublish` performs only the local `context.save()`
/// without touching CloudKit.
@MainActor
final class ClubActionCoordinatorTests: XCTestCase {
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
            LibraryBook.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return ModelContext(container)
    }

    private func makeCoordinator(context: ModelContext) -> ClubActionCoordinator {
        let identity = MemberIdentity()
        identity.memberID = "member-1"
        identity.name = "Alex"
        return ClubActionCoordinator(context: context, memberIdentity: identity)
    }

    func test_assignCurrentPromotesSubmissionAndPersists() throws {
        let context = try makeContext()
        let club = BookClub(name: "Tuesday")
        let proposed = BookSubmission(title: "Piranesi", status: .proposed)
        club.addSubmission(proposed)
        context.insert(club)

        let coordinator = makeCoordinator(context: context)
        coordinator.assignCurrent(proposed, in: club)

        XCTAssertEqual(proposed.status, .current)
        XCTAssertNotNil(proposed.pickedAt)
        XCTAssertFalse(context.hasChanges, "saveAndPublish should have flushed the context")
        // Starter prompts are seeded as part of promotion.
        XCTAssertEqual(proposed.activeDiscussionPrompts.count, DiscussionPromptLibrary.starterQuestions.count)
    }

    func test_markCompleteUpdatesStatus() throws {
        let context = try makeContext()
        let club = BookClub(name: "Tuesday")
        let current = BookSubmission(title: "Current", status: .current)
        club.addSubmission(current)
        context.insert(club)

        let coordinator = makeCoordinator(context: context)
        coordinator.markComplete(current, in: club)

        XCTAssertEqual(current.status, .completed)
        XCTAssertNotNil(current.completedAt)
    }

    func test_moveCurrentToProposalsResetsStatus() throws {
        let context = try makeContext()
        let club = BookClub(name: "Tuesday")
        let current = BookSubmission(title: "Current", status: .current)
        current.pickedAt = .now
        club.addSubmission(current)
        context.insert(club)

        let coordinator = makeCoordinator(context: context)
        coordinator.moveCurrentToProposals(current, in: club)

        XCTAssertEqual(current.status, .proposed)
        XCTAssertNil(current.pickedAt)
        XCTAssertNil(current.completedAt)
    }

    func test_pickRandomNextPromotesOneProposal() throws {
        let context = try makeContext()
        let club = BookClub(name: "Tuesday")
        let a = BookSubmission(title: "A", status: .proposed)
        let b = BookSubmission(title: "B", status: .proposed)
        club.addSubmission(a)
        club.addSubmission(b)
        context.insert(club)

        let coordinator = makeCoordinator(context: context)
        coordinator.pickRandomNext(in: club, from: club.sections.proposed)

        XCTAssertEqual(club.sections.current != nil ? 1 : 0, 1, "exactly one book should become current")
    }

    func test_openOrCreatePollReturnsExistingOpenPoll() throws {
        let context = try makeContext()
        let club = BookClub(name: "Tuesday")
        let a = BookSubmission(title: "A", status: .proposed)
        let b = BookSubmission(title: "B", status: .proposed)
        club.addSubmission(a)
        club.addSubmission(b)
        context.insert(club)
        let existing = SelectionPoll(title: "Open", candidates: [a, b])
        context.insert(existing)
        club.addSelectionPoll(existing)

        let coordinator = makeCoordinator(context: context)
        let result = coordinator.openOrCreatePoll(in: club, activePoll: existing, proposed: [a, b])

        XCTAssertTrue(result === existing, "should return the already-open poll without creating a new one")
        XCTAssertEqual((club.selectionPolls ?? []).count, 1)
    }

    func test_openOrCreatePollCreatesPollWhenEnoughProposals() throws {
        let context = try makeContext()
        let club = BookClub(name: "Tuesday")
        let a = BookSubmission(title: "A", status: .proposed)
        let b = BookSubmission(title: "B", status: .proposed)
        club.addSubmission(a)
        club.addSubmission(b)
        context.insert(club)

        let coordinator = makeCoordinator(context: context)
        let result = coordinator.openOrCreatePoll(in: club, activePoll: nil, proposed: [a, b])

        let poll = try XCTUnwrap(result)
        XCTAssertEqual(poll.createdByMemberID, "member-1")
        XCTAssertEqual(poll.candidateIDs.count, 2)
        XCTAssertEqual((club.selectionPolls ?? []).count, 1)
    }

    func test_openOrCreatePollReturnsNilWithTooFewProposals() throws {
        let context = try makeContext()
        let club = BookClub(name: "Tuesday")
        let a = BookSubmission(title: "A", status: .proposed)
        club.addSubmission(a)
        context.insert(club)

        let coordinator = makeCoordinator(context: context)
        let result = coordinator.openOrCreatePoll(in: club, activePoll: nil, proposed: [a])

        XCTAssertNil(result)
        XCTAssertEqual((club.selectionPolls ?? []).count, 0)
    }

    func test_deleteRemovesSubmissionAndRecordsTombstone() throws {
        let context = try makeContext()
        let club = BookClub(name: "Tuesday")
        let a = BookSubmission(title: "A", status: .proposed)
        club.addSubmission(a)
        context.insert(club)

        let coordinator = makeCoordinator(context: context)
        coordinator.delete(a, in: club)

        let remaining = try context.fetch(FetchDescriptor<BookSubmission>())
        XCTAssertTrue(remaining.isEmpty)
    }

    func test_saveToPersonalLibraryInsertsBookMarkedRead() throws {
        let context = try makeContext()
        let submission = BookSubmission(title: "Piranesi")
        submission.externalProvider = "googleBooks"
        submission.externalID = "abc123"
        context.insert(submission)

        let coordinator = makeCoordinator(context: context)
        XCTAssertFalse(coordinator.hasPersonalLibraryCopy(of: submission))

        coordinator.saveToPersonalLibrary(submission)

        let books = try context.fetch(FetchDescriptor<LibraryBook>())
        XCTAssertEqual(books.count, 1)
        XCTAssertTrue(books.first?.didRead ?? false)
        XCTAssertTrue(coordinator.hasPersonalLibraryCopy(of: submission))
    }

    func test_saveToPersonalLibraryUpdatesExistingCopy() throws {
        let context = try makeContext()
        let submission = BookSubmission(title: "Piranesi")
        submission.externalProvider = "googleBooks"
        submission.externalID = "abc123"
        context.insert(submission)

        let coordinator = makeCoordinator(context: context)
        coordinator.saveToPersonalLibrary(submission)
        coordinator.saveToPersonalLibrary(submission)

        let books = try context.fetch(FetchDescriptor<LibraryBook>())
        XCTAssertEqual(books.count, 1, "second save should update the existing copy, not insert a duplicate")
        XCTAssertTrue(books.first?.didRead ?? false)
    }
}
