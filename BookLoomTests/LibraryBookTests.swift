import XCTest
@testable import BookLoom

final class LibraryBookTests: XCTestCase {
    func test_pendingImportCopiesIntoPersonalLibraryBook() {
        let url = URL(string: "https://www.goodreads.com/book/show/35959740-circe")!
        var pending = SharedImportInbox.PendingImport(
            url: url,
            enqueuedAt: Date(timeIntervalSince1970: 100)
        )
        pending.title = "Circe"
        pending.author = "Madeline Miller"
        pending.isbn = "9780316556347"
        pending.externalProvider = BookMetadataProvider.goodreads.rawValue
        pending.externalID = "35959740"
        pending.coverURLString = "https://example.com/circe.jpg"
        pending.metadataFetchedAt = Date(timeIntervalSince1970: 200)

        let book = LibraryBook.fromPendingImport(pending, now: Date(timeIntervalSince1970: 300))

        XCTAssertEqual(book.title, "Circe")
        XCTAssertEqual(book.author, "Madeline Miller")
        XCTAssertEqual(book.isbn, "9780316556347")
        XCTAssertEqual(book.externalProvider, BookMetadataProvider.goodreads.rawValue)
        XCTAssertEqual(book.externalID, "35959740")
        XCTAssertEqual(book.sourceURLString, url.absoluteString)
        XCTAssertTrue(book.matchesPendingImport(pending))
    }

    func test_ownershipBadgesSummarizeDesktopManagementState() {
        let book = LibraryBook(title: "Piranesi", author: "Susanna Clarke")
        book.didRead = true
        book.didListenToAudiobook = true
        book.isSigned = true
        book.isOnLoan = true
        book.loanedTo = "Owen"
        book.intendedRecipient = "Sam"
        book.purchasePriceCents = 2800
        book.purchaseCurrencyCode = "USD"

        XCTAssertTrue(book.ownershipBadges.contains("Read"))
        XCTAssertTrue(book.ownershipBadges.contains("Listened"))
        XCTAssertTrue(book.ownershipBadges.contains("Signed"))
        XCTAssertTrue(book.ownershipBadges.contains("On loan"))
        XCTAssertTrue(book.ownershipBadges.contains("Gift planned"))
        XCTAssertFalse(book.ownershipBadges.isEmpty)
    }

    func test_submissionCanBeCopiedIntoPersonalLibraryBook() {
        let submission = BookSubmission(
            title: "Project Hail Mary",
            author: "Andy Weir",
            isbn: "9780593135204",
            coverURL: "https://example.com/hail-mary.jpg",
            externalProvider: BookMetadataProvider.openLibrary.rawValue,
            externalID: "/works/OL21745884W"
        )

        let book = LibraryBook.fromSubmission(submission)

        XCTAssertEqual(book.title, submission.title)
        XCTAssertEqual(book.author, submission.author)
        XCTAssertEqual(book.isbn, submission.isbn)
        XCTAssertTrue(book.matchesSubmission(submission))
    }
}
