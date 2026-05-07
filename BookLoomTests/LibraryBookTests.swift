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

    func test_ratingMarksBookRead() {
        let book = LibraryBook(title: "Piranesi", author: "Susanna Clarke")

        book.setPersonalRatingStars(4)

        XCTAssertEqual(book.personalRatingStars, 4)
        XCTAssertTrue(book.didRead)
    }

    func test_wishlistBookSurfacesWishlistBadge() {
        let book = LibraryBook(title: "The Bee Sting", author: "Paul Murray")
        XCTAssertFalse(book.isWishlist)
        XCTAssertFalse(book.ownershipBadges.contains("Wishlist"))

        book.isWishlist = true

        XCTAssertTrue(book.isWishlist)
        XCTAssertTrue(book.ownershipBadges.contains("Wishlist"))
    }

    func test_applyingMetadataRefreshesBookDetails() {
        let sourceURL = URL(string: "https://openlibrary.org/works/OL20893680W")!
        let coverURL = URL(string: "https://covers.openlibrary.org/b/id/10226290-L.jpg")!
        let candidate = BookMetadataCandidate(
            provider: .openLibrary,
            externalID: "/works/OL20893680W",
            title: "Piranesi",
            authors: ["Susanna Clarke"],
            publishedYear: 2020,
            isbn: "9781635575637",
            coverURL: coverURL,
            description: "A house with endless halls.",
            sourceURL: sourceURL
        )
        let book = LibraryBook(title: "Wrong title", author: "Wrong author")

        book.applyMetadata(candidate)

        XCTAssertEqual(book.title, "Piranesi")
        XCTAssertEqual(book.author, "Susanna Clarke")
        XCTAssertEqual(book.isbn, "9781635575637")
        XCTAssertEqual(book.coverURL, coverURL.absoluteString)
        XCTAssertEqual(book.sourceURLString, sourceURL.absoluteString)
    }
}
