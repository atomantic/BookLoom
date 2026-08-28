import Foundation
import SwiftData

/// Metadata and installation identity for the free, author-hosted Accelerando
/// edition. The book text itself stays in the local download cache rather than
/// in SwiftData/iCloud.
enum AccelerandoBook {
    static let identifier = "accelerando"
    static let provider = "Accelerando"
    static let title = "Accelerando"
    static let author = "Charles Stross"
    static let sourceURL = URL(string: "https://www.antipope.org/charlie/blog-static/fiction/accelerando/accelerando.html")!
    static let sourcePageURL = URL(string: "https://www.antipope.org/charlie/blog-static/fiction/accelerando/accelerando-intro.html")!
    static let licenseURL = URL(string: "https://creativecommons.org/licenses/by-nc-nd/2.5/")!
    static let licenseName = "CC BY-NC-ND 2.5"
    static let coverURL = URL(string: "https://covers.openlibrary.org/b/id/284259-L.jpg?default=false")!
    static let installationDefaultsKey = "bookloom.accelerando-default-installed-v1"

    static func matches(_ book: LibraryBook) -> Bool {
        if book.externalProvider == provider && book.externalID == identifier {
            return true
        }
        return book.title.trimmed.caseInsensitiveCompare(title) == .orderedSame
            && book.author.localizedCaseInsensitiveContains(author)
    }

    static func makeShelfBook(now: Date = .now) -> LibraryBook {
        let book = LibraryBook(
            title: title,
            author: author,
            isbn: "0441012841",
            bookDescription: "A free author-hosted edition of Charles Stross's dense, idea-driven science fiction novel about accelerating technological change.",
            publishedYear: 2005,
            coverURL: coverURL.absoluteString,
            externalProvider: provider,
            externalID: identifier,
            sourceURLString: sourceURL.absoluteString,
            addedAt: now
        )
        book.format = .ebook
        book.condition = .new
        book.shelfLocation = "Digital Shelf"
        book.isOwned = true
        book.isWishlist = false
        return book
    }

    /// Installs the default shelf entry once it is absent. A title/author match
    /// also recognizes an Accelerando the reader already added manually, so an
    /// upgrade never creates a duplicate.
    @MainActor
    static func ensureOnShelf(context: ModelContext) throws -> LibraryBook? {
        let books = try context.fetch(FetchDescriptor<LibraryBook>())
        if let existing = books.first(where: matches) {
            UserDefaults.standard.set(true, forKey: installationDefaultsKey)
            return existing
        }
        guard !UserDefaults.standard.bool(forKey: installationDefaultsKey) else {
            return nil
        }

        let book = makeShelfBook()
        context.insert(book)
        do {
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
        UserDefaults.standard.set(true, forKey: installationDefaultsKey)
        return book
    }
}

extension LibraryBook {
    var isAccelerando: Bool {
        AccelerandoBook.matches(self)
    }
}
