import SwiftData
import XCTest
@testable import BookLoom

/// The per-club `clearPersistedCoverData(in:)` overload is covered in
/// SharedClubSnapshotTests. This pins the global (all-submissions, context)
/// overload used on launch to evict legacy on-disk cover bytes across every
/// club, including submissions not attached to any club.
@MainActor
final class CoverDataCleanupTests: XCTestCase {
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

    func test_coverDataCleanupClearsAllSubmissionsViaContext() throws {
        let context = try makeContext()

        let clubA = BookClub(name: "Club A")
        let inClub = BookSubmission(title: "Cached A", coverURL: "https://example.com/a.jpg")
        inClub.coverData = Data([1, 2, 3])
        context.insert(clubA)
        context.insert(inClub)
        clubA.addSubmission(inClub)

        // A submission with no club at all — the per-club overload would miss
        // it, but the context overload must still strip its bytes.
        let orphan = BookSubmission(title: "Cached Orphan", coverURL: "https://example.com/orphan.jpg")
        orphan.coverData = Data([4, 5, 6])
        context.insert(orphan)

        // A submission that already has no cover bytes — must be left untouched.
        let clean = BookSubmission(title: "No Cover")
        context.insert(clean)

        try context.save()

        CoverDataCleanup.clearPersistedCoverData(in: context)

        XCTAssertNil(inClub.coverData, "In-club submission cover bytes must be cleared")
        XCTAssertNil(orphan.coverData, "Orphan submission cover bytes must be cleared")
        XCTAssertNil(clean.coverData)

        // Persisted: a freshly fetched copy must also see nil cover bytes.
        let refetched = try context.fetch(FetchDescriptor<BookSubmission>())
        XCTAssertEqual(refetched.count, 3)
        XCTAssertTrue(refetched.allSatisfy { $0.coverData == nil }, "Cleared cover bytes must be saved to the store")
    }
}
