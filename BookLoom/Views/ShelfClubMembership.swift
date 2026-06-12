#if os(iOS)
import Foundation

/// Shared shelf-to-club types used by the iOS shelf screens. `LibraryTabView`
/// produces a `ShelfClubAddOutcome` from `addToClub(_:)` and decides club
/// membership via `containsLibraryBook`; `MobileLibraryBookDetailView` surfaces
/// the outcome in an alert and uses the same membership check. They live here,
/// not in either view, so neither view "owns" logic the other depends on.

/// Outcome of attempting to add a shelf book to the active club's proposals.
enum ShelfClubAddOutcome: Equatable {
    case added(String)
    case alreadyAdded(String)
    case failed(String)

    var title: String {
        switch self {
        case .added:
            "Added to Club"
        case .alreadyAdded:
            "Already in Club"
        case .failed:
            "Couldn't Add to Club"
        }
    }

    var message: String {
        switch self {
        case .added(let clubName):
            "This book is now in \(clubName)'s proposals."
        case .alreadyAdded(let clubName):
            "This book is already in \(clubName)'s proposals or reading history."
        case .failed(let message):
            message
        }
    }
}

extension BookClub {
    func containsLibraryBook(_ book: LibraryBook) -> Bool {
        (submissions ?? []).contains { $0.matchesLibraryBook(book) }
    }
}

extension BookSubmission {
    func matchesLibraryBook(_ book: LibraryBook) -> Bool {
        if book.matchesSubmission(self) {
            return true
        }

        let bookISBN = book.isbn.trimmed.lowercased()
        let submissionISBN = isbn.trimmed.lowercased()
        if !bookISBN.isEmpty, bookISBN == submissionISBN {
            return true
        }

        let bookTitle = book.title.trimmed.lowercased()
        let submissionTitle = title.trimmed.lowercased()
        guard !bookTitle.isEmpty, bookTitle == submissionTitle else {
            return false
        }

        let bookAuthor = book.author.trimmed.lowercased()
        let submissionAuthor = author.trimmed.lowercased()
        return bookAuthor.isEmpty || submissionAuthor.isEmpty || bookAuthor == submissionAuthor
    }
}

/// Compact card-style labels for a book format, shared by the iOS shelf row and
/// the detail view.
extension LibraryBookFormat {
    var cardLabel: String {
        switch self {
        case .hardcover: "Hardback"
        case .paperback: "Paperback"
        case .ebook: "E-book"
        case .audiobook: "Audio"
        case .other: "Other"
        }
    }

    var cardSystemImage: String {
        switch self {
        case .hardcover: "book.closed.fill"
        case .paperback: "book.fill"
        case .ebook: "ipad"
        case .audiobook: "headphones"
        case .other: "bookmark.fill"
        }
    }
}

#endif
