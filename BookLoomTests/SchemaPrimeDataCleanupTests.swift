import SwiftData
import XCTest
@testable import BookLoom

@MainActor
final class SchemaPrimeDataCleanupTests: XCTestCase {
    func test_removeSchemaPrimeDataDeletesOnlySignedSeedClubs() throws {
        let context = try makeContext()
        let stale = BookClub(name: "Schema Prime")
        let staleSubmission = BookSubmission(
            title: "Schema Prime",
            bookDescription: "Development-only record used to register CloudKit schema.",
            submittedBy: "PlotLoom",
            submittedByMemberID: "schema-prime"
        )
        context.insert(stale)
        context.insert(staleSubmission)
        stale.addSubmission(staleSubmission)

        let legitimateSameName = BookClub(name: "Schema Prime")
        let legitimateSubmission = BookSubmission(title: "A Real Proposal", bookDescription: "Member-created club.")
        context.insert(legitimateSameName)
        context.insert(legitimateSubmission)
        legitimateSameName.addSubmission(legitimateSubmission)

        let ordinary = BookClub(name: "Tuesday Bookworms")
        context.insert(ordinary)
        try context.save()

        XCTAssertTrue(SchemaPrimeDataCleanup.isSchemaPrime(stale))
        XCTAssertFalse(SchemaPrimeDataCleanup.isSchemaPrime(legitimateSameName))

        XCTAssertEqual(SchemaPrimeDataCleanup.removeSchemaPrimeData(from: context), 1)

        let fetched = try context.fetch(FetchDescriptor<BookClub>())
        XCTAssertEqual(fetched.count, 2)
        XCTAssertTrue(fetched.contains { $0 === legitimateSameName })
        XCTAssertTrue(fetched.contains { $0 === ordinary })
        XCTAssertFalse(fetched.contains { $0 === stale })
    }

    func test_removeSchemaPrimeDataDeletesShareRootPrimeClubsWithoutSubmissions() throws {
        let context = try makeContext()
        let stale = BookClub(name: "Schema Prime")
        stale.cloudZoneName = "BookClub-SchemaPrime-123"
        context.insert(stale)
        try context.save()

        XCTAssertEqual(SchemaPrimeDataCleanup.removeSchemaPrimeData(from: context), 1)

        let fetched = try context.fetch(FetchDescriptor<BookClub>())
        XCTAssertTrue(fetched.isEmpty)
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
