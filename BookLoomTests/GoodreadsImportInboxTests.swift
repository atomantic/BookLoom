import Foundation
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
}
