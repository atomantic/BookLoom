import Foundation
import SwiftData
import XCTest
@testable import BookLoom

@MainActor
final class GoodreadsImportInboxTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() async throws {
        try await super.setUp()
        suiteName = "GoodreadsImportInboxTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        try await super.tearDown()
    }

    func test_pendingMirrorsSharedInboxOnInit() {
        let url = URL(string: "https://www.goodreads.com/book/show/1")!
        SharedImportInbox.enqueue(url, defaults: defaults)

        let inbox = GoodreadsImportInbox(defaults: defaults)

        XCTAssertEqual(inbox.pending.map(\.url), [url])
    }

    func test_refreshPicksUpExternalShareAfterInit() {
        let url = URL(string: "https://www.goodreads.com/book/show/99")!
        let inbox = GoodreadsImportInbox(defaults: defaults)
        XCTAssertTrue(inbox.pending.isEmpty)

        SharedImportInbox.enqueue(url, defaults: defaults)
        inbox.refresh()

        XCTAssertEqual(inbox.pending.map(\.url), [url])
    }

    func test_dismissWithSavedTrueRemovesURLFromQueue() {
        let url = URL(string: "https://www.goodreads.com/book/show/42")!
        SharedImportInbox.enqueue(url, defaults: defaults)
        let inbox = GoodreadsImportInbox(defaults: defaults)
        inbox.present(url)

        inbox.dismiss(saved: true)

        XCTAssertNil(inbox.presentedItem)
        XCTAssertEqual(SharedImportInbox.pendingCount(defaults: defaults), 0)
    }

    func test_dismissWithSavedFalseKeepsURLInQueue() {
        let url = URL(string: "https://www.goodreads.com/book/show/77")!
        SharedImportInbox.enqueue(url, defaults: defaults)
        let inbox = GoodreadsImportInbox(defaults: defaults)
        inbox.present(url)

        inbox.dismiss(saved: false)

        XCTAssertNil(inbox.presentedItem)
        XCTAssertEqual(SharedImportInbox.pendingCount(defaults: defaults), 1, "Cancelled imports must remain in the inbox so users can return to them")
    }

    func test_presentNextIfNeededDoesNotLoopOnClosedURL() {
        let first = URL(string: "https://www.goodreads.com/book/show/1")!
        let second = URL(string: "https://www.goodreads.com/book/show/2")!
        SharedImportInbox.enqueue(first, defaults: defaults)
        SharedImportInbox.enqueue(second, defaults: defaults)
        let inbox = GoodreadsImportInbox(defaults: defaults)

        inbox.presentNextIfNeeded()
        XCTAssertEqual(inbox.presentedItem?.url, first)

        inbox.dismiss(saved: false)
        inbox.presentNextIfNeeded()

        XCTAssertEqual(inbox.presentedItem?.url, second, "After closing the first share, auto-pop should advance to the next, not loop on the same URL")
    }

    func test_presentBypassesSkipSetForManualOpen() {
        let url = URL(string: "https://www.goodreads.com/book/show/manual")!
        SharedImportInbox.enqueue(url, defaults: defaults)
        let inbox = GoodreadsImportInbox(defaults: defaults)
        inbox.presentNextIfNeeded()
        inbox.dismiss(saved: false)

        inbox.present(url)
        XCTAssertEqual(inbox.presentedItem?.url, url)
    }

    func test_removeDropsURLFromQueue() {
        let keep = URL(string: "https://www.goodreads.com/book/show/keep")!
        let drop = URL(string: "https://www.goodreads.com/book/show/drop")!
        SharedImportInbox.enqueue(keep, defaults: defaults)
        SharedImportInbox.enqueue(drop, defaults: defaults)
        let inbox = GoodreadsImportInbox(defaults: defaults)

        inbox.remove(drop)

        XCTAssertEqual(SharedImportInbox.peekAll(defaults: defaults).map(\.url), [keep])
        XCTAssertEqual(inbox.pending.map(\.url), [keep])
    }

    func test_presentNextIfNeededSkipsItemsOlderThanAutoPresentWindow() {
        let stale = URL(string: "https://www.goodreads.com/book/show/stale")!
        let staleEnqueuedAt = Date.now.addingTimeInterval(-GoodreadsImportInbox.autoPresentMaxAge - 60)
        SharedImportInbox.enqueue(stale, defaults: defaults, now: staleEnqueuedAt)
        let inbox = GoodreadsImportInbox(defaults: defaults)

        inbox.presentNextIfNeeded()

        XCTAssertNil(inbox.presentedItem, "Items shared more than 10 minutes ago should not auto-prompt")
        XCTAssertEqual(inbox.pending.map(\.url), [stale], "Stale items remain on the Shelf, just not auto-presented")
    }

    func test_presentNextIfNeededSurfacesRecentlyEnqueuedItem() {
        let fresh = URL(string: "https://www.goodreads.com/book/show/fresh")!
        SharedImportInbox.enqueue(fresh, defaults: defaults)
        let inbox = GoodreadsImportInbox(defaults: defaults)

        inbox.presentNextIfNeeded()

        XCTAssertEqual(inbox.presentedItem?.url, fresh, "Recently shared items still auto-prompt")
    }

    func test_presentNextIfNeededWalksPastStaleItemsToReachFreshOne() {
        let stale = URL(string: "https://www.goodreads.com/book/show/stale")!
        let fresh = URL(string: "https://www.goodreads.com/book/show/fresh")!
        let staleEnqueuedAt = Date.now.addingTimeInterval(-GoodreadsImportInbox.autoPresentMaxAge - 60)
        SharedImportInbox.enqueue(stale, defaults: defaults, now: staleEnqueuedAt)
        SharedImportInbox.enqueue(fresh, defaults: defaults)
        let inbox = GoodreadsImportInbox(defaults: defaults)

        inbox.presentNextIfNeeded()

        XCTAssertEqual(inbox.presentedItem?.url, fresh, "Auto-pop should skip past stale items and surface a freshly enqueued one")
    }

    func test_moveSubmissionToShelfReturnsFalseForNonGoodreadsSubmission() throws {
        let context = try makeModelContext()
        let club = BookClub(name: "Test")
        context.insert(club)
        let submission = BookSubmission(title: "Manual Add", externalProvider: "", externalID: "")
        club.addSubmission(submission)
        context.insert(submission)
        let inbox = GoodreadsImportInbox(defaults: defaults)

        XCTAssertFalse(inbox.moveSubmissionToShelf(submission, context: context))
        XCTAssertEqual(SharedImportInbox.pendingCount(defaults: defaults), 0)
        XCTAssertFalse(submission.isDeleted, "A submission that can't be moved should remain in the club")
    }

    func test_moveSubmissionToShelfRebuildsGoodreadsURLAndCopiesMetadata() throws {
        let context = try makeModelContext()
        let club = BookClub(name: "Test")
        context.insert(club)
        let submission = BookSubmission(
            title: "Piranesi",
            author: "Susanna Clarke",
            isbn: "9781635575637",
            bookDescription: "A man lives in an infinite house.",
            publishedYear: 2020,
            coverURL: "https://example.com/cover.jpg",
            externalProvider: BookMetadataProvider.goodreads.rawValue,
            externalID: "50202953"
        )
        club.addSubmission(submission)
        context.insert(submission)
        let inbox = GoodreadsImportInbox(defaults: defaults)

        XCTAssertTrue(inbox.moveSubmissionToShelf(submission, context: context))

        let queue = SharedImportInbox.peekAll(defaults: defaults)
        XCTAssertEqual(queue.count, 1)
        let entry = try XCTUnwrap(queue.first)
        XCTAssertEqual(entry.url.absoluteString, "https://www.goodreads.com/book/show/50202953")
        XCTAssertEqual(entry.displayTitle, "Piranesi")
        XCTAssertEqual(entry.displayAuthor, "Susanna Clarke")
        XCTAssertEqual(entry.isbn, "9781635575637")
        XCTAssertEqual(entry.publishedYear, 2020)
        XCTAssertEqual(entry.coverURLString, "https://example.com/cover.jpg")
        XCTAssertTrue(entry.hasResolvedMetadata)
    }

    func test_moveSubmissionToShelfDoesNotImmediatelyAutoPrompt() throws {
        let context = try makeModelContext()
        let club = BookClub(name: "Test")
        context.insert(club)
        let submission = BookSubmission(
            title: "Piranesi",
            externalProvider: BookMetadataProvider.goodreads.rawValue,
            externalID: "50202953"
        )
        club.addSubmission(submission)
        context.insert(submission)
        let inbox = GoodreadsImportInbox(defaults: defaults)

        XCTAssertTrue(inbox.moveSubmissionToShelf(submission, context: context))
        inbox.presentNextIfNeeded()

        XCTAssertNil(inbox.presentedItem, "A submission moved to the Shelf is not freshly added — it should not auto-prompt")
    }

    private func makeModelContext() throws -> ModelContext {
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
