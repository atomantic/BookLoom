import Foundation
import SwiftData
import SwiftUI

/// Paginated loader for the iOS shelf. Lifts the raw `context.fetch` paging that
/// previously lived as private methods on `LibraryTabView` (and was therefore
/// untestable) into a standalone `@Observable` store.
///
/// The fetch is injected as a closure so the paging logic can be exercised in
/// unit tests without a live `ModelContext`.
@Observable
@MainActor
final class LibraryPaginationStore {
    /// Loads one page of books. `offset` is the number already loaded; `limit`
    /// is the page size. Throwing surfaces as a halted load (no more paging).
    typealias PageLoader = (_ offset: Int, _ limit: Int) throws -> [LibraryBook]

    private(set) var books: [LibraryBook] = []
    private(set) var canLoadMore = true
    private(set) var hasLoadedOnce = false
    private(set) var isLoading = false

    let pageSize: Int
    private let loadPage: PageLoader

    init(pageSize: Int = 80, loadPage: @escaping PageLoader) {
        self.pageSize = pageSize
        self.loadPage = loadPage
    }

    /// Convenience initializer that pages a `LibraryBook` query out of a
    /// SwiftData context, sorted by most-recently-updated.
    convenience init(context: ModelContext, pageSize: Int = 80) {
        self.init(pageSize: pageSize) { offset, limit in
            var descriptor = FetchDescriptor<LibraryBook>(
                sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
            )
            descriptor.fetchLimit = limit
            descriptor.fetchOffset = offset
            return try context.fetch(descriptor)
        }
    }

    /// Clears loaded books and fetches the first page again.
    func reset() {
        books = []
        canLoadMore = true
        loadMore()
    }

    /// Loads the next page if there is one and a load is not already running.
    func loadMore() {
        guard canLoadMore, !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        hasLoadedOnce = true
        do {
            let nextPage = try loadPage(books.count, pageSize)
            books.append(contentsOf: nextPage)
            canLoadMore = nextPage.count == pageSize
        } catch {
            canLoadMore = false
            assertionFailure("Failed to load library books: \(error.localizedDescription)")
        }
    }

    /// Loads the next page when `book` is the last currently-visible book.
    func loadMoreIfNeeded(after book: LibraryBook, visibleBooks: [LibraryBook]) {
        guard visibleBooks.last?.persistentModelID == book.persistentModelID else { return }
        loadMore()
    }

    /// Removes a book from the loaded page set (used after a delete) and reports
    /// whether the caller should trigger another `loadMore` to backfill.
    @discardableResult
    func remove(id: PersistentIdentifier) -> Bool {
        books.removeAll { $0.persistentModelID == id }
        return books.isEmpty && canLoadMore
    }
}
