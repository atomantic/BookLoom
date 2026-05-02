import XCTest
import SwiftData
@testable import BookLoom

final class ReadingMetricsTests: XCTestCase {
    func test_sectionsSortCurrentProposedAndCompleted() {
        let older = Date(timeIntervalSince1970: 100)
        let newer = Date(timeIntervalSince1970: 200)

        let proposedA = BookSubmission(title: "A", submittedAt: newer, status: .proposed)
        let proposedB = BookSubmission(title: "B", submittedAt: older, status: .proposed)
        let current = BookSubmission(title: "Current", submittedAt: older, status: .current)
        current.pickedAt = newer
        let completedA = BookSubmission(title: "Done A", submittedAt: older, status: .completed)
        completedA.completedAt = older
        let completedB = BookSubmission(title: "Done B", submittedAt: newer, status: .completed)
        completedB.completedAt = newer

        let sections = BookClubSubmissionSections(submissions: [
            proposedA,
            completedA,
            current,
            completedB,
            proposedB
        ])

        XCTAssertEqual(sections.current?.title, "Current")
        XCTAssertEqual(sections.proposed.map(\.title), ["B", "A"])
        XCTAssertEqual(sections.completed.map(\.title), ["Done B", "Done A"])
    }

    func test_metricsCountsSubmissionsEngagementAndMembers() {
        let current = BookSubmission(title: "Current", submittedBy: "Alex", status: .current)
        let proposed = BookSubmission(title: "Proposal", submittedBy: "Sam", status: .proposed)
        let completed = BookSubmission(title: "Done", submittedBy: "Alex", status: .completed)

        let rating = Rating(memberName: "Riley", stars: 4)
        let note = BookNote(memberName: "Sam", text: "Great discussion pick.")
        current.ratings = [rating]
        proposed.notes = [note]

        let metrics = BookClubMetrics(submissions: [current, proposed, completed])

        XCTAssertEqual(metrics.currentCount, 1)
        XCTAssertEqual(metrics.proposedCount, 1)
        XCTAssertEqual(metrics.completedCount, 1)
        XCTAssertEqual(metrics.totalSubmissionCount, 3)
        XCTAssertEqual(metrics.ratingCount, 1)
        XCTAssertEqual(metrics.noteCount, 1)
        XCTAssertEqual(metrics.memberCount, 3)
    }

    func test_ratingSummaryFormatsAverage() {
        let summary = RatingSummary(ratings: [
            Rating(memberName: "Alex", stars: 5),
            Rating(memberName: "Sam", stars: 4)
        ])

        XCTAssertEqual(summary.count, 2)
        XCTAssertEqual(summary.average, 4.5)
        XCTAssertEqual(summary.displayValue, "4.5")
    }

    func test_addSubmissionAttachesProposalToClubSections() throws {
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
        let club = BookClub(name: "Tuesday Bookworms")
        let submission = BookSubmission(title: "Piranesi", author: "Susanna Clarke", submittedBy: "Alex")

        context.insert(club)
        club.addSubmission(submission)
        context.insert(submission)
        try context.save()

        let fetchedClub = try XCTUnwrap(try context.fetch(FetchDescriptor<BookClub>()).first)
        XCTAssertEqual(fetchedClub.sections.proposed.map(\.title), ["Piranesi"])
        XCTAssertEqual(fetchedClub.metrics.proposedCount, 1)
    }

    func test_displayedMemberCountIncludesOwnerBeforeEngagement() {
        let club = BookClub(name: "Tuesday Bookworms")

        XCTAssertEqual(club.metrics.memberCount, 0)
        XCTAssertEqual(club.displayedMemberCount, 1)
    }
}
