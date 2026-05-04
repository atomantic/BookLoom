import Foundation
import XCTest
@testable import BookLoom

final class SharedImportInboxTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "SharedImportInboxTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func test_enqueueAddsURLToQueue() {
        let url = URL(string: "https://www.goodreads.com/book/show/1")!
        SharedImportInbox.enqueue(url, defaults: defaults)

        XCTAssertEqual(SharedImportInbox.pendingCount(defaults: defaults), 1)
        XCTAssertEqual(SharedImportInbox.peekNext(defaults: defaults), url)
    }

    func test_enqueuePreservesOrderAcrossMultipleShares() {
        let first = URL(string: "https://www.goodreads.com/book/show/1")!
        let second = URL(string: "https://www.goodreads.com/book/show/2")!
        let third = URL(string: "https://www.goodreads.com/book/show/3")!
        let base = Date.now

        SharedImportInbox.enqueue(first, defaults: defaults, now: base)
        SharedImportInbox.enqueue(second, defaults: defaults, now: base.addingTimeInterval(1))
        SharedImportInbox.enqueue(third, defaults: defaults, now: base.addingTimeInterval(2))

        let urls = SharedImportInbox.peekAll(defaults: defaults, now: base.addingTimeInterval(3)).map(\.url)
        XCTAssertEqual(urls, [first, second, third])
    }

    func test_enqueueDeduplicatesIdenticalURL() {
        let url = URL(string: "https://www.goodreads.com/book/show/42")!
        SharedImportInbox.enqueue(url, defaults: defaults)
        SharedImportInbox.enqueue(url, defaults: defaults)
        SharedImportInbox.enqueue(url, defaults: defaults)

        XCTAssertEqual(SharedImportInbox.pendingCount(defaults: defaults), 1)
    }

    func test_removeDeletesSpecificURL() {
        let first = URL(string: "https://www.goodreads.com/book/show/1")!
        let second = URL(string: "https://www.goodreads.com/book/show/2")!
        let base = Date.now
        SharedImportInbox.enqueue(first, defaults: defaults, now: base)
        SharedImportInbox.enqueue(second, defaults: defaults, now: base.addingTimeInterval(1))

        SharedImportInbox.remove(first, defaults: defaults, now: base.addingTimeInterval(2))

        XCTAssertEqual(SharedImportInbox.peekAll(defaults: defaults, now: base.addingTimeInterval(3)).map(\.url), [second])
    }

    func test_clearRemovesAllPending() {
        SharedImportInbox.enqueue(URL(string: "https://www.goodreads.com/book/show/1")!, defaults: defaults)
        SharedImportInbox.enqueue(URL(string: "https://www.goodreads.com/book/show/2")!, defaults: defaults)

        SharedImportInbox.clear(defaults: defaults)

        XCTAssertEqual(SharedImportInbox.pendingCount(defaults: defaults), 0)
    }

    func test_agedEntriesArePrunedOnRead() {
        let fresh = URL(string: "https://www.goodreads.com/book/show/fresh")!
        let stale = URL(string: "https://www.goodreads.com/book/show/stale")!
        let now = Date(timeIntervalSinceReferenceDate: 1_000_000)
        let staleTime = now.addingTimeInterval(-(SharedImportInbox.pendingMaxAge + 60))

        SharedImportInbox.enqueue(stale, defaults: defaults, now: staleTime)
        SharedImportInbox.enqueue(fresh, defaults: defaults, now: now)

        let urls = SharedImportInbox.peekAll(defaults: defaults, now: now).map(\.url)
        XCTAssertEqual(urls, [fresh])
    }

    func test_legacySingleURLEntryIsDrainedIntoQueueOnce() {
        let legacy = URL(string: "https://www.goodreads.com/book/show/legacy")!
        defaults.set(legacy.absoluteString, forKey: SharedImportInbox.legacyURLKey)
        defaults.set(Date.now.timeIntervalSince1970, forKey: SharedImportInbox.legacyTimestampKey)

        let firstRead = SharedImportInbox.peekAll(defaults: defaults).map(\.url)
        XCTAssertEqual(firstRead, [legacy])

        // After draining, the legacy entry is migrated into the queue and the
        // legacy keys are removed; reading again shouldn't duplicate it.
        let secondRead = SharedImportInbox.peekAll(defaults: defaults).map(\.url)
        XCTAssertEqual(secondRead, [legacy])
        XCTAssertNil(defaults.string(forKey: SharedImportInbox.legacyURLKey))
    }
}
