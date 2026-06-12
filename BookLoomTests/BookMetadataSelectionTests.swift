import Foundation
import SwiftUI
import XCTest
@testable import BookLoom

/// Unit tests for `BookMetadataSelection.apply(_:)` — the shared write-back the
/// three metadata import controls (search, ISBN scan, Goodreads paste) funnel
/// through. It copies a chosen candidate's fields into the form's bindings.
///
/// The type wraps `@Binding` properties, so each test backs the bindings with
/// captured local `var`s (the standard way to drive a `Binding` outside
/// SwiftUI) and asserts on those locals after `apply`.
@MainActor
final class BookMetadataSelectionTests: XCTestCase {

    func test_apply_copiesTitleAuthorAndSelection() {
        var title = ""
        var author = ""
        var isbn = ""
        var selected: BookMetadataCandidate?
        let selection = BookMetadataSelection(
            title: Binding(get: { title }, set: { title = $0 }),
            author: Binding(get: { author }, set: { author = $0 }),
            isbn: Binding(get: { isbn }, set: { isbn = $0 }),
            selectedMetadata: Binding(get: { selected }, set: { selected = $0 })
        )

        let candidate = makeCandidate(
            title: "Piranesi",
            authors: ["Susanna Clarke"],
            isbn: "9781635575637"
        )
        selection.apply(candidate)

        XCTAssertEqual(title, "Piranesi")
        XCTAssertEqual(author, "Susanna Clarke", "Author is taken from the candidate's joined authorLine")
        XCTAssertEqual(isbn, "9781635575637")
        XCTAssertEqual(selected, candidate, "The applied candidate is retained as the selected metadata")
    }

    func test_apply_joinsMultipleAuthorsIntoAuthorLine() {
        var title = ""
        var author = ""
        var isbn = ""
        var selected: BookMetadataCandidate?
        let selection = BookMetadataSelection(
            title: Binding(get: { title }, set: { title = $0 }),
            author: Binding(get: { author }, set: { author = $0 }),
            isbn: Binding(get: { isbn }, set: { isbn = $0 }),
            selectedMetadata: Binding(get: { selected }, set: { selected = $0 })
        )

        selection.apply(makeCandidate(
            title: "Good Omens",
            authors: ["Terry Pratchett", "Neil Gaiman"],
            isbn: nil
        ))

        XCTAssertEqual(author, "Terry Pratchett, Neil Gaiman", "Multiple authors join with ', '")
    }

    func test_apply_leavesExistingISBNWhenCandidateHasNone() {
        var title = ""
        var author = ""
        var isbn = "existing-isbn"
        var selected: BookMetadataCandidate?
        let selection = BookMetadataSelection(
            title: Binding(get: { title }, set: { title = $0 }),
            author: Binding(get: { author }, set: { author = $0 }),
            isbn: Binding(get: { isbn }, set: { isbn = $0 }),
            selectedMetadata: Binding(get: { selected }, set: { selected = $0 })
        )

        // A candidate with no ISBN must not clobber an ISBN the user already
        // scanned/typed — `apply` only writes ISBN when the candidate has one.
        selection.apply(makeCandidate(title: "No ISBN Book", authors: ["A"], isbn: nil))

        XCTAssertEqual(isbn, "existing-isbn", "A nil candidate ISBN must preserve the existing field")
        XCTAssertEqual(title, "No ISBN Book", "Title is still applied even when ISBN is absent")
    }

    // MARK: - Helpers

    private func makeCandidate(
        title: String,
        authors: [String],
        isbn: String?
    ) -> BookMetadataCandidate {
        BookMetadataCandidate(
            provider: .openLibrary,
            externalID: "OL-test",
            title: title,
            authors: authors,
            publishedYear: 2020,
            isbn: isbn,
            coverURL: nil,
            description: nil,
            sourceURL: nil
        )
    }
}
