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

    func test_shareConfirmationMessagePointsSingleShareToImports() {
        XCTAssertEqual(
            SharedImportInbox.shareConfirmationMessage(pendingCount: 1),
            "This book is waiting in Imports. Open BookLoom to choose Shelf and club destinations."
        )
    }

    func test_shareConfirmationMessagePointsMultipleSharesToImports() {
        XCTAssertEqual(
            SharedImportInbox.shareConfirmationMessage(pendingCount: 5),
            "5 books are waiting in Imports. Open BookLoom to choose Shelf and club destinations."
        )
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

    func test_fileMirrorKeepsQueueReadableWhenDefaultsAreEmpty() throws {
        let fileURL = makeTemporaryQueueFileURL()
        defer { try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent()) }
        let url = URL(string: "https://www.goodreads.com/book/show/99")!

        SharedImportInbox.enqueue(url, defaults: defaults, fileURL: fileURL)
        defaults.removeObject(forKey: SharedImportInbox.queueKey)

        XCTAssertEqual(SharedImportInbox.peekAll(defaults: defaults, fileURL: fileURL).map(\.url), [url])
        XCTAssertEqual(SharedImportInbox.pendingCount(defaults: defaults, fileURL: fileURL), 1)
    }

    func test_clearRemovesFileMirror() throws {
        let fileURL = makeTemporaryQueueFileURL()
        defer { try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent()) }
        let url = URL(string: "https://www.goodreads.com/book/show/100")!
        SharedImportInbox.enqueue(url, defaults: defaults, fileURL: fileURL)

        SharedImportInbox.clear(defaults: defaults, fileURL: fileURL)

        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))
        XCTAssertEqual(SharedImportInbox.pendingCount(defaults: defaults, fileURL: fileURL), 0)
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

    func test_updateWritesMetadataBackForMatchingURL() {
        let url = URL(string: "https://www.goodreads.com/book/show/77")!
        SharedImportInbox.enqueue(url, defaults: defaults)

        let written = SharedImportInbox.update(url, defaults: defaults) { entry in
            entry.title = "Piranesi"
            entry.author = "Susanna Clarke"
            entry.coverURLString = "https://covers.openlibrary.org/b/id/12345-L.jpg"
            entry.metadataFetchedAt = Date(timeIntervalSinceReferenceDate: 5_000)
        }

        XCTAssertTrue(written)
        let entry = SharedImportInbox.peekAll(defaults: defaults).first
        XCTAssertEqual(entry?.title, "Piranesi")
        XCTAssertEqual(entry?.author, "Susanna Clarke")
        XCTAssertEqual(entry?.coverURL?.absoluteString, "https://covers.openlibrary.org/b/id/12345-L.jpg")
        XCTAssertTrue(entry?.hasResolvedMetadata == true)
    }

    func test_updateReturnsFalseWhenURLIsNotInQueue() {
        let written = SharedImportInbox.update(URL(string: "https://www.goodreads.com/book/show/missing")!, defaults: defaults) { entry in
            entry.title = "should not write"
        }

        XCTAssertFalse(written)
        XCTAssertEqual(SharedImportInbox.pendingCount(defaults: defaults), 0)
    }

    func test_legacyEncodedEntryDecodesWithNilMetadata() throws {
        // Simulates an App-Group blob written before the metadata fields were
        // added: only the original two keys present. The new struct's optional
        // fields must decode as nil so users with pending pre-update shares
        // don't lose their queue.
        let enqueuedAt = Date(timeIntervalSinceReferenceDate: 760_000_000)
        let json = """
        [{"url":"https://www.goodreads.com/book/show/old","enqueuedAt":760000000.0}]
        """
        defaults.set(Data(json.utf8), forKey: SharedImportInbox.queueKey)

        // Pass `now` close to the encoded enqueuedAt so the 7-day TTL doesn't
        // prune the test fixture out from under us.
        let entries = SharedImportInbox.peekAll(defaults: defaults, now: enqueuedAt.addingTimeInterval(60))
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?.url.absoluteString, "https://www.goodreads.com/book/show/old")
        XCTAssertNil(entries.first?.title)
        XCTAssertNil(entries.first?.metadataFetchedAt)
        XCTAssertFalse(entries.first?.hasResolvedMetadata == true)
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

    private func makeTemporaryQueueFileURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("SharedImportInboxTests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent(SharedImportInbox.queueFileName, isDirectory: false)
    }
}
