import Foundation
import SwiftData
import XCTest
@testable import BookLoom

/// `LibraryPaginationStore` lifts the iOS shelf's raw `context.fetch` paging out
/// of the view so the paging arithmetic, the "can load more" terminal state, and
/// the delete-backfill signal can be exercised without a live SwiftUI view.
///
/// The store takes an injectable `PageLoader`, so these tests page a fixed
/// in-memory array of real `LibraryBook` models (inserted into an in-memory
/// container so each has a stable `persistentModelID`).
@MainActor
final class LibraryPaginationStoreTests: XCTestCase {
    private var container: ModelContainer!

    override func setUpWithError() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(for: LibraryBook.self, configurations: config)
    }

    override func tearDown() {
        container = nil
        super.tearDown()
    }

    private func makeBooks(_ count: Int) -> [LibraryBook] {
        (0..<count).map { index in
            let book = LibraryBook(title: "Book \(index)")
            container.mainContext.insert(book)
            return book
        }
    }

    private func makeStore(books: [LibraryBook], pageSize: Int) -> LibraryPaginationStore {
        LibraryPaginationStore(pageSize: pageSize) { offset, limit in
            guard offset < books.count else { return [] }
            return Array(books[offset..<min(offset + limit, books.count)])
        }
    }

    func test_loadMore_loadsOnePageAtATime() {
        let books = makeBooks(5)
        let store = makeStore(books: books, pageSize: 2)

        XCTAssertTrue(store.canLoadMore)
        XCTAssertFalse(store.hasLoadedOnce)

        store.loadMore()
        XCTAssertEqual(store.books.count, 2)
        XCTAssertTrue(store.hasLoadedOnce)
        XCTAssertTrue(store.canLoadMore)

        store.loadMore()
        XCTAssertEqual(store.books.count, 4)
        XCTAssertTrue(store.canLoadMore)

        store.loadMore()
        XCTAssertEqual(store.books.count, 5)
        // Final partial page (< pageSize) means no more pages.
        XCTAssertFalse(store.canLoadMore)
    }

    func test_loadMore_stopsWhenLastPageExactlyFills() {
        let books = makeBooks(4)
        let store = makeStore(books: books, pageSize: 2)

        store.loadMore()
        store.loadMore()
        XCTAssertEqual(store.books.count, 4)
        // A full final page still reports canLoadMore; the next fetch returns
        // empty and terminates paging.
        XCTAssertTrue(store.canLoadMore)

        store.loadMore()
        XCTAssertEqual(store.books.count, 4)
        XCTAssertFalse(store.canLoadMore)
    }

    func test_loadMore_noopsAfterTerminated() {
        let books = makeBooks(1)
        let store = makeStore(books: books, pageSize: 10)

        store.loadMore()
        XCTAssertEqual(store.books.count, 1)
        XCTAssertFalse(store.canLoadMore)

        store.loadMore()
        XCTAssertEqual(store.books.count, 1)
    }

    func test_reset_clearsAndReloadsFirstPage() {
        let books = makeBooks(5)
        let store = makeStore(books: books, pageSize: 2)

        store.loadMore()
        store.loadMore()
        XCTAssertEqual(store.books.count, 4)

        store.reset()
        XCTAssertEqual(store.books.count, 2)
        XCTAssertTrue(store.canLoadMore)
    }

    func test_remove_signalsBackfillOnlyWhenEmptiedWithMoreAvailable() {
        let books = makeBooks(3)
        let store = makeStore(books: books, pageSize: 2)
        store.loadMore()
        XCTAssertEqual(store.books.count, 2)

        // Removing one of two loaded books leaves a non-empty page: no backfill.
        XCTAssertFalse(store.remove(id: books[0].persistentModelID))
        XCTAssertEqual(store.books.count, 1)

        // Removing the last loaded book while more pages remain: backfill.
        XCTAssertTrue(store.remove(id: books[1].persistentModelID))
        XCTAssertTrue(store.books.isEmpty)
    }

    func test_remove_doesNotSignalBackfillWhenNoMorePages() {
        let books = makeBooks(1)
        let store = makeStore(books: books, pageSize: 10)
        store.loadMore()
        XCTAssertFalse(store.canLoadMore)

        // Emptied but no further pages: caller should not loadMore.
        XCTAssertFalse(store.remove(id: books[0].persistentModelID))
        XCTAssertTrue(store.books.isEmpty)
    }
}
